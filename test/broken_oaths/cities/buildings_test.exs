defmodule BrokenOaths.Cities.BuildingsTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Cities.Buildings

  describe "catalog/0 and maintenance/1" do
    test "story 930's four new buildings alongside the Granary" do
      assert Buildings.catalog() == %{
               granary: 1,
               library: 1,
               ancient_walls: 0,
               barracks: 1,
               water_mill: 1,
               pyramids: 0,
               hanging_gardens: 0
             }

      assert Buildings.maintenance(:granary) == 1
      assert Buildings.maintenance(:library) == 1
      assert Buildings.maintenance(:ancient_walls) == 0
      assert Buildings.maintenance(:barracks) == 1
      assert Buildings.maintenance(:water_mill) == 1
      assert Buildings.maintenance(:pyramids) == 0
      assert Buildings.maintenance(:hanging_gardens) == 0
    end

    test "an undeclared building raises rather than silently defaulting" do
      assert_raise KeyError, fn -> Buildings.maintenance(:temple) end
    end
  end

  describe "has?/2" do
    test "the Granary reads the lone has_granary boolean" do
      assert Buildings.has?(%{has_granary: true}, :granary)
      refute Buildings.has?(%{has_granary: false}, :granary)
      refute Buildings.has?(%{}, :granary)
    end

    test "every other building reads the buildings list" do
      assert Buildings.has?(%{buildings: [:library]}, :library)
      refute Buildings.has?(%{buildings: [:library]}, :barracks)
      refute Buildings.has?(%{}, :library)
    end
  end

  describe "city_upkeep/1" do
    test "a city with a Granary owes its maintenance" do
      assert Buildings.city_upkeep(%{has_granary: true}) == 1
    end

    test "a city without a Granary owes nothing" do
      assert Buildings.city_upkeep(%{has_granary: false}) == 0
    end

    test "a hand-built city fixture missing the field defaults to no Granary" do
      assert Buildings.city_upkeep(%{}) == 0
    end

    test "sums every one of a city's buildings, granary and the list alike" do
      city = %{has_granary: true, buildings: [:library, :barracks, :water_mill]}
      # granary 1 + library 1 + barracks 1 + water_mill 1 == 4.
      assert Buildings.city_upkeep(city) == 4
    end

    test "Ancient Walls carries no maintenance" do
      assert Buildings.city_upkeep(%{buildings: [:ancient_walls]}) == 0
    end

    test "a wonder carries no maintenance either" do
      assert Buildings.city_upkeep(%{buildings: [:pyramids, :hanging_gardens]}) == 0
    end
  end

  # Story 933 — the Pyramids/Hanging Gardens world wonders.
  describe "wonder?/1" do
    test "true for the two wonders" do
      assert Buildings.wonder?(:pyramids)
      assert Buildings.wonder?(:hanging_gardens)
    end

    test "false for every standard building" do
      refute Buildings.wonder?(:granary)
      refute Buildings.wonder?(:library)
      refute Buildings.wonder?(:ancient_walls)
      refute Buildings.wonder?(:barracks)
      refute Buildings.wonder?(:water_mill)
    end
  end

  describe "wonder_built_or_building?/2" do
    test "false when no city anywhere has it built or queued" do
      cities = [%{buildings: [], queue: []}, %{buildings: [:library], queue: []}]
      refute Buildings.wonder_built_or_building?(cities, :pyramids)
    end

    test "true once ANY city has it completed" do
      cities = [%{buildings: [], queue: []}, %{buildings: [:pyramids], queue: []}]
      assert Buildings.wonder_built_or_building?(cities, :pyramids)
    end

    test "true once ANY city has it queued, even unfinished" do
      cities = [%{buildings: [], queue: [%{type: :pyramids, banked: 10, cost: 220}]}]
      assert Buildings.wonder_built_or_building?(cities, :pyramids)
    end

    test "each wonder is tracked independently" do
      cities = [%{buildings: [:pyramids], queue: []}]
      assert Buildings.wonder_built_or_building?(cities, :pyramids)
      refute Buildings.wonder_built_or_building?(cities, :hanging_gardens)
    end
  end

  describe "player_has?/3" do
    test "true when ANY city that player owns has the building — not just the one queried" do
      cities = [
        %{player_id: 1, buildings: [:pyramids]},
        %{player_id: 1, buildings: []}
      ]

      assert Buildings.player_has?(cities, 1, :pyramids)
    end

    test "false for a different player, even if someone else holds it" do
      cities = [%{player_id: 1, buildings: [:pyramids]}]
      refute Buildings.player_has?(cities, 2, :pyramids)
    end

    test "false with no cities at all" do
      refute Buildings.player_has?([], 1, :pyramids)
    end
  end
end
