defmodule BrokenOaths.Simulation.Turn.Movement do
  @moduledoc """
  Pure simultaneous-move resolution — the turn-pipeline-specific phase
  `BrokenOaths.Simulation.Turn.tick/1` runs first, every tick: reset every
  unit's movement to its max, then resolve every `:pending` move order
  in lockstep rounds (one step per round per still-active mover,
  movers processed in ascending unit id each round for determinism),
  then (story 920) ramp every unit's still-held Fortify stance by one
  turn (`advance_fortify/1` below). A
  step is blocked when its destination is occupied at that instant —
  either by a unit that never moves this round or by a unit that
  claimed the tile earlier in the same round. A blocked mover halts for
  the rest of the tick: its order becomes `:interrupted` and its
  remaining path (including the blocked step) is preserved untouched.
  `:interrupted` orders AUTO-RESUME on the next tick — `resolve_orders/1`
  re-picks any order still `:pending` OR `:interrupted` with a non-empty
  path, so a mover blocked this tick keeps retrying its preserved path
  each turn until the tile clears (or the player cancels it), the Civ 6
  keep-pathing behavior. A path fully consumed within the tick is an
  arrival: the order is removed entirely.

  Story 925: one step per round no longer means one movement point per
  round — each step spends whatever `BrokenOaths.Units.Unit.entry_cost/3`
  prices the target tile at (1 for open terrain or a completed Road, 2
  for DIFFICULT terrain — hills/woods/rainforest/marsh — with no Road),
  clamped at 0 rather than going negative. `active_movers/1`'s own gate
  (`movement_left > 0`, not `>= cost`) preserves Civ 6's "a unit with
  any movement may always move at least one tile" rule, so a
  movement-1 unit is never stuck outside a forest it can't afford.

  This logic is genuinely cross-cutting (it reads `BrokenOaths.Game.
  CityDefense`'s own garrison rule and `BrokenOaths.Combat.Siege`'s own
  broken-city walk-in exception to decide what counts as "blocked") and
  has no single owning domain model — it belongs to the turn pipeline
  itself, not to `BrokenOaths.Units.Unit`. `move_now/2` is the one seam
  `BrokenOaths.Units.Unit.queue_move/4` and `BrokenOaths.Game.
  Stewardship` call directly (via `BrokenOaths.Simulation.Turn.move_now/2`,
  which delegates here) to resolve a freshly-queued order's first steps
  immediately rather than waiting for the next tick boundary — same
  collision semantics as the tick's own resolution.

  `state` throughout is the canonical tick-state described in
  `BrokenOaths.Simulation.Turn`.
  """

  alias BrokenOaths.Combat.CityDefense
  alias BrokenOaths.Units.Unit
  alias BrokenOaths.Vision.Visibility

  @doc "Reset every unit's `movement` to its `max_movement` at the start of a tick."
  @spec reset_movement(map()) :: map()
  def reset_movement(state) do
    units = Map.new(state.units, fn {id, unit} -> {id, %{unit | movement: unit.max_movement}} end)
    %{state | units: units}
  end

  @doc "Resolve every `:pending` move order simultaneously, in lockstep rounds."
  @spec resolve_orders(map()) :: map()
  def resolve_orders(state) do
    movers =
      for {unit_id, %{kind: :move, status: status, path: path}} <- state.orders,
          status in [:pending, :interrupted],
          path != [],
          into: %{} do
        unit = Map.fetch!(state.units, unit_id)

        {unit_id,
         %{tile_id: unit.tile_id, path: path, status: :pending, movement_left: unit.movement}}
      end

    positions = Map.new(state.units, fn {id, unit} -> {id, unit.tile_id} end)

    {movers, positions} =
      run_rounds(
        movers,
        positions,
        state.units,
        garrisonable_tiles(state.cities),
        broken_city_tiles(state.cities),
        state.world,
        Map.get(state, :roads, %{})
      )

    %{
      state
      | units: apply_positions(state.units, movers, positions),
        orders: apply_orders(state.orders, movers)
    }
  end

  @doc """
  Story 920 rework — ramp every held Fortify stance by one turn at the
  boundary (Civ 6's own +3-after-1-turn/+6-after-2-turns shape, ratio-
  mapped by `Combat.Resolver.effective_strength/3`): any unit whose own
  `fortified_turns` is still >= 1 gets bumped by one, capped at 2. MUST
  run AFTER `resolve_orders/1`, never before — that phase's own
  `apply_positions/3` above already zeroed `fortified_turns` for anyone
  who actually displaced this tick, and every clear-on-attack site
  (`Combat.Resolver.resolve_attack/4`, `Combat.Camps.
  resolve_camp_attack/3`, `Combat.Siege`'s own `resolve_city_attack/4`)
  already zeroed anyone who fought, all BEFORE this tick boundary ever
  runs (attacks resolve the instant they're requested, not queued) — so
  by the time this runs, a nonzero `fortified_turns` is exactly a unit
  that stayed put and didn't fight THIS tick. 1 (set the instant
  `Units.Unit.fortify/3` was called, this turn or an earlier one)
  becomes 2 the first time it survives a whole boundary untouched;
  already-2 stays capped there.
  """
  @spec advance_fortify(map()) :: map()
  def advance_fortify(state) do
    units = Map.new(state.units, fn {id, unit} -> {id, bump_fortify(unit)} end)
    %{state | units: units}
  end

  defp bump_fortify(unit) do
    case Map.get(unit, :fortified_turns, 0) do
      0 -> unit
      n -> Map.put(unit, :fortified_turns, min(n + 1, 2))
    end
  end

  @doc """
  Immediate movement: spend `unit_id`'s remaining points on its pending
  order right now. Orders execute as they're issued — the turn boundary
  only recharges movement and continues whatever path remains. Same
  collision semantics as the tick: a step into an occupied tile
  interrupts the order in place.
  """
  @spec move_now(map(), term()) :: map()
  def move_now(state, unit_id) do
    case Map.get(state.orders, unit_id) do
      %{kind: :move, status: :pending, path: path} when path != [] ->
        unit = Map.fetch!(state.units, unit_id)

        movers = %{
          unit_id => %{
            tile_id: unit.tile_id,
            path: path,
            status: :pending,
            movement_left: unit.movement
          }
        }

        positions = Map.new(state.units, fn {id, u} -> {id, u.tile_id} end)

        {movers, positions} =
          run_rounds(
            movers,
            positions,
            state.units,
            garrisonable_tiles(state.cities),
            broken_city_tiles(state.cities),
            state.world,
            Map.get(state, :roads, %{})
          )

        %{
          state
          | units: apply_positions(state.units, movers, positions),
            orders: apply_orders(state.orders, movers)
        }
        |> Visibility.refresh_explored()

      _ ->
        state
    end
  end

  # `units` is the pre-round snapshot of every unit's `type`/`player_id`
  # (stable for the round — only `positions` changes as movers claim
  # tiles); `garrisonable` is `player_id => MapSet.t(their own cities'
  # tile_ids)`, precomputed once via `garrisonable_tiles/1`; `broken_cities`
  # is `tile_id => owner_player_id`, precomputed once via
  # `broken_city_tiles/1`. `world`/`roads` (story 925) are the same
  # read-only pair `attempt_step/7`'s own `Unit.entry_cost/3` call needs
  # to price each step. All five are read-only context for
  # `attempt_step/7`'s story-895 garrison exception, story-906 broken-
  # city exception, and story-925 terrain/road cost below.
  defp run_rounds(movers, positions, units, garrisonable, broken_cities, world, roads) do
    case active_movers(movers) do
      [] ->
        {movers, positions}

      ids ->
        {movers, positions} =
          Enum.reduce(
            ids,
            {movers, positions},
            &attempt_step(&1, &2, units, garrisonable, broken_cities, world, roads)
          )

        run_rounds(movers, positions, units, garrisonable, broken_cities, world, roads)
    end
  end

  # Story 925's Civ 6 "min 1" rule falls out of this gate for free: it's
  # `movement_left > 0`, never `movement_left >= entry_cost`, so a
  # Warrior (movement 1) with any movement left still gets to attempt
  # its next step even when the target tile costs 2 — `attempt_step/7`
  # below just clamps the result to 0 rather than refusing the step.
  # Without this, a movement-1 unit could never enter a DIFFICULT tile
  # (hills/woods/rainforest/marsh) at all.
  defp active_movers(movers) do
    movers
    |> Enum.filter(fn {_id, m} ->
      m.status == :pending and m.path != [] and m.movement_left > 0
    end)
    |> Enum.map(fn {id, _m} -> id end)
    |> Enum.sort()
  end

  # `player_id => MapSet.t(tile_id)` of that player's own cities' own
  # tiles — the only tiles `blocked?/6`'s garrison exception ever
  # applies to.
  defp garrisonable_tiles(cities) do
    cities
    |> Map.values()
    |> Enum.group_by(& &1.player_id)
    |> Map.new(fn {player_id, owned} ->
      {player_id, MapSet.new(Enum.map(owned, & &1.tile_id))}
    end)
  end

  # `tile_id => owner_player_id` of every BROKEN (0 HP), still-free city
  # — story 906's own movement exception (`BrokenOaths.Combat.Siege.
  # enterable_despite_garrison?/2`): once a city's walls are down, any
  # OTHER player's unit may step onto its own tile even past a fallen
  # (still-alive, not-yet-resolved) garrison. A healthy or already-
  # captured city (`occupied_by_player_id` set) is never in this map, so
  # this never loosens collision for either case — see `Siege.broken?/1`.
  defp broken_city_tiles(cities) do
    cities
    |> Map.values()
    |> Enum.filter(&(Map.get(&1, :hp) == 0 and is_nil(Map.get(&1, :occupied_by_player_id))))
    |> Map.new(&{&1.tile_id, &1.player_id})
  end

  defp attempt_step(
         unit_id,
         {movers, positions},
         units,
         garrisonable,
         broken_cities,
         world,
         roads
       ) do
    mover = Map.fetch!(movers, unit_id)
    [target | rest] = mover.path
    mover_unit = Map.fetch!(units, unit_id)

    # A step onto the mover's OWN current-in-round tile is degenerate,
    # not a same-tile arrival to silently drop: `blocked?/6` always
    # excludes the mover itself from `positions`-derived occupants (a
    # unit never blocks its own vacated tile), so without this guard
    # such a step would "succeed" into an empty path, `apply_orders/2`
    # would read that as arrival, and the order would vanish instead of
    # halting the mover with `:interrupted` as a blocked step should.
    if target == mover.tile_id or
         blocked?(target, positions, units, mover_unit, garrisonable, broken_cities) do
      {Map.put(movers, unit_id, %{mover | status: :interrupted}), positions}
    else
      # Story 925: spend the tile's own cost (`Unit.entry_cost/3` —
      # terrain, or 1 flat if a completed Road covers it), clamped at 0
      # rather than going negative — the min-1 rule (`active_movers/1`
      # above) already let a unit with less than the full cost left
      # attempt this step; it simply can't go any further this round.
      cost = Unit.entry_cost(world, roads, target)

      moved = %{
        mover
        | tile_id: target,
          path: rest,
          movement_left: max(mover.movement_left - cost, 0)
      }

      {Map.put(movers, unit_id, moved), Map.put(positions, unit_id, target)}
    end
  end

  # A tile with no occupants at all is never blocked. Otherwise blocked
  # UNLESS `target` is `mover_unit`'s own city's own tile with garrison
  # room for it (story 895 — `CityDefense.garrison_room?/2`), OR `target`
  # is another player's BROKEN city (story 906 — `Siege.
  # enterable_despite_garrison?/2`, the fallen-garrison walk-in), OR
  # `target` holds exactly one of the mover's own units of the OTHER
  # combat class (v0.2.1 playtest issue 5df5de88 — a civilian may stack
  # with a combat escort, either direction, out in the open field —
  # `entering_field_stack_with_room?/2`); every other occupied tile,
  # city or not, mine or another player's, keeps the original
  # all-or-nothing rule.
  defp blocked?(target, positions, units, mover_unit, garrisonable, broken_cities) do
    occupants =
      for {id, tile} <- positions, tile == target, id != mover_unit.id, do: Map.fetch!(units, id)

    case occupants do
      [] ->
        false

      _ ->
        not (entering_own_garrison_with_room?(target, occupants, mover_unit, garrisonable) or
               entering_broken_enemy_city?(target, mover_unit, broken_cities) or
               entering_field_stack_with_room?(occupants, mover_unit))
    end
  end

  # Mirrors `WorldServer.field_stack_room?/2`'s queue-time allowance for
  # the dynamic, tick-time check: exactly one existing occupant, owned
  # by the SAME player as `mover_unit`, of the OTHER combat class
  # (`CityDefense.military?/1` — the same combat/civilian split story
  # 895's own garrison rule uses). Two or more occupants, a foreign
  # occupant, or a same-class occupant all stay blocked.
  defp entering_field_stack_with_room?([only], mover_unit) do
    only.player_id == mover_unit.player_id and
      CityDefense.military?(only) != CityDefense.military?(mover_unit)
  end

  defp entering_field_stack_with_room?(_occupants, _mover_unit), do: false

  defp entering_own_garrison_with_room?(target, occupants, mover_unit, garrisonable) do
    MapSet.member?(Map.get(garrisonable, mover_unit.player_id, MapSet.new()), target) and
      CityDefense.garrison_room?(mover_unit, occupants)
  end

  defp entering_broken_enemy_city?(target, mover_unit, broken_cities) do
    case Map.get(broken_cities, target) do
      nil -> false
      owner_player_id -> owner_player_id != mover_unit.player_id
    end
  end

  # Story 920: a unit whose queued step was blocked before it ever left
  # its own tile (`attempt_step/5`'s degenerate/blocked branches — the
  # SAME tile before and after) hasn't actually "moved" in the sense
  # Fortify's own "clears when the unit acts" rule cares about, so its
  # own stance (whatever level it's at) survives; a unit that DID
  # displace loses it — back to 0, the same way attacking does
  # (`Combat.Resolver.resolve_attack/4`). `Map.get/3` (not straight
  # `unit.fortified_turns`) so this never raises on a hand-built test
  # unit map that predates the field. This is also what makes
  # `advance_fortify/1` below correct: it only ever runs AFTER this, so
  # any unit that displaced this tick already reads 0 by the time it
  # does.
  defp apply_positions(units, movers, positions) do
    Map.new(units, fn {id, unit} ->
      case Map.fetch(movers, id) do
        {:ok, mover} ->
          new_tile_id = Map.fetch!(positions, id)

          fortified_turns =
            if new_tile_id == unit.tile_id, do: Map.get(unit, :fortified_turns, 0), else: 0

          {id,
           unit
           |> Map.put(:tile_id, new_tile_id)
           |> Map.put(:movement, mover.movement_left)
           |> Map.put(:fortified_turns, fortified_turns)}

        :error ->
          {id, unit}
      end
    end)
  end

  # Orders whose path emptied this tick (arrival) are dropped entirely.
  defp apply_orders(orders, movers) do
    orders
    |> Enum.map(fn {id, order} ->
      case Map.fetch(movers, id) do
        {:ok, mover} -> {id, %{order | path: mover.path, status: mover.status}}
        :error -> {id, order}
      end
    end)
    |> Enum.reject(fn {_id, order} -> order.path == [] end)
    |> Map.new()
  end
end
