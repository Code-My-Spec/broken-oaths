defmodule BrokenOaths.Cities.BuildingsTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Cities.Buildings

  describe "catalog/0 and maintenance/1" do
    test "the Granary costs 1 gold/turn — today's only building" do
      assert Buildings.catalog() == %{granary: 1}
      assert Buildings.maintenance(:granary) == 1
    end

    test "an undeclared building raises rather than silently defaulting" do
      assert_raise KeyError, fn -> Buildings.maintenance(:library) end
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
  end
end
