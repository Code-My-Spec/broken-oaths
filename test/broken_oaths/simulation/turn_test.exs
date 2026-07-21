defmodule BrokenOaths.Simulation.TurnTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Technology.Research
  alias BrokenOaths.Simulation.Turn
  alias BrokenOaths.Vision.Visibility
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.World

  @frequency 8
  @seed 424_242

  # Timer inversion default is economy_turns 10, but most of these tests
  # assume the economy (production/research/growth/income) advances every
  # turn — pin to 1 (behavior-preserving); the "timer inversion" describe
  # below builds its own world with a real economy_turns.
  defp world, do: %World{seed: @seed, frequency: @frequency, economy_turns: 1}

  defp unit(id, opts) do
    max_movement = Keyword.get(opts, :max_movement, 2)
    max_hp = Keyword.get(opts, :max_hp, 10)

    %{
      id: id,
      player_id: Keyword.get(opts, :player_id, 1),
      type: Keyword.get(opts, :type, :settler),
      tile_id: Keyword.fetch!(opts, :tile),
      hp: Keyword.get(opts, :hp, max_hp),
      max_hp: max_hp,
      movement: Keyword.get(opts, :movement, max_movement),
      max_movement: max_movement
    }
  end

  defp base_state(units, orders \\ %{}) do
    player_ids = units |> Map.values() |> Enum.map(& &1.player_id) |> Enum.uniq()
    players = Map.new(player_ids, &{&1, %{id: &1, user_id: &1, region_id: 0, gold: 50}})

    %{
      world: world(),
      turn: 0,
      units: units,
      orders: orders,
      players: players,
      explored: %{},
      cities: %{},
      improvements: %{}
    }
  end

  defp city(id, opts) do
    %{
      id: id,
      player_id: Keyword.get(opts, :player_id, 1),
      tile_id: Keyword.fetch!(opts, :tile),
      name: Keyword.get(opts, :name, "City #{id}"),
      size: Keyword.get(opts, :size, 1),
      food: Keyword.get(opts, :food, 0),
      # Story 895: `CityDefense.regen/1` (wired into `Turn.regen_cities/2`)
      # requires city HP — `Game.City`'s own schema defaults a freshly
      # founded city to `CityDefense.max_hp/0` (100), so plain test-built
      # city maps mirror that same default here.
      hp: Keyword.get(opts, :hp, 100),
      territory: Keyword.get(opts, :territory, [Keyword.fetch!(opts, :tile)]),
      worked_tiles: Keyword.get(opts, :worked_tiles, []),
      queue: Keyword.get(opts, :queue, [])
    }
  end

  describe "tick/1 turn counter" do
    test "advances the turn and returns a turn_advanced event" do
      {new_state, events} = Turn.tick(base_state(%{}))

      assert new_state.turn == 1
      assert {:turn_advanced, 1} in events
    end

    test "advances by one from any starting turn" do
      state = %{base_state(%{}) | turn: 41}
      {new_state, events} = Turn.tick(state)

      assert new_state.turn == 42
      assert {:turn_advanced, 42} in events
    end
  end

  describe "tick/1 timer inversion — movement every tick, economy on economy_turns" do
    test "movement recharges every tick, regardless of economy_turns" do
      u = unit(1, tile: 5, movement: 0, max_movement: 2)
      world3 = %World{seed: @seed, frequency: @frequency, economy_turns: 3}
      state = %{base_state(%{1 => u}) | world: world3}

      # Turn 1 (rem 1,3 != 0, economy frozen): movement still recharges.
      {after_t1, _} = Turn.tick(state)
      assert after_t1.units[1].movement == 2

      # Spend it again, tick to turn 2 (still rem != 0): recharges again.
      spent = %{after_t1 | units: %{1 => %{after_t1.units[1] | movement: 0}}}
      {after_t2, _} = Turn.tick(spent)
      assert after_t2.units[1].movement == 2
    end

    test "economy_turns: 3 freezes production for two ticks, then accrues on the 3rd" do
      c = city(1, tile: 1, queue: [%{id: 10, type: :warrior, banked: 0, cost: 40}])
      world3 = %World{seed: @seed, frequency: @frequency, economy_turns: 3}
      state = %{base_state(%{}) | world: world3, cities: %{1 => c}}

      # Turns 1 and 2 (rem != 0): the economy is frozen — banked production
      # doesn't move.
      {after_t1, _} = Turn.tick(state)
      assert after_t1.cities[1].queue == [%{id: 10, type: :warrior, banked: 0, cost: 40}]

      {after_t2, _} = Turn.tick(after_t1)
      assert after_t2.cities[1].queue == [%{id: 10, type: :warrior, banked: 0, cost: 40}]

      # Turn 3 (rem == 0): the economy runs — the flat 5/turn base (story
      # 879) finally banks.
      {after_t3, _} = Turn.tick(after_t2)
      assert [%{banked: 5}] = after_t3.cities[1].queue
    end
  end

  describe "tick/1 movement" do
    test "resets movement to max_movement before consuming the path" do
      # movement is 0 going in (spent last tick); max_movement is 2, and a
      # 2-hex path should still fully resolve this tick. Path tiles 9 and
      # 11 are both OPEN (cost 1, story 925) — this test is about the
      # reset, not terrain cost (see the "terrain & road cost" describe
      # below for that).
      u = unit(1, tile: 5, movement: 0, max_movement: 2)
      order = %{kind: :move, path: [9, 11], status: :pending}
      state = base_state(%{1 => u}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 11
      refute Map.has_key?(new_state.orders, 1)
    end

    test "a unit advances up to its movement rate; a longer path stays pending" do
      # Path tiles 9, 11, 12 are all OPEN (cost 1, story 925).
      u = unit(1, tile: 5, max_movement: 2)
      order = %{kind: :move, path: [9, 11, 12], status: :pending}
      state = base_state(%{1 => u}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 11
      assert new_state.units[1].movement == 0
      assert new_state.orders[1] == %{kind: :move, path: [12], status: :pending}
    end

    test "arrival (path fully consumed) removes the order" do
      # Path tiles 9, 11 are both OPEN (cost 1, story 925).
      u = unit(1, tile: 5, max_movement: 3)
      order = %{kind: :move, path: [9, 11], status: :pending}
      state = base_state(%{1 => u}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 11
      assert new_state.units[1].movement == 1
      refute Map.has_key?(new_state.orders, 1)
    end

    test "a unit with no order does not move and keeps full movement" do
      u = unit(1, tile: 5, max_movement: 2)
      state = base_state(%{1 => u})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 5
      assert new_state.units[1].movement == 2
    end

    test "a path whose first step is the unit's own current tile is blocked" do
      u = unit(1, tile: 5, max_movement: 1)
      order = %{kind: :move, path: [5], status: :pending}
      state = base_state(%{1 => u}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 5
      assert new_state.orders[1].status == :interrupted
    end
  end

  # Story 925 — terrain costs movement (Civ 6 model) and a completed Road
  # negates it. Tile relationships below are verified against `Regions`/
  # `Terrain` directly (same "never hardcoded blind" discipline
  # `unit_test.exs`'s own `bfs_path/4` tests use), all in the SAME
  # fixture world (`@seed`/`@frequency`) these `tick/1` tests already
  # share: tile 1's own neighbors include tile 9 (open — snow, flat,
  # cost 1) and tile 10 (DIFFICULT — snow hills, cost 2); tile 10's own
  # neighbors include tile 11 (open, cost 1).
  describe "tick/1 movement — terrain & road cost (story 925)" do
    test "entering an open tile spends 1 movement point, same as before" do
      u = unit(1, tile: 1, max_movement: 2)
      order = %{kind: :move, path: [9], status: :pending}
      state = base_state(%{1 => u}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 9
      assert new_state.units[1].movement == 1
      refute Map.has_key?(new_state.orders, 1)
    end

    test "entering a DIFFICULT (hills) tile spends 2 movement points" do
      u = unit(1, tile: 1, max_movement: 2)
      order = %{kind: :move, path: [10], status: :pending}
      state = base_state(%{1 => u}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 10
      assert new_state.units[1].movement == 0
      refute Map.has_key?(new_state.orders, 1)
    end

    test "the Civ 6 min-1 rule: a movement-1 unit still enters a cost-2 tile, ending at 0 rather than being stuck" do
      u = unit(1, tile: 1, max_movement: 1)
      order = %{kind: :move, path: [10], status: :pending}
      state = base_state(%{1 => u}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 10
      assert new_state.units[1].movement == 0
      refute Map.has_key?(new_state.orders, 1)
    end

    test "a completed Road on the DIFFICULT tile drops its cost to 1, letting the unit reach further this turn" do
      u = unit(1, tile: 1, max_movement: 2)
      order = %{kind: :move, path: [10, 11], status: :pending}

      state =
        %{1 => u}
        |> base_state(%{1 => order})
        |> Map.put(:roads, %{
          10 => %{tile_id: 10, kind: :road, progress: 4, status: :complete, builder_unit_id: nil}
        })

      {new_state, _events} = Turn.tick(state)

      # Without the road, entering 10 alone (cost 2) would spend the
      # unit's entire turn — see the DIFFICULT-tile test above. With the
      # road (cost 1), the SAME 2 movement points also cover the open
      # tile 11 right after.
      assert new_state.units[1].tile_id == 11
      assert new_state.units[1].movement == 0
      refute Map.has_key?(new_state.orders, 1)
    end

    test "a road still :building (not yet complete) grants nothing" do
      u = unit(1, tile: 1, max_movement: 2)
      order = %{kind: :move, path: [10], status: :pending}

      state =
        %{1 => u}
        |> base_state(%{1 => order})
        |> Map.put(:roads, %{
          10 => %{tile_id: 10, kind: :road, progress: 1, status: :building, builder_unit_id: nil}
        })

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 10
      assert new_state.units[1].movement == 0
    end

    # Story 931 — the Scout ignores difficult-terrain movement cost
    # entirely (Civ 6's recon trait): the SAME DIFFICULT tile 10 a
    # Warrior pays 2 for (see the test above) costs a Scout only 1,
    # letting it reach further on the same turn's movement.
    test "a Scout pays only 1 to enter a DIFFICULT (hills) tile, where a Warrior pays 2" do
      u = unit(1, tile: 1, type: :scout, max_movement: 3)
      order = %{kind: :move, path: [10, 11], status: :pending}
      state = base_state(%{1 => u}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      # Without the recon trait, entering DIFFICULT tile 10 (cost 2)
      # then open tile 11 (cost 1) would spend 3 of 3 movement exactly
      # like a Warrior would need 2 + 1 = 3 too — this instead confirms
      # the SCOUT's own flat 1-per-tile cost by spending only 2 of 3 to
      # cover the same two hexes, arriving with 1 left over.
      assert new_state.units[1].tile_id == 11
      assert new_state.units[1].movement == 1
      refute Map.has_key?(new_state.orders, 1)
    end

    test "a Scout still pays 1 on open terrain, same as everyone else" do
      u = unit(1, tile: 1, type: :scout, max_movement: 2)
      order = %{kind: :move, path: [9], status: :pending}
      state = base_state(%{1 => u}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 9
      assert new_state.units[1].movement == 1
      refute Map.has_key?(new_state.orders, 1)
    end
  end

  # Story 920 rework — `Movement.advance_fortify/1` runs right after
  # `resolve_orders/1` in `Turn.tick/1`, so a unit's own `fortified_turns`
  # (defaulting to 0 via `Map.get/3` for the shared `unit/2` fixture
  # above, which carries no such key) only ramps when it actually held
  # still THIS tick — a mover's own fresh 0 (set by `apply_positions/3`)
  # is never bumped back up.
  describe "tick/1 Fortify ramp (story 920, Civ 6 ramp)" do
    test "a unit with no order (holding fortify) ramps from 1 (partial) to 2 (full)" do
      u = unit(1, tile: 5, max_movement: 2) |> Map.put(:fortified_turns, 1)
      state = base_state(%{1 => u})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].fortified_turns == 2
    end

    test "the ramp caps at 2 — an already-full unit stays at 2 across another boundary" do
      u = unit(1, tile: 5, max_movement: 2) |> Map.put(:fortified_turns, 2)
      state = base_state(%{1 => u})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].fortified_turns == 2
    end

    test "a unit that actually displaces this tick ends it at 0, never ramped" do
      # Path tiles 9, 11 are both OPEN (cost 1, story 925).
      u = unit(1, tile: 5, max_movement: 2) |> Map.put(:fortified_turns, 1)
      order = %{kind: :move, path: [9, 11], status: :pending}
      state = base_state(%{1 => u}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 11
      assert new_state.units[1].fortified_turns == 0
    end

    test "a unit whose own step is blocked in place keeps and ramps its fortify, same as never having an order" do
      u = unit(1, tile: 5, max_movement: 1) |> Map.put(:fortified_turns, 1)
      order = %{kind: :move, path: [5], status: :pending}
      state = base_state(%{1 => u}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 5
      assert new_state.units[1].fortified_turns == 2
    end

    test "a unit that never fortified (no key at all, like every other tick_test.exs fixture) is left untouched" do
      u = unit(1, tile: 5, max_movement: 2)
      state = base_state(%{1 => u})

      {new_state, _events} = Turn.tick(state)

      # `advance_fortify/1` never ADDS the key (`bump_fortify/1`'s own
      # `0 -> unit` clause returns the unit as-is) — same `Map.get/3`
      # default (0, not fortified) every other reader of this field
      # already uses.
      assert Map.get(new_state.units[1], :fortified_turns, 0) == 0
    end
  end

  describe "tick/1 simultaneous conflict resolution" do
    test "two units converging on the same tile resolve to exactly one occupant, lowest id wins" do
      u1 = unit(1, tile: 1, max_movement: 1)
      u2 = unit(2, tile: 2, max_movement: 1)
      order1 = %{kind: :move, path: [50], status: :pending}
      order2 = %{kind: :move, path: [50], status: :pending}
      state = base_state(%{1 => u1, 2 => u2}, %{1 => order1, 2 => order2})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 50
      refute Map.has_key?(new_state.orders, 1)

      assert new_state.units[2].tile_id == 2
      assert new_state.orders[2] == %{kind: :move, path: [50], status: :interrupted}
    end

    test "the outcome is deterministic across repeated resolution of the same state" do
      u1 = unit(1, tile: 1, max_movement: 1)
      u2 = unit(2, tile: 2, max_movement: 1)

      orders = %{
        1 => %{kind: :move, path: [50], status: :pending},
        2 => %{kind: :move, path: [50], status: :pending}
      }

      state = base_state(%{1 => u1, 2 => u2}, orders)

      {first, _} = Turn.tick(state)
      {second, _} = Turn.tick(state)

      assert first.units == second.units
      assert first.orders == second.orders
    end
  end

  describe "tick/1 path interruption" do
    test "a stationary unit with no order blocks an incoming step" do
      mover = unit(1, tile: 5, max_movement: 1)
      blocker = unit(2, tile: 20, max_movement: 1)
      order = %{kind: :move, path: [20], status: :pending}
      state = base_state(%{1 => mover, 2 => blocker}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 5
      assert new_state.orders[1] == %{kind: :move, path: [20], status: :interrupted}
      assert new_state.units[2].tile_id == 20
    end

    test "a path blocked mid-journey halts the unit and preserves the full remaining path" do
      mover = unit(1, tile: 5, max_movement: 3)
      blocker = unit(2, tile: 20, max_movement: 0)
      order = %{kind: :move, path: [10, 20, 30], status: :pending}
      state = base_state(%{1 => mover, 2 => blocker}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 10
      assert new_state.orders[1] == %{kind: :move, path: [20, 30], status: :interrupted}
    end

    test "an interrupted order auto-resumes and completes when the tile is clear (task 16)" do
      mover = unit(1, tile: 5, max_movement: 2)
      order = %{kind: :move, path: [20], status: :interrupted}
      state = base_state(%{1 => mover}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      # Nothing blocks tile 20 now, so the retried interrupted order runs:
      # the mover advances and the finished order is dropped.
      assert new_state.units[1].tile_id == 20
      refute Map.has_key?(new_state.orders, 1)
    end

    test "a blocked order stays interrupted, then resumes once the blocker leaves (task 16)" do
      mover = unit(1, tile: 5, max_movement: 1)
      blocker = unit(2, tile: 20, max_movement: 0)
      order = %{kind: :move, path: [20], status: :pending}
      blocked_state = base_state(%{1 => mover, 2 => blocker}, %{1 => order})

      # Tick 1: tile 20 is occupied -> mover halts, order interrupted.
      {interrupted, _} = Turn.tick(blocked_state)
      assert interrupted.units[1].tile_id == 5
      assert interrupted.orders[1].status == :interrupted

      # The blocker leaves; tick 2 retries the interrupted order and it moves.
      cleared = %{interrupted | units: Map.delete(interrupted.units, 2)}
      {resumed, _} = Turn.tick(cleared)
      assert resumed.units[1].tile_id == 20
      refute Map.has_key?(resumed.orders, 1)
    end
  end

  # v0.2.1 playtest issue 5df5de88 — "1 non-combat unit should stack
  # with 1 combat unit". `unit/2` defaults to `:settler` (non-combat);
  # these tests spell out `:warrior` (combat) explicitly for clarity.
  describe "tick/1 field civilian/combat stacking (issue 5df5de88)" do
    test "a non-combat mover joins a tile already holding its owner's lone combat unit" do
      warrior = unit(2, tile: 20, type: :warrior, max_movement: 0)
      mover = unit(1, tile: 5, type: :settler, max_movement: 1)
      order = %{kind: :move, path: [20], status: :pending}
      state = base_state(%{1 => mover, 2 => warrior}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 20
      refute Map.has_key?(new_state.orders, 1)
      assert new_state.units[2].tile_id == 20
    end

    test "a combat mover joins a tile already holding its owner's lone non-combat unit" do
      settler = unit(2, tile: 20, type: :settler, max_movement: 0)
      mover = unit(1, tile: 5, type: :warrior, max_movement: 1)
      order = %{kind: :move, path: [20], status: :pending}
      state = base_state(%{1 => mover, 2 => settler}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 20
      refute Map.has_key?(new_state.orders, 1)
      assert new_state.units[2].tile_id == 20
    end

    test "two units of the same combat class still do not stack" do
      blocker = unit(2, tile: 20, type: :warrior, max_movement: 0)
      mover = unit(1, tile: 5, type: :warrior, max_movement: 1)
      order = %{kind: :move, path: [20], status: :pending}
      state = base_state(%{1 => mover, 2 => blocker}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 5
      assert new_state.orders[1] == %{kind: :move, path: [20], status: :interrupted}
    end

    test "a tile already holding one of each class is full — a third mover is blocked" do
      warrior = unit(2, tile: 20, type: :warrior, max_movement: 0)
      settler = unit(3, tile: 20, type: :settler, max_movement: 0)
      mover = unit(1, tile: 5, type: :worker, max_movement: 1)
      order = %{kind: :move, path: [20], status: :pending}
      state = base_state(%{1 => mover, 2 => warrior, 3 => settler}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 5
      assert new_state.orders[1] == %{kind: :move, path: [20], status: :interrupted}
    end

    test "an opposite-class occupant belonging to ANOTHER player grants no stacking room" do
      enemy_warrior = unit(2, tile: 20, type: :warrior, player_id: 2, max_movement: 0)
      mover = unit(1, tile: 5, type: :settler, player_id: 1, max_movement: 1)
      order = %{kind: :move, path: [20], status: :pending}
      state = base_state(%{1 => mover, 2 => enemy_warrior}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 5
      assert new_state.orders[1] == %{kind: :move, path: [20], status: :interrupted}
    end
  end

  describe "tick/1 exploration" do
    test "explored grows to cover the unit's post-move vision" do
      mover = unit(1, tile: 0, max_movement: 1, type: :lord)
      [target | _] = Regions.adjacent_tiles(world(), 0)
      order = %{kind: :move, path: [target], status: :pending}
      state = base_state(%{1 => mover}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      expected = Visibility.visible_tiles(world(), [%{type: :lord, tile_id: target}])
      assert new_state.explored[1] == expected
    end

    test "explored accumulates across ticks rather than resetting" do
      far_tile = 300
      mover = unit(1, tile: 0, max_movement: 0, type: :settler)
      state = %{base_state(%{1 => mover}) | explored: %{1 => MapSet.new([far_tile])}}

      {new_state, _events} = Turn.tick(state)

      assert far_tile in new_state.explored[1]
    end

    test "a player with no units has an empty, unchanged explored set" do
      state = base_state(%{}, %{})

      state = %{
        state
        | players: %{1 => %{id: 1, user_id: 1, region_id: 0, gold: 50}},
          explored: %{}
      }

      {new_state, _events} = Turn.tick(state)

      assert new_state.explored[1] == MapSet.new()
    end
  end

  describe "tick/1 production and spawn placement" do
    test "a completed item spawns on the city's own tile when free, as a spawn event" do
      c = city(1, tile: 1, queue: [%{id: 10, type: :warrior, banked: 35, cost: 40}])
      state = %{base_state(%{}) | cities: %{1 => c}}

      {new_state, events} = Turn.tick(state)

      assert new_state.cities[1].queue == []
      assert {:unit_spawned, %{player_id: 1, type: :warrior, tile_id: 1}} in events
      # Turn never allocates a real unit id itself — only the caller can.
      assert new_state.units == %{}
    end

    test "an occupied city tile places the unit on a free adjacent tile instead" do
      c = city(1, tile: 1, queue: [%{id: 10, type: :warrior, banked: 40, cost: 40}])
      blocker = unit(99, tile: 1, player_id: 2, type: :lord)
      state = %{base_state(%{99 => blocker}) | cities: %{1 => c}}

      {new_state, events} = Turn.tick(state)

      assert [{:unit_spawned, %{tile_id: landed}}] =
               Enum.filter(events, &match?({:unit_spawned, _}, &1))

      refute landed == 1
      assert landed in Regions.adjacent_tiles(world(), 1)
      assert new_state.cities[1].queue == []
    end

    test "a fully blocked city keeps its item queued without losing banked production" do
      land_neighbors =
        world()
        |> Regions.adjacent_tiles(1)
        |> Enum.filter(&(Regions.tile_class(world(), &1) == :land))

      blockers =
        [1 | land_neighbors]
        |> Enum.with_index(100)
        |> Map.new(fn {tile, id} -> {id, unit(id, tile: tile, player_id: 2, type: :lord)} end)

      c = city(1, tile: 1, queue: [%{id: 10, type: :warrior, banked: 40, cost: 40}])
      state = %{base_state(blockers) | cities: %{1 => c}}

      {new_state, events} = Turn.tick(state)

      refute Enum.any?(events, &match?({:unit_spawned, _}, &1))
      assert [%{banked: banked}] = new_state.cities[1].queue
      assert banked >= 45
    end

    # Regression for issue 63300098: a settler's population cost
    # (`Production.apply_pop_cost/3`, resolved in phase 3) used to get
    # silently refunded by growth (phase 5) resolving in the SAME tick
    # once a well-fed city crossed its next threshold — `size` never
    # visibly dropped from the outside. Growth for a city that just
    # settled THIS tick is now suppressed for that one boundary.
    test "a settler's pop cost survives the same tick's growth for a well-fed city" do
      c =
        city(1,
          tile: 1,
          size: 2,
          # Comfortably past size 2's own growth threshold (30) even
          # before this tick's own food accrual adds more.
          food: 500,
          territory: [1],
          queue: [%{id: 10, type: :settler, banked: 100, cost: 100}]
        )

      state = %{base_state(%{}) | cities: %{1 => c}}

      {new_state, events} = Turn.tick(state)

      assert {:unit_spawned, %{player_id: 1, type: :settler, tile_id: 1}} in events
      # Settled from size 2 -> 1; growth this same tick is suppressed,
      # so it must NOT bounce back up to 2.
      assert new_state.cities[1].size == 1
    end

    test "a well-fed city with no settler completing still grows normally" do
      c = city(1, tile: 1, size: 2, food: 500, territory: [1])
      state = %{base_state(%{}) | cities: %{1 => c}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.cities[1].size == 3
    end
  end

  describe "tick/1 improvement progress" do
    test "advances progress when the declared builder is still on the tile" do
      worker = unit(1, tile: 100, type: :worker)

      improvement = %{
        tile_id: 100,
        kind: :farm,
        progress: 1,
        status: :building,
        builder_unit_id: 1
      }

      state = %{base_state(%{1 => worker}) | improvements: %{100 => improvement}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.improvements[100].progress == 2
      assert new_state.improvements[100].status == :building
    end

    test "completes once progress reaches the kind's duration, clearing the builder" do
      worker = unit(1, tile: 100, type: :worker)

      improvement = %{
        tile_id: 100,
        kind: :road,
        progress: 1,
        status: :building,
        builder_unit_id: 1
      }

      state = %{base_state(%{1 => worker}) | improvements: %{100 => improvement}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.improvements[100].status == :complete
      assert new_state.improvements[100].progress == 2
      assert new_state.improvements[100].builder_unit_id == nil
    end

    # Story 902, criterion 7628 — `improvement.duration`, when present,
    # overrides `Improvement.duration(kind)` (`WorldServer.
    # persist_start_improvement!/3` is what actually resolves it from
    # research; here we only need to prove `Turn` HONORS it).
    test "a stored :duration overrides the kind's base duration" do
      worker = unit(1, tile: 100, type: :worker)

      improvement = %{
        tile_id: 100,
        kind: :mine,
        progress: 2,
        status: :building,
        duration: 3,
        builder_unit_id: 1
      }

      state = %{base_state(%{1 => worker}) | improvements: %{100 => improvement}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.improvements[100].status == :complete
      assert new_state.improvements[100].progress == 3
      assert new_state.improvements[100].builder_unit_id == nil
    end

    test "no :duration key falls back to the kind's base — the mine still needs 5" do
      worker = unit(1, tile: 100, type: :worker)

      improvement = %{
        tile_id: 100,
        kind: :mine,
        progress: 3,
        status: :building,
        builder_unit_id: 1
      }

      state = %{base_state(%{1 => worker}) | improvements: %{100 => improvement}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.improvements[100].status == :building
      assert new_state.improvements[100].progress == 4
    end

    test "a builder that moves away this tick freezes progress and clears the builder" do
      [target | _] = Regions.adjacent_tiles(world(), 100)
      worker = unit(1, tile: 100, type: :worker, max_movement: 2)
      order = %{kind: :move, path: [target], status: :pending}

      improvement = %{
        tile_id: 100,
        kind: :mine,
        progress: 2,
        status: :building,
        builder_unit_id: 1
      }

      state = %{base_state(%{1 => worker}, %{1 => order}) | improvements: %{100 => improvement}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.improvements[100].progress == 2
      assert new_state.improvements[100].builder_unit_id == nil
    end

    test "no builder present leaves progress untouched" do
      improvement = %{
        tile_id: 100,
        kind: :mine,
        progress: 3,
        status: :building,
        builder_unit_id: nil
      }

      state = %{base_state(%{}) | improvements: %{100 => improvement}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.improvements[100] == improvement
    end

    test "a complete improvement never advances further" do
      improvement = %{
        tile_id: 100,
        kind: :farm,
        progress: 3,
        status: :complete,
        builder_unit_id: nil
      }

      state = %{base_state(%{}) | improvements: %{100 => improvement}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.improvements[100] == improvement
    end
  end

  # Story 929 "Build road to a destination" — `Turn.RoadBuilder`'s own
  # per-tick walk-or-build state machine, exercised via `Turn.tick/1`
  # for everything that stays PURE state (walk, skip-a-complete-road,
  # block-cancels, attacked-cancels, a dead worker). Starting a BRAND
  # NEW road needs a real `Repo.insert` `Turn.tick/1` may never make
  # itself (see `RoadBuilder`'s own "Pure core, impure shell"
  # moduledoc) — that ONE seam, plus the full multi-segment walk-then-
  # build-then-walk sequencing, is covered directly against
  # `RoadBuilder.resolve/1` in `RoadBuilderTest`, and end to end
  # (through the real `WorldServer`, real inserts included) in
  # `WorldServerTest`'s own `build_road_to/4` describe block. Orders are
  # hand-built directly (`kind: :road_to`), the same "bypass the
  # command-layer validation, drive the tick phase itself" posture the
  # "tick/1 movement" describe block already takes for `:move` orders.
  # Tile 5's own neighbor chain (5 -> 9 -> 11, both OPEN terrain, cost 1
  # each) is the SAME fixture path the "tick/1 movement" describe block
  # above already established for this seed/frequency.
  describe "tick/1 road-to (story 929)" do
    defp road_worker(id, tile, opts \\ []) do
      unit(id, Keyword.merge([tile: tile, type: :worker], opts))
    end

    test "walks the immutable route one hex per tick toward the first gap tile" do
      worker = road_worker(1, 5)
      order = %{kind: :road_to, path: [9, 11], status: :pending, hp_at_issue: worker.hp}
      state = base_state(%{1 => worker}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 9
      assert new_state.orders[1] == order
    end

    test "arriving at an unroaded gap tile with no road row yet emits a road_start_needed event, leaving state.roads untouched" do
      worker = road_worker(1, 9)
      order = %{kind: :road_to, path: [9, 11], status: :pending, hp_at_issue: worker.hp}
      state = base_state(%{1 => worker}, %{1 => order})

      {new_state, events} = Turn.tick(state)

      assert {:road_start_needed, 9, 1} in events
      assert Map.get(new_state, :roads, %{}) == %{}
      assert new_state.units[1].tile_id == 9
      assert new_state.orders[1] == order
    end

    test "resumes (claims as builder) an already-building road row in place, purely in memory" do
      worker = road_worker(1, 9)
      order = %{kind: :road_to, path: [9, 11], status: :pending, hp_at_issue: worker.hp}
      building = %{9 => %{tile_id: 9, kind: :road, status: :building, progress: 0, builder_unit_id: 99}}
      state = base_state(%{1 => worker}, %{1 => order}) |> Map.put(:roads, building)

      {new_state, events} = Turn.tick(state)

      assert new_state.roads[9].builder_unit_id == 1
      assert events == [{:turn_advanced, 1}]
    end

    test "an already-complete road tile is walked through, never rebuilt" do
      worker = road_worker(1, 5)
      order = %{kind: :road_to, path: [9, 11], status: :pending, hp_at_issue: worker.hp}
      pre_built = %{9 => %{tile_id: 9, kind: :road, status: :complete, progress: 2}}
      state = base_state(%{1 => worker}, %{1 => order}) |> Map.put(:roads, pre_built)

      {t1, _} = Turn.tick(state)
      assert t1.units[1].tile_id == 9
      assert t1.roads[9] == pre_built[9]

      {t2, _events} = Turn.tick(t1)
      assert t2.units[1].tile_id == 11
      assert t2.roads[9] == pre_built[9]
      refute Map.has_key?(t2.roads, 11)

      # Only NOW (standing on the real gap tile, tile 9 skipped for good)
      # does a build get requested.
      {t3, events} = Turn.tick(t2)
      assert {:road_start_needed, 11, 1} in events
      refute Map.has_key?(t3.roads, 11)
    end

    test "the order completes and is removed once every tile on the route, including the destination, is complete" do
      worker = road_worker(1, 11)
      order = %{kind: :road_to, path: [9, 11], status: :pending, hp_at_issue: worker.hp}

      roads = %{
        9 => %{tile_id: 9, kind: :road, status: :complete, progress: 2},
        11 => %{tile_id: 11, kind: :road, status: :complete, progress: 2}
      }

      state = base_state(%{1 => worker}, %{1 => order}) |> Map.put(:roads, roads)

      {new_state, _events} = Turn.tick(state)

      refute Map.has_key?(new_state.orders, 1)
      assert new_state.units[1].tile_id == 11
    end

    test "a next tile occupied by another unit cancels the whole order" do
      worker = road_worker(1, 5)
      blocker = unit(2, tile: 9, max_movement: 0)
      order = %{kind: :road_to, path: [9, 11], status: :pending, hp_at_issue: worker.hp}
      state = base_state(%{1 => worker, 2 => blocker}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].tile_id == 5
      refute Map.has_key?(new_state.orders, 1)
    end

    test "hp dropping below hp_at_issue (attacked mid-build) cancels the order" do
      worker = road_worker(1, 9, hp: 6)
      order = %{kind: :road_to, path: [9, 11], status: :pending, hp_at_issue: 10}
      state = base_state(%{1 => worker}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      refute Map.has_key?(new_state.orders, 1)
      assert new_state.units[1].tile_id == 9
      assert Map.get(new_state, :roads, %{}) == %{}
    end

    test "a dead worker's order is dropped, not resolved" do
      order = %{kind: :road_to, path: [9, 11], status: :pending, hp_at_issue: 10}
      state = base_state(%{}, %{1 => order})

      {new_state, _events} = Turn.tick(state)

      refute Map.has_key?(new_state.orders, 1)
    end
  end

  # Story 882 playtest update (issue 1caa87e9 — worker build charges).
  describe "tick/1 worker build charges" do
    defp worker_with_charges(id, tile, charges) do
      Map.put(unit(id, tile: tile, type: :worker), :charges, charges)
    end

    test "a completed Farm spends one of the builder's charges" do
      worker = worker_with_charges(1, 100, 3)

      improvement = %{
        tile_id: 100,
        kind: :farm,
        progress: 2,
        status: :building,
        builder_unit_id: 1
      }

      state = %{base_state(%{1 => worker}) | improvements: %{100 => improvement}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.improvements[100].status == :complete
      assert new_state.units[1].charges == 2
    end

    test "a completed Mine spends one of the builder's charges" do
      worker = worker_with_charges(1, 100, 3)

      improvement = %{
        tile_id: 100,
        kind: :mine,
        progress: 4,
        status: :building,
        builder_unit_id: 1
      }

      state = %{base_state(%{1 => worker}) | improvements: %{100 => improvement}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.improvements[100].status == :complete
      assert new_state.units[1].charges == 2
    end

    test "a completed Road never spends a charge" do
      worker = worker_with_charges(1, 100, 2)

      improvement = %{
        tile_id: 100,
        kind: :road,
        progress: 1,
        status: :building,
        builder_unit_id: 1
      }

      state = %{base_state(%{1 => worker}) | improvements: %{100 => improvement}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.improvements[100].status == :complete
      assert new_state.units[1].charges == 2
    end

    test "a worker with no :charges key defaults to 3 and drops to 2 on a completed Farm" do
      worker = unit(1, tile: 100, type: :worker)

      improvement = %{
        tile_id: 100,
        kind: :farm,
        progress: 2,
        status: :building,
        builder_unit_id: 1
      }

      state = %{base_state(%{1 => worker}) | improvements: %{100 => improvement}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].charges == 2
    end

    test "spending a worker's last charge expends it — removed from state.units" do
      worker = worker_with_charges(1, 100, 1)

      improvement = %{
        tile_id: 100,
        kind: :farm,
        progress: 2,
        status: :building,
        builder_unit_id: 1
      }

      state = %{base_state(%{1 => worker}) | improvements: %{100 => improvement}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.improvements[100].status == :complete
      refute Map.has_key?(new_state.units, 1)
    end

    test "an abandoned (not-yet-complete) dig spends no charge" do
      worker = worker_with_charges(1, 100, 3)

      improvement = %{
        tile_id: 100,
        kind: :mine,
        progress: 1,
        status: :building,
        builder_unit_id: 1
      }

      state = %{base_state(%{1 => worker}) | improvements: %{100 => improvement}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.improvements[100].status == :building
      assert new_state.units[1].charges == 3
    end
  end

  describe "tick/1 food accrual and growth" do
    test "food accrues and a city at threshold grows, claiming a new tile" do
      c = city(1, tile: 1, food: 18, territory: [1])
      state = %{base_state(%{}) | cities: %{1 => c}}

      {new_state, _events} = Turn.tick(state)

      grown = new_state.cities[1]
      assert grown.size == 2
      assert length(grown.territory) == 2
    end

    test "growth respects a rival city's prior claim on the same tiles" do
      neighbors = Regions.adjacent_tiles(world(), 1)
      rival = city(2, tile: 600, territory: neighbors, player_id: 2)
      c = city(1, tile: 1, food: 25, territory: [1])
      state = %{base_state(%{}) | cities: %{1 => c, 2 => rival}}

      {new_state, _events} = Turn.tick(state)

      grown = new_state.cities[1]
      assert grown.size == 2
      assert grown.territory == [1]
    end
  end

  describe "tick/1 healing" do
    test "unmoved-at-home heals 10, garrisoned-on-the-city-tile heals 15, abroad heals 5" do
      neighbors = Regions.adjacent_tiles(world(), 1)
      [home_tile | _] = neighbors

      abroad_tile =
        neighbors
        |> Enum.flat_map(&Regions.adjacent_tiles(world(), &1))
        |> Enum.uniq()
        |> Enum.reject(&(&1 == 1 or &1 in neighbors))
        |> List.first()

      c = city(1, tile: 1, territory: [1 | neighbors])

      home = unit(1, tile: home_tile, hp: 50, max_hp: 100, type: :warrior, max_movement: 1)
      garrison = unit(2, tile: 1, hp: 50, max_hp: 100, type: :warrior, max_movement: 1)
      abroad = unit(3, tile: abroad_tile, hp: 50, max_hp: 100, type: :warrior, max_movement: 1)

      state = %{base_state(%{1 => home, 2 => garrison, 3 => abroad}) | cities: %{1 => c}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].hp == 60
      assert new_state.units[2].hp == 65
      # Story: abroad now heals 5 (was 0) — some slow healing anywhere.
      assert new_state.units[3].hp == 55
    end

    test "a unit that moved this tick does not heal, even in home territory" do
      neighbors = Regions.adjacent_tiles(world(), 1)
      [target | _] = neighbors
      c = city(1, tile: 1, territory: [1 | neighbors])

      mover = unit(1, tile: 1, hp: 50, max_hp: 100, max_movement: 1)
      order = %{kind: :move, path: [target], status: :pending}
      state = %{base_state(%{1 => mover}, %{1 => order}) | cities: %{1 => c}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].hp == 50
    end

    test "a unit already at full HP is left alone" do
      c = city(1, tile: 1)
      full_hp = unit(1, tile: 1, hp: 100, max_hp: 100)
      state = %{base_state(%{1 => full_hp}) | cities: %{1 => c}}

      {new_state, _events} = Turn.tick(state)

      assert new_state.units[1].hp == 100
    end
  end

  describe "tick/1 science accrual (story 902)" do
    defp research_state(city, player_research) do
      %{base_state(%{}) | cities: %{1 => city}}
      |> Map.put(:players, %{1 => %{id: 1, user_id: 1, region_id: 0, gold: 50}})
      |> Map.put(:player_research, %{1 => player_research})
    end

    test "banks 2 science per population point toward current_research" do
      c = city(1, tile: 1, size: 3)
      state = research_state(c, %{Research.new() | current_research: :pottery})

      {new_state, _events} = Turn.tick(state)

      # size 3 * 2 science/pop = 6 banked toward pottery.
      assert Research.banked(new_state.player_research[1], :pottery) == 6
    end

    test "a player with no current_research banks nothing" do
      c = city(1, tile: 1, size: 4)
      state = research_state(c, Research.new())

      {new_state, events} = Turn.tick(state)

      assert new_state.player_research[1] == Research.new()
      refute Enum.any?(events, &match?({:tech_completed, _, _}, &1))
    end

    test "auto-completes a tech the instant its cost is banked, and clears current_research" do
      c = city(1, tile: 1, size: 4)
      # Pottery costs 80 (QA issue d95ea179 rebalance); 72 banked + 8
      # income (size 4 * 2/pop) lands exactly on cost.
      pr = %{Research.new() | current_research: :pottery} |> Research.accrue(72)
      state = research_state(c, pr)

      {new_state, events} = Turn.tick(state)

      completed = new_state.player_research[1]
      assert :pottery in completed.completed_techs
      assert completed.current_research == nil
      assert {:tech_completed, 1, :pottery} in events
    end

    test "a tech below cost keeps banking without completing" do
      c = city(1, tile: 1, size: 1)
      pr = %{Research.new() | current_research: :bronze_working}
      state = research_state(c, pr)

      {new_state, events} = Turn.tick(state)

      not_yet = new_state.player_research[1]
      assert Research.banked(not_yet, :bronze_working) == 2
      assert not_yet.current_research == :bronze_working
      refute Enum.any?(events, &match?({:tech_completed, _, _}, &1))
    end

    test "each player accrues independently against their own cities' population" do
      city_a = city(1, tile: 1, player_id: 1, size: 2)
      city_b = city(2, tile: 10, player_id: 2, size: 4)
      state = %{base_state(%{}) | cities: %{1 => city_a, 2 => city_b}}

      state =
        state
        |> Map.put(:players, %{
          1 => %{id: 1, user_id: 1, region_id: 0, gold: 50},
          2 => %{id: 2, user_id: 2, region_id: 1, gold: 50}
        })
        |> Map.put(:player_research, %{
          1 => %{Research.new() | current_research: :mining},
          2 => %{Research.new() | current_research: :mining}
        })

      {new_state, _events} = Turn.tick(state)

      assert Research.banked(new_state.player_research[1], :mining) == 4
      assert Research.banked(new_state.player_research[2], :mining) == 8
    end

    test "a player missing from player_research entirely is treated as a fresh, unstarted player" do
      c = city(1, tile: 1, size: 2)
      state = %{base_state(%{}) | cities: %{1 => c}}
      state = Map.put(state, :players, %{1 => %{id: 1, user_id: 1, region_id: 0, gold: 50}})

      {new_state, _events} = Turn.tick(state)

      assert new_state.player_research[1] == Research.new()
    end
  end
end
