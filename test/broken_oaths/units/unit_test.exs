defmodule BrokenOaths.Units.UnitTest do
  use BrokenOathsTest.DataCase, async: true

  alias BrokenOaths.Players.Player
  alias BrokenOaths.Units.Unit
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.Worlds.World
  alias BrokenOaths.WorldsFixtures

  # Same fixture seed/frequency `production_test.exs`/`resolver_test.exs`
  # already use — real terrain, not a stub, so `bfs_path/4`'s own tests
  # below exercise the actual `Regions` classification.
  defp fixture_world, do: %World{seed: 424_242, frequency: 8}

  defp tick_state(units \\ %{}), do: %{world: fixture_world(), units: units}

  defp player_fixture(attrs \\ %{}) do
    world = attrs[:world] || WorldsFixtures.world_fixture()
    user = UsersFixtures.user_fixture()

    {:ok, player} =
      %Player{}
      |> Player.changeset(%{
        world_id: world.id,
        user_id: user.id,
        region_id: attrs[:region_id] || 1,
        joined_turn: 0
      })
      |> Repo.insert()

    player
  end

  defp valid_attrs do
    player = player_fixture()

    %{
      world_id: player.world_id,
      player_id: player.id,
      type: :lord,
      tile_id: 42,
      hp: 10,
      max_hp: 10,
      movement: 2,
      max_movement: 2
    }
  end

  test "changeset with valid attrs is valid" do
    changeset = Unit.changeset(%Unit{}, valid_attrs())
    assert changeset.valid?
  end

  test "changeset requires all fields except player_id and camp_id" do
    changeset = Unit.changeset(%Unit{}, %{})
    refute changeset.valid?

    assert %{
             world_id: ["can't be blank"],
             type: ["can't be blank"],
             tile_id: ["can't be blank"],
             hp: ["can't be blank"],
             max_hp: ["can't be blank"],
             movement: ["can't be blank"],
             max_movement: ["can't be blank"]
           } = errors_on(changeset)

    refute Map.has_key?(errors_on(changeset), :player_id)
    refute Map.has_key?(errors_on(changeset), :camp_id)
  end

  test "player_id is nullable — a barbarian warrior has no owner" do
    attrs = %{valid_attrs() | player_id: nil, type: :barbarian_warrior}
    changeset = Unit.changeset(%Unit{}, attrs)
    assert changeset.valid?
  end

  test "type must be lord or settler" do
    changeset = Unit.changeset(%Unit{}, %{valid_attrs() | type: :wizard})
    refute changeset.valid?
    assert %{type: ["is invalid"]} = errors_on(changeset)
  end

  test "hp must be greater than 0" do
    changeset = Unit.changeset(%Unit{}, %{valid_attrs() | hp: 0})
    refute changeset.valid?
    assert %{hp: ["must be greater than 0"]} = errors_on(changeset)
  end

  test "hp cannot exceed max_hp" do
    changeset = Unit.changeset(%Unit{}, %{valid_attrs() | hp: 11, max_hp: 10})
    refute changeset.valid?
    assert %{hp: ["must be less than or equal to max_hp"]} = errors_on(changeset)
  end

  test "movement cannot exceed max_movement" do
    changeset = Unit.changeset(%Unit{}, %{valid_attrs() | movement: 3, max_movement: 2})
    refute changeset.valid?
    assert %{movement: ["must be less than or equal to max_movement"]} = errors_on(changeset)
  end

  test "movement can be zero" do
    changeset = Unit.changeset(%Unit{}, %{valid_attrs() | movement: 0})
    assert changeset.valid?
  end

  # Story 882 playtest update (issue 1caa87e9 — worker build charges):
  # every unit type carries this field (only :worker ever spends it),
  # defaulting to 3 (a fresh Civ 6-style Builder's charge count) when
  # the caller doesn't set it explicitly.
  test "charges defaults to 3 when omitted" do
    changeset = Unit.changeset(%Unit{}, %{valid_attrs() | type: :worker})
    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :charges) == 3
  end

  test "charges can be set explicitly" do
    changeset = Unit.changeset(%Unit{}, Map.put(valid_attrs(), :charges, 1))
    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :charges) == 1
  end

  test "charges cannot be negative" do
    changeset = Unit.changeset(%Unit{}, Map.put(valid_attrs(), :charges, -1))
    refute changeset.valid?
    assert %{charges: ["must be greater than or equal to 0"]} = errors_on(changeset)
  end

  # Story 895: the blanket `(world_id, tile_id)` DB uniqueness this test
  # used to assert was dropped outright by migration
  # `20260716190000_drop_unit_tile_uniqueness_for_city_garrisons` — a
  # city's own tile is now a deliberate stacking exception (up to 3
  # friendly military units, plus any number of civilians; see
  # `BrokenOaths.Combat.CityDefense.garrison_room?/2`), and Postgres has
  # no built-in "unique except on these specific tiles" constraint, so
  # "one unit per hex" moved entirely to the application layer
  # (`WorldServer.occupied_by_own?/4` at queue time, `Turn`'s
  # `attempt_step/4` collision check at tick time — see `garrison_room?/2`'s
  # own test coverage in `city_defense_test.exs` for the exception
  # itself). The changeset/schema layer no longer refuses a same-tile
  # insert at all, which is exactly what this asserts now.
  test "the changeset layer no longer refuses two units sharing a tile" do
    attrs = valid_attrs()
    assert {:ok, _unit} = Unit.changeset(%Unit{}, attrs) |> Repo.insert()

    world = Repo.get!(World, attrs.world_id)
    other_player = player_fixture(%{world: world, region_id: 2})
    dup_attrs = %{attrs | world_id: world.id, player_id: other_player.id}

    assert {:ok, _other_unit} = Unit.changeset(%Unit{}, dup_attrs) |> Repo.insert()
  end

  # -------------------------------------------------------------------
  # passable_tile?/2 + bfs_path/4 (story 921 — the Galley's own
  # domain-aware terrain check). Same fixture seed/frequency
  # `production_test.exs`/`resolver_test.exs` already use: tile 26
  # (land) has adjacent `:coastal_water` tiles 19 and 32; 32 and 33 are
  # themselves adjacent `:coastal_water` tiles (verified against
  # `Regions` directly, never hardcoded blind).
  # -------------------------------------------------------------------

  describe "passable_tile?/2" do
    test "every unit type before the Galley is :land-only, unchanged" do
      assert Unit.passable_tile?(:warrior, :land)
      refute Unit.passable_tile?(:warrior, :coastal_water)
      refute Unit.passable_tile?(:warrior, :mountain)
      refute Unit.passable_tile?(:warrior, :deep_ocean)

      assert Unit.passable_tile?(:lord, :land)
      assert Unit.passable_tile?(:settler, :land)
      assert Unit.passable_tile?(:barbarian_warrior, :land)
    end

    test "the Galley is :coastal_water-only — no land, no deep ocean (V1's locked scope)" do
      assert Unit.passable_tile?(:galley, :coastal_water)
      refute Unit.passable_tile?(:galley, :land)
      refute Unit.passable_tile?(:galley, :mountain)
      refute Unit.passable_tile?(:galley, :deep_ocean)
    end

    # Story 931 — the Scout is an ordinary land unit for passability
    # purposes; its own trait is entry COST (`entry_cost/5` below), not
    # which tiles it may enter at all.
    test "the Scout is :land-only, same as every other land unit" do
      assert Unit.passable_tile?(:scout, :land)
      refute Unit.passable_tile?(:scout, :coastal_water)
      refute Unit.passable_tile?(:scout, :mountain)
      refute Unit.passable_tile?(:scout, :deep_ocean)
    end
  end

  describe "bfs_path/4" do
    test "a land unit paths across land tiles exactly as before" do
      assert Unit.bfs_path(tick_state(), 26, 27, :warrior) == [27]
    end

    test "a Galley paths across adjacent coastal_water tiles" do
      assert Unit.bfs_path(tick_state(), 32, 33, :galley) == [33]
    end

    test "a Galley cannot reach a land destination — no path through water-only tiles" do
      assert Unit.bfs_path(tick_state(), 32, 26, :galley) == nil
    end

    test "a land unit cannot reach a coastal_water destination — no path through land-only tiles" do
      assert Unit.bfs_path(tick_state(), 26, 19, :warrior) == nil
    end

    test "the destination may be occupied — approaching it is legal (Turn's own dynamic collision check is what halts the mover, not queue-time pathing)" do
      other_galley = %{id: 99, tile_id: 33, type: :galley}
      assert Unit.bfs_path(tick_state(%{99 => other_galley}), 32, 33, :galley) == [33]
    end
  end

  # -------------------------------------------------------------------
  # entry_cost/3 + weighted bfs_path/4 (story 925 — Civ-faithful
  # road/terrain movement). Same fixture world as above (seed 424_242,
  # frequency 8). Tile relationships below are verified against
  # `Regions`/`Terrain` directly, never hardcoded blind:
  #   * tile 10 is DIFFICULT (snow hills, `Terrain.movement_cost/1` 2).
  #   * tile 1's own neighbors include tile 9 (OPEN — snow flat, cost 1)
  #     and tile 10; tile 9's own neighbors include tile 17 (OPEN, cost
  #     1); tile 10's own neighbors ALSO include tile 17 — but tile 17
  #     is NOT itself a neighbor of tile 1, so 1 -> 17 has exactly two
  #     2-hop routes: via 9 (total cost 1 + 1 = 2) or via 10 (total cost
  #     2 + 1 = 3).
  #   * tile 1's own neighbors also include tile 2 (also DIFFICULT,
  #     cost 2); both 2 and 10's own neighbors include tile 11 (OPEN,
  #     cost 1), and 11 is likewise not itself a neighbor of tile 1, so
  #     1 -> 11 has two more 2-hop routes, via 2 or via 10, tied at cost
  #     2 + 1 = 3 with neither Road.
  # -------------------------------------------------------------------

  describe "entry_cost/3" do
    test "open terrain costs 1" do
      world = fixture_world()
      assert Unit.entry_cost(world, %{}, 9) == 1
    end

    test "DIFFICULT terrain (hills) costs 2 with no road" do
      world = fixture_world()
      assert Unit.entry_cost(world, %{}, 10) == 2
    end

    test "a completed Road overrides DIFFICULT terrain back down to 1" do
      world = fixture_world()
      roads = %{10 => %{tile_id: 10, kind: :road, progress: 4, status: :complete}}
      assert Unit.entry_cost(world, roads, 10) == 1
    end

    test "a road still :building (not yet complete) grants nothing" do
      world = fixture_world()
      roads = %{10 => %{tile_id: 10, kind: :road, progress: 1, status: :building}}
      assert Unit.entry_cost(world, roads, 10) == 2
    end
  end

  # Story 927 "Workers chop woods and rainforest" — `entry_cost/4`'s own
  # worker-cleared overlay (`Regions.terrain/3`): a chopped Woods/
  # Rainforest/Marsh tile prices like open terrain the instant it's
  # cleared, but clearing a FEATURE never touches DIFFICULT *relief*
  # (hills) — the two are independent difficulty sources.
  describe "entry_cost/4 (story 927 — the worker-cleared overlay)" do
    test "with no cleared_features, matches entry_cost/3 exactly" do
      world = fixture_world()
      assert Unit.entry_cost(world, %{}, 9, MapSet.new()) == Unit.entry_cost(world, %{}, 9)
      assert Unit.entry_cost(world, %{}, 10, MapSet.new()) == Unit.entry_cost(world, %{}, 10)
    end

    test "clearing a feature tile drops its cost to 1" do
      world = fixture_world()

      feature_tile =
        Enum.find(0..641, fn t ->
          BrokenOaths.Worlds.Regions.tile_class(world, t) == :land and
            BrokenOaths.Worlds.Regions.terrain(world, t).relief == :flat and
            BrokenOaths.Worlds.Regions.terrain(world, t).feature in [:woods, :rainforest, :marsh]
        end)

      assert Unit.entry_cost(world, %{}, feature_tile) == 2
      assert Unit.entry_cost(world, %{}, feature_tile, MapSet.new([feature_tile])) == 1
    end

    test "clearing a hills tile's own feature never drops relief-driven difficulty" do
      world = fixture_world()
      # Tile 10 (see this describe's own header comment) is DIFFICULT via
      # `relief: :hills`, not a feature — clearing it (even though it
      # carries no feature to clear at all) leaves it at cost 2.
      assert Unit.entry_cost(world, %{}, 10, MapSet.new([10])) == 2
    end
  end

  # Story 931 — the Scout's own terrain-ignore: `entry_cost/5` prices a
  # `:scout` at a flat 1 on ANY passable land tile, difficult or not
  # (Civ 6's recon trait). Same fixture tiles the `entry_cost/3`/`/4`
  # describes above already document: tile 9 is OPEN (cost 1), tile 10
  # is DIFFICULT (snow hills, cost 2 for every other type).
  describe "entry_cost/5 (story 931 — the Scout's terrain-ignore)" do
    test "a Scout pays 1 to enter a DIFFICULT tile, where a Warrior still pays 2" do
      world = fixture_world()
      assert Unit.entry_cost(world, %{}, 10, MapSet.new(), :scout) == 1
      assert Unit.entry_cost(world, %{}, 10, MapSet.new(), :warrior) == 2
    end

    test "a Scout still pays 1 on open terrain, same as everyone else" do
      world = fixture_world()
      assert Unit.entry_cost(world, %{}, 9, MapSet.new(), :scout) == 1
      assert Unit.entry_cost(world, %{}, 9, MapSet.new(), :warrior) == 1
    end

    test "a completed Road under a Scout is still 1 — no double discount" do
      world = fixture_world()
      roads = %{10 => %{tile_id: 10, kind: :road, progress: 4, status: :complete}}
      assert Unit.entry_cost(world, roads, 10, MapSet.new(), :scout) == 1
    end

    test "no unit_type (nil) preserves the pre-931 default for every existing caller" do
      world = fixture_world()
      assert Unit.entry_cost(world, %{}, 10, MapSet.new(), nil) == Unit.entry_cost(world, %{}, 10)
      assert Unit.entry_cost(world, %{}, 9, MapSet.new(), nil) == Unit.entry_cost(world, %{}, 9)
    end
  end

  describe "bfs_path/4 — Scout terrain-ignore (story 931)" do
    test "a Scout's own route through a DIFFICULT tile costs the same 1-per-hop as open ground — it never needs to detour around one" do
      world = fixture_world()
      # Tile 1 -> 10 is a single DIFFICULT hop; a Warrior pays 2 for it
      # (see the "entry_cost/3" describe's own header comment), a Scout
      # pays 1 — the same flat per-hop cost open terrain already has.
      assert Unit.bfs_path(tick_state(), 1, 10, :scout) == [10]
      assert Unit.entry_cost(world, %{}, 10, MapSet.new(), :scout) == 1
    end

    test "a Scout still routes to the correct destination through mixed terrain" do
      assert Unit.bfs_path(tick_state(), 1, 17, :scout) == [9, 17]
    end
  end

  describe "bfs_path/4 — weighted (story 925)" do
    test "routes along cheap terrain over a parallel DIFFICULT-terrain route, and the path's total cost is the cheaper one" do
      assert Unit.bfs_path(tick_state(), 1, 17, :warrior) == [9, 17]

      world = fixture_world()

      total_cost =
        [9, 17]
        |> Enum.reduce(0, fn tile, acc -> acc + Unit.entry_cost(world, %{}, tile) end)

      assert total_cost == 2
    end

    test "a completed Road on the DIFFICULT leg makes it the cheaper route, flipping the choice" do
      # Unroaded, 1 -> 11 ties at cost 3 either way (via tile 2 or via
      # tile 10, both DIFFICULT). A completed Road on 10 drops that leg
      # to 1, making 1 -> 10 -> 11 (cost 1 + 1 = 2) strictly cheaper
      # than 1 -> 2 -> 11 (cost 2 + 1 = 3) — the reported "units don't
      # route along roads" bug, fixed at the pathfinding level.
      state =
        Map.put(tick_state(), :roads, %{
          10 => %{tile_id: 10, kind: :road, progress: 4, status: :complete}
        })

      assert Unit.bfs_path(state, 1, 11, :warrior) == [10, 11]
    end

    test "ties (no road, both routes DIFFICULT) resolve deterministically by lowest tile id" do
      assert Unit.bfs_path(tick_state(), 1, 11, :warrior) == [2, 11]
    end
  end

  # Story 929 "Build road to a destination" — `allowed_tiles`, the
  # territory restriction `Unit.build_road_to/4` passes in so a road
  # route never strays outside the issuing player's own borders. Same
  # fixture tiles the "bfs_path/4 — weighted" describe block above
  # already documents: 1 -> 17's cheapest route is [9, 17] (cost 2,
  # via OPEN tile 9); tile 10 (DIFFICULT) is a pricier alternate also
  # reaching 17 directly.
  describe "bfs_path/5 — territory restriction (story 929)" do
    test "the default (no 5th arg, or an explicit nil) is unrestricted — identical to bfs_path/4" do
      assert Unit.bfs_path(tick_state(), 1, 17, :warrior) ==
               Unit.bfs_path(tick_state(), 1, 17, :warrior, nil)
    end

    test "a territory wide enough to include the cheapest route changes nothing" do
      territory = MapSet.new([1, 9, 17])
      assert Unit.bfs_path(tick_state(), 1, 17, :warrior, territory) == [9, 17]
    end

    test "a territory that excludes the cheapest route's own tile forces the pricier detour that stays inside it" do
      territory = MapSet.new([1, 10, 17])
      assert Unit.bfs_path(tick_state(), 1, 17, :warrior, territory) == [10, 17]
    end

    test "a territory that never reaches the destination at all returns nil, same as any other unreachable route" do
      territory = MapSet.new([1])
      assert Unit.bfs_path(tick_state(), 1, 17, :warrior, territory) == nil
    end
  end
end
