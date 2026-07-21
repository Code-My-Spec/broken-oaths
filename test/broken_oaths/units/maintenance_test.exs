defmodule BrokenOaths.Units.MaintenanceTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Units.Maintenance

  describe "catalog/0" do
    test "every player-owned unit type declares its own upkeep — Civ-6-grounded numbers" do
      assert Maintenance.catalog() == %{
               lord: 0,
               settler: 0,
               worker: 0,
               warrior: 0,
               archer: 1,
               bronze_spearman: 1,
               galley: 1,
               scout: 1
             }
    end
  end

  describe "upkeep/1" do
    test "the leader, both civilians, and the free starter warrior cost nothing" do
      assert Maintenance.upkeep(:lord) == 0
      assert Maintenance.upkeep(:settler) == 0
      assert Maintenance.upkeep(:worker) == 0
      assert Maintenance.upkeep(:warrior) == 0
    end

    test "every other military type costs 1 gold/turn" do
      assert Maintenance.upkeep(:archer) == 1
      assert Maintenance.upkeep(:bronze_spearman) == 1
      assert Maintenance.upkeep(:galley) == 1
      # Story 931 — the Scout: a real, combat-capable buildable (unlike
      # the free starter Warrior), so it follows the same "every OTHER
      # military type costs 1" rule.
      assert Maintenance.upkeep(:scout) == 1
    end

    test "a barbarian warrior (never player-owned) is 0, not a raise" do
      assert Maintenance.upkeep(:barbarian_warrior) == 0
    end

    test "an unrecognized type falls back to 0 rather than raising" do
      assert Maintenance.upkeep(:trebuchet) == 0
    end

    test "accepts a unit-shaped map the same way Units.Actions.available/1 does" do
      assert Maintenance.upkeep(%{type: :archer, id: 1, hp: 20}) == 1
      assert Maintenance.upkeep(%{type: :settler}) == 0
    end
  end
end
