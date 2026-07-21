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
               water_mill: 1
             }

      assert Buildings.maintenance(:granary) == 1
      assert Buildings.maintenance(:library) == 1
      assert Buildings.maintenance(:ancient_walls) == 0
      assert Buildings.maintenance(:barracks) == 1
      assert Buildings.maintenance(:water_mill) == 1
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
  end
end
