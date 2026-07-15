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
      assert Yields.tile_yield(%Terrain{base: :grassland, relief: :hills}) == %{food: 2, production: 1}
      assert Yields.tile_yield(%Terrain{base: :grassland, feature: :woods}) == %{food: 2, production: 1}

      assert Yields.tile_yield(%Terrain{base: :grassland, relief: :hills, feature: :woods}) ==
               %{food: 2, production: 2}

      assert Yields.tile_yield(%Terrain{base: :grassland, feature: :rainforest}) == %{food: 3, production: 0}
      assert Yields.tile_yield(%Terrain{base: :grassland, feature: :marsh}) == %{food: 3, production: 0}
    end

    test "plains stacks: flat, hills, woods, hills+woods, rainforest" do
      assert Yields.tile_yield(%Terrain{base: :plains}) == %{food: 1, production: 1}
      assert Yields.tile_yield(%Terrain{base: :plains, relief: :hills}) == %{food: 1, production: 2}
      assert Yields.tile_yield(%Terrain{base: :plains, feature: :woods}) == %{food: 1, production: 2}

      assert Yields.tile_yield(%Terrain{base: :plains, relief: :hills, feature: :woods}) ==
               %{food: 1, production: 3}

      assert Yields.tile_yield(%Terrain{base: :plains, feature: :rainforest}) == %{food: 2, production: 1}
    end

    test "desert and snow: nothing flat, +1 production on hills" do
      assert Yields.tile_yield(%Terrain{base: :desert}) == %{food: 0, production: 0}
      assert Yields.tile_yield(%Terrain{base: :desert, relief: :hills}) == %{food: 0, production: 1}
      assert Yields.tile_yield(%Terrain{base: :snow}) == %{food: 0, production: 0}
      assert Yields.tile_yield(%Terrain{base: :snow, relief: :hills}) == %{food: 0, production: 1}
    end

    test "tundra: flat, hills, hills+woods" do
      assert Yields.tile_yield(%Terrain{base: :tundra}) == %{food: 1, production: 0}
      assert Yields.tile_yield(%Terrain{base: :tundra, relief: :hills}) == %{food: 1, production: 1}

      assert Yields.tile_yield(%Terrain{base: :tundra, relief: :hills, feature: :woods}) ==
               %{food: 1, production: 2}
    end

    test "coast and ocean are flat 1 food" do
      assert Yields.tile_yield(%Terrain{base: :coast}) == %{food: 1, production: 0}
      assert Yields.tile_yield(%Terrain{base: :ocean}) == %{food: 1, production: 0}
    end

    test "mountains never yield anything, regardless of base" do
      assert Yields.tile_yield(%Terrain{base: :grassland, relief: :mountains}) == %{food: 0, production: 0}
      assert Yields.tile_yield(%Terrain{base: :tundra, relief: :mountains}) == %{food: 0, production: 0}
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
      assert Yields.center_yield(city, world()) == Yields.city_center_yield(Regions.terrain(world(), city_tile))
    end

    test "a completed improvement's bonus is included, an in-progress one is not" do
      city_tile = 0
      [worked_tile | _] = Regions.adjacent_tiles(world(), city_tile)
      city = %{tile_id: city_tile, worked_tiles: [worked_tile]}
      terrain = Regions.terrain(world(), worked_tile)

      complete = %{worked_tile => %{kind: :farm, status: :complete}}
      building = %{worked_tile => %{kind: :farm, status: :building}}

      assert Yields.worked_yields(city, world(), complete) == [Yields.worked_tile_yield(terrain, :farm)]
      assert Yields.worked_yields(city, world(), building) == [Yields.worked_tile_yield(terrain, nil)]
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
      city = %{tile_id: city_tile, territory: [city_tile | neighbors], worked_tiles: [already_worked]}

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
end
