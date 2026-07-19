defmodule BrokenOaths.Game.YieldsTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Game.Yields
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.Terrain
  alias BrokenOaths.Worlds.World

  # Same fixture pair the rest of the functional core tests against
  # (see turn_test.exs, spawner_test.exs) — 642 tiles, no hills
  # anywhere (verified by scanning every tile), which is exactly why
  # it's useful here: any plains/grassland tile found on it is
  # guaranteed flat.
  @frequency 8
  @seed 424_242

  defp world, do: %World{seed: @seed, frequency: @frequency}

  # -------------------------------------------------------------------
  # Raw terrain yield — the canonical table
  # (.code_my_spec/knowledge/stone_age_yields.md)
  # -------------------------------------------------------------------

  describe "tile_yield/1" do
    test "grassland stacks: flat, hills, woods, hills+woods, rainforest, marsh" do
      assert Yields.tile_yield(%Terrain{base: :grassland}) == %{food: 2, production: 0}

      assert Yields.tile_yield(%Terrain{base: :grassland, relief: :hills}) == %{
               food: 2,
               production: 1
             }

      assert Yields.tile_yield(%Terrain{base: :grassland, feature: :woods}) == %{
               food: 2,
               production: 1
             }

      assert Yields.tile_yield(%Terrain{base: :grassland, relief: :hills, feature: :woods}) ==
               %{food: 2, production: 2}

      assert Yields.tile_yield(%Terrain{base: :grassland, feature: :rainforest}) == %{
               food: 3,
               production: 0
             }

      assert Yields.tile_yield(%Terrain{base: :grassland, feature: :marsh}) == %{
               food: 3,
               production: 0
             }
    end

    test "plains stacks: flat, hills, woods, hills+woods, rainforest" do
      assert Yields.tile_yield(%Terrain{base: :plains}) == %{food: 1, production: 1}

      assert Yields.tile_yield(%Terrain{base: :plains, relief: :hills}) == %{
               food: 1,
               production: 2
             }

      assert Yields.tile_yield(%Terrain{base: :plains, feature: :woods}) == %{
               food: 1,
               production: 2
             }

      assert Yields.tile_yield(%Terrain{base: :plains, relief: :hills, feature: :woods}) ==
               %{food: 1, production: 3}

      assert Yields.tile_yield(%Terrain{base: :plains, feature: :rainforest}) == %{
               food: 2,
               production: 1
             }
    end

    test "desert and snow: nothing flat, +1 production on hills" do
      assert Yields.tile_yield(%Terrain{base: :desert}) == %{food: 0, production: 0}

      assert Yields.tile_yield(%Terrain{base: :desert, relief: :hills}) == %{
               food: 0,
               production: 1
             }

      assert Yields.tile_yield(%Terrain{base: :snow}) == %{food: 0, production: 0}
      assert Yields.tile_yield(%Terrain{base: :snow, relief: :hills}) == %{food: 0, production: 1}
    end

    test "tundra: flat, hills, hills+woods" do
      assert Yields.tile_yield(%Terrain{base: :tundra}) == %{food: 1, production: 0}

      assert Yields.tile_yield(%Terrain{base: :tundra, relief: :hills}) == %{
               food: 1,
               production: 1
             }

      assert Yields.tile_yield(%Terrain{base: :tundra, relief: :hills, feature: :woods}) ==
               %{food: 1, production: 2}
    end

    test "coast and ocean are flat 1 food" do
      assert Yields.tile_yield(%Terrain{base: :coast}) == %{food: 1, production: 0}
      assert Yields.tile_yield(%Terrain{base: :ocean}) == %{food: 1, production: 0}
    end

    test "mountains never yield anything, regardless of base" do
      assert Yields.tile_yield(%Terrain{base: :grassland, relief: :mountains}) == %{
               food: 0,
               production: 0
             }

      assert Yields.tile_yield(%Terrain{base: :tundra, relief: :mountains}) == %{
               food: 0,
               production: 0
             }
    end

    test "ice never yields anything, regardless of base" do
      assert Yields.tile_yield(%Terrain{base: :coast, feature: :ice}) == %{food: 0, production: 0}
      assert Yields.tile_yield(%Terrain{base: :ocean, feature: :ice}) == %{food: 0, production: 0}
    end
  end

  describe "city_center_yield/1" do
    test "floors a weak tile at 2 food / 1 production" do
      assert Yields.city_center_yield(%Terrain{base: :desert}) == %{food: 2, production: 1}
      assert Yields.city_center_yield(%Terrain{base: :snow}) == %{food: 2, production: 1}
      assert Yields.city_center_yield(%Terrain{base: :grassland}) == %{food: 2, production: 1}
    end

    test "upgrades past the floor when the terrain beats it" do
      assert Yields.city_center_yield(%Terrain{base: :grassland, relief: :hills, feature: :woods}) ==
               %{food: 2, production: 2}

      assert Yields.city_center_yield(%Terrain{base: :grassland, feature: :rainforest}) ==
               %{food: 3, production: 1}
    end
  end

  describe "workable?/1" do
    test "mountains and ice are never workable" do
      refute Yields.workable?(%Terrain{base: :grassland, relief: :mountains})
      refute Yields.workable?(%Terrain{base: :coast, feature: :ice})
    end

    test "everything else is workable" do
      assert Yields.workable?(%Terrain{base: :desert})
      assert Yields.workable?(%Terrain{base: :ocean})
      assert Yields.workable?(%Terrain{base: :grassland, relief: :hills})
    end
  end

  describe "improvement_bonus/1" do
    test "farm adds food, mine adds production, road and nil add nothing" do
      assert Yields.improvement_bonus(:farm) == %{food: 2, production: 0}
      assert Yields.improvement_bonus(:mine) == %{food: 0, production: 2}
      assert Yields.improvement_bonus(:road) == %{food: 0, production: 0}
      assert Yields.improvement_bonus(nil) == %{food: 0, production: 0}
    end
  end

  describe "worked_tile_yield/2" do
    test "adds the improvement's bonus on top of raw terrain" do
      flat_grassland = %Terrain{base: :grassland}
      assert Yields.worked_tile_yield(flat_grassland, nil) == %{food: 2, production: 0}
      assert Yields.worked_tile_yield(flat_grassland, :farm) == %{food: 4, production: 0}

      hills = %Terrain{base: :plains, relief: :hills}
      assert Yields.worked_tile_yield(hills, :mine) == %{food: 1, production: 4}
    end
  end

  describe "assignment_score/1 and growth_score/1" do
    test "assignment doubles food, growth weights it evenly" do
      yield = %{food: 2, production: 1}
      assert Yields.assignment_score(yield) == 5
      assert Yields.growth_score(yield) == 3
    end
  end

  describe "threshold/1 and capped?/1" do
    test "thresholds match the documented curve and cap at size 4" do
      assert Yields.threshold(1) == 20
      assert Yields.threshold(2) == 30
      assert Yields.threshold(3) == 40
      assert Yields.threshold(4) == nil

      refute Yields.capped?(1)
      refute Yields.capped?(3)
      assert Yields.capped?(4)
      assert Yields.capped?(5)
    end
  end

  describe "threshold/2 and capped?/2 — age-aware (story 903)" do
    test "arity-1/1 stay Stone Age by default, agreeing exactly with arity-2/2's :stone_age clause" do
      for size <- 1..6 do
        assert Yields.threshold(size) == Yields.threshold(size, :stone_age)
        assert Yields.capped?(size) == Yields.capped?(size, :stone_age)
      end
    end

    test "a Stone Age city still caps at 4, even asked explicitly" do
      assert Yields.threshold(4, :stone_age) == nil
      assert Yields.threshold(5, :stone_age) == nil
      refute Yields.capped?(3, :stone_age)
      assert Yields.capped?(4, :stone_age)
    end

    test "a Bronze Age city keeps growing past 4, up to the new size-6 cap" do
      assert Yields.threshold(1, :bronze_age) == 20
      assert Yields.threshold(2, :bronze_age) == 30
      assert Yields.threshold(3, :bronze_age) == 40
      assert Yields.threshold(4, :bronze_age) == 50
      assert Yields.threshold(5, :bronze_age) == 60
      assert Yields.threshold(6, :bronze_age) == nil

      refute Yields.capped?(4, :bronze_age)
      refute Yields.capped?(5, :bronze_age)
      assert Yields.capped?(6, :bronze_age)
    end
  end

  # -------------------------------------------------------------------
  # Per-city accrual — needs real terrain, so a real (deterministic)
  # World struct rather than hand-built Terrain structs.
  # -------------------------------------------------------------------

  describe "worked_yields/3 and center_yield/2" do
    test "sums every worked tile's yield, center yield is the floored terrain" do
      city_tile = 0
      [worked_tile | _] = Regions.adjacent_tiles(world(), city_tile)
      city = %{tile_id: city_tile, worked_tiles: [worked_tile]}

      terrain = Regions.terrain(world(), worked_tile)
      expected = Yields.worked_tile_yield(terrain, nil)

      assert Yields.worked_yields(city, world(), %{}) == [expected]

      assert Yields.center_yield(city, world()) ==
               Yields.city_center_yield(Regions.terrain(world(), city_tile))
    end

    test "a completed improvement's bonus is included, an in-progress one is not" do
      city_tile = 0
      [worked_tile | _] = Regions.adjacent_tiles(world(), city_tile)
      city = %{tile_id: city_tile, worked_tiles: [worked_tile]}
      terrain = Regions.terrain(world(), worked_tile)

      complete = %{worked_tile => %{kind: :farm, status: :complete}}
      building = %{worked_tile => %{kind: :farm, status: :building}}

      assert Yields.worked_yields(city, world(), complete) == [
               Yields.worked_tile_yield(terrain, :farm)
             ]

      assert Yields.worked_yields(city, world(), building) == [
               Yields.worked_tile_yield(terrain, nil)
             ]
    end
  end

  describe "accrue_food/3" do
    test "adds the center's food plus every worked tile's food to the running total" do
      city_tile = 0
      [worked_tile | _] = Regions.adjacent_tiles(world(), city_tile)
      city = %{tile_id: city_tile, food: 3, worked_tiles: [worked_tile]}

      center_food = Yields.city_center_yield(Regions.terrain(world(), city_tile)).food
      worked_food = Yields.worked_tile_yield(Regions.terrain(world(), worked_tile), nil).food

      assert Yields.accrue_food(city, world(), %{}).food == 3 + center_food + worked_food
    end

    test "a city with no has_granary key accrues exactly as before (defensive default)" do
      city_tile = 0
      city = %{tile_id: city_tile, food: 0, worked_tiles: []}

      center_food = Yields.city_center_yield(Regions.terrain(world(), city_tile)).food
      assert Yields.accrue_food(city, world(), %{}).food == center_food
    end

    test "a Granary adds a flat +2 food on top of everything else (story 902)" do
      city_tile = 0
      city = %{tile_id: city_tile, food: 0, worked_tiles: [], has_granary: true}

      center_food = Yields.city_center_yield(Regions.terrain(world(), city_tile)).food
      assert Yields.accrue_food(city, world(), %{}).food == center_food + 2
    end

    test "has_granary: false accrues the same as no key at all" do
      city_tile = 0
      city = %{tile_id: city_tile, food: 0, worked_tiles: [], has_granary: false}

      center_food = Yields.city_center_yield(Regions.terrain(world(), city_tile)).food
      assert Yields.accrue_food(city, world(), %{}).food == center_food
    end
  end

  # -------------------------------------------------------------------
  # Gold (story 912)
  # -------------------------------------------------------------------

  describe "base_gold/1" do
    test "1 + floor(size/2), the locked story 912 curve" do
      assert Yields.base_gold(1) == 1
      assert Yields.base_gold(2) == 2
      assert Yields.base_gold(3) == 2
      assert Yields.base_gold(4) == 3
    end
  end

  describe "tile_gold/1" do
    test "Coast yields +1 gold, regardless of feature" do
      assert Yields.tile_gold(%Terrain{base: :coast}) == 1
      assert Yields.tile_gold(%Terrain{base: :coast, feature: :ice}) == 1
    end

    test "every other terrain yields 0 gold" do
      assert Yields.tile_gold(%Terrain{base: :ocean}) == 0
      assert Yields.tile_gold(%Terrain{base: :grassland}) == 0
      assert Yields.tile_gold(%Terrain{base: :plains, relief: :hills, feature: :woods}) == 0
      assert Yields.tile_gold(%Terrain{base: :desert}) == 0
      assert Yields.tile_gold(%Terrain{base: :tundra}) == 0
      assert Yields.tile_gold(%Terrain{base: :snow}) == 0
    end
  end

  describe "city_gold_income/2" do
    test "a size-1 city with no worked tiles earns only the base" do
      city = %{tile_id: 0, size: 1, worked_tiles: []}
      assert Yields.city_gold_income(city, world()) == 1
    end

    test "a landlocked size-4 city earns exactly 3 — base only, no tile gold (criterion 7713)" do
      # Every tile in this fixture's own founding ring (freq 8, seed
      # 424242) around tile 0 happens to be non-Coast — verified by the
      # same `Regions.terrain/2` read `city_gold_income/2` itself uses,
      # so this is a real, deterministic 0-tile-gold city, not an
      # assumption.
      city_tile = 0
      neighbors = Regions.adjacent_tiles(world(), city_tile)
      assert Enum.all?(neighbors, &(Regions.terrain(world(), &1).base != :coast))

      city = %{tile_id: city_tile, size: 4, worked_tiles: neighbors}
      assert Yields.city_gold_income(city, world()) == 3
    end

    test "sums base_gold + tile_gold over every worked tile" do
      city_tile = 0
      [worked_tile | _] = Regions.adjacent_tiles(world(), city_tile)
      city = %{tile_id: city_tile, size: 3, worked_tiles: [worked_tile]}

      expected = Yields.base_gold(3) + Yields.tile_gold(Regions.terrain(world(), worked_tile))
      assert Yields.city_gold_income(city, world()) == expected
    end

    test "a worked Coast tile adds its own +1 gold on top of the base (criterion 7715)" do
      coast_tile =
        Enum.find(0..(BrokenOaths.Worlds.Globe.tile_count(@frequency) - 1), fn t ->
          Regions.terrain(world(), t).base == :coast
        end)

      refute is_nil(coast_tile), "expected at least one Coast tile on this fixture's own globe"

      landlocked = %{tile_id: 0, size: 4, worked_tiles: []}
      coastal = %{landlocked | worked_tiles: [coast_tile]}

      assert Yields.city_gold_income(coastal, world()) ==
               Yields.city_gold_income(landlocked, world()) + 1
    end

    test "recomputes fresh from current size/worked_tiles — growing raises income (criterion 7716)" do
      city_tile = 0
      size1 = %{tile_id: city_tile, size: 1, worked_tiles: []}
      size4 = %{size1 | size: 4}

      assert Yields.city_gold_income(size4, world()) > Yields.city_gold_income(size1, world())
    end
  end

  # -------------------------------------------------------------------
  # Growth and deterministic tile-picking
  # -------------------------------------------------------------------

  describe "pick_growth_tile/3" do
    test "never picks a tile another city already claimed" do
      city_tile = 0
      neighbors = Regions.adjacent_tiles(world(), city_tile)
      city = %{id: 1, tile_id: city_tile, territory: [city_tile]}

      # A rival that has claimed every single neighbor leaves nothing
      # left to pick.
      rival = %{id: 2, tile_id: 9999, territory: neighbors}

      assert Yields.pick_growth_tile(city, [city, rival], world()) == nil
    end

    test "is deterministic across repeated calls with the same input" do
      city_tile = 0
      city = %{id: 1, tile_id: city_tile, territory: [city_tile]}

      first = Yields.pick_growth_tile(city, [city], world())
      second = Yields.pick_growth_tile(city, [city], world())

      assert first == second
      refute is_nil(first)
      assert first in Regions.adjacent_tiles(world(), city_tile)
    end
  end

  describe "pick_worked_tile/2" do
    test "never picks the free center or an already-worked tile" do
      city_tile = 0
      neighbors = Regions.adjacent_tiles(world(), city_tile)
      [already_worked | _] = neighbors

      city = %{
        tile_id: city_tile,
        territory: [city_tile | neighbors],
        worked_tiles: [already_worked]
      }

      pick = Yields.pick_worked_tile(city, world())

      refute pick == city_tile
      refute pick == already_worked
      assert pick in neighbors
    end

    test "returns nil once every territory tile is already worked" do
      city_tile = 0
      neighbors = Regions.adjacent_tiles(world(), city_tile)
      city = %{tile_id: city_tile, territory: [city_tile | neighbors], worked_tiles: neighbors}

      assert Yields.pick_worked_tile(city, world()) == nil
    end
  end

  describe "grow/3" do
    test "below threshold, nothing changes" do
      city = %{id: 1, tile_id: 0, size: 1, food: 19, territory: [0], worked_tiles: []}

      assert Yields.grow(city, [city], world()) == city
    end

    test "at threshold, claims a tile, grows size, carries food overflow, and works a new tile" do
      city = %{id: 1, tile_id: 0, size: 1, food: 23, territory: [0], worked_tiles: []}

      grown = Yields.grow(city, [city], world())

      assert grown.size == 2
      assert grown.food == 23 - 20
      assert length(grown.territory) == 2
      assert length(grown.worked_tiles) == 1
      assert hd(grown.worked_tiles) in grown.territory
    end

    test "at the size-4 cap, food accrues but nothing else changes" do
      city = %{id: 1, tile_id: 0, size: 4, food: 999, territory: [0], worked_tiles: []}

      assert Yields.grow(city, [city], world()) == city
    end

    test "grows at most once per call even with enough overflow for two" do
      city = %{id: 1, tile_id: 0, size: 1, food: 55, territory: [0], worked_tiles: []}

      grown = Yields.grow(city, [city], world())

      assert grown.size == 2
      assert grown.food == 55 - 20
    end
  end

  describe "grow/4 — age-aware (story 903)" do
    test "arity-3 stays Stone Age by default, agreeing exactly with arity-4's :stone_age clause" do
      city = %{id: 1, tile_id: 0, size: 4, food: 999, territory: [0], worked_tiles: []}

      assert Yields.grow(city, [city], world()) == Yields.grow(city, [city], world(), :stone_age)
    end

    test "a Stone Age city at size 4 still refuses to grow, explicit age or not" do
      city = %{id: 1, tile_id: 0, size: 4, food: 999, territory: [0], worked_tiles: []}

      assert Yields.grow(city, [city], world(), :stone_age) == city
    end

    test "a Bronze Age city at the old size-4 cap, with abundant food, grows to size 5" do
      city = %{id: 1, tile_id: 0, size: 4, food: 999, territory: [0], worked_tiles: []}

      grown = Yields.grow(city, [city], world(), :bronze_age)

      assert grown.size == 5
      assert grown.food == 999 - 50
    end

    test "a Bronze Age city at size 5, with abundant food, grows to size 6" do
      city = %{id: 1, tile_id: 0, size: 5, food: 999, territory: [0], worked_tiles: []}

      grown = Yields.grow(city, [city], world(), :bronze_age)

      assert grown.size == 6
      assert grown.food == 999 - 60
    end

    test "a Bronze Age city at the new size-6 cap stops growing — food still accrues" do
      city = %{id: 1, tile_id: 0, size: 6, food: 999, territory: [0], worked_tiles: []}

      assert Yields.grow(city, [city], world(), :bronze_age) == city
    end
  end
end
