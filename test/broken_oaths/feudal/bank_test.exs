defmodule BrokenOaths.Feudal.BankTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Feudal.Bank

  describe "starting_cap/0 and upgrade_cost/1" do
    test "starting_cap is a fixed, positive figure" do
      assert Bank.starting_cap() == 100
    end

    test "upgrade_cost scales with the current cap" do
      assert Bank.upgrade_cost(100) == 500
      assert Bank.upgrade_cost(200) == 1000
    end

    test "upgraded_cap raises the cap by a fixed increment" do
      assert Bank.upgraded_cap(100) == 200
      assert Bank.upgraded_cap(200) == 300
    end
  end

  describe "accrue/3" do
    test "a modest income accrues below the cap" do
      assert Bank.accrue(0, 100, 5) == 5
      assert Bank.accrue(10, 100, 5) == 15
    end

    test "accrual holds at the cap and wastes the overflow" do
      assert Bank.accrue(95, 100, 50) == 100
      assert Bank.accrue(100, 100, 50) == 100
    end

    test "a non-positive income never moves the banked figure" do
      assert Bank.accrue(10, 100, 0) == 10
      assert Bank.accrue(10, 100, -5) == 10
    end
  end

  describe "settle_income/3" do
    test "a logged-in player's income lands in the treasury, not the bank" do
      player = %{gold: 50, banked_gold: 0, bank_cap: 100}
      settled = Bank.settle_income(player, 5, true)

      assert settled.gold == 55
      assert settled.banked_gold == 0
    end

    test "an offline player's income accrues into the bank, leaving the treasury untouched" do
      player = %{gold: 50, banked_gold: 0, bank_cap: 100}
      settled = Bank.settle_income(player, 5, false)

      assert settled.gold == 50
      assert settled.banked_gold == 5
    end

    test "an offline player's bank holds at the cap regardless of overflow" do
      player = %{gold: 50, banked_gold: 98, bank_cap: 100}
      settled = Bank.settle_income(player, 50, false)

      assert settled.banked_gold == 100
    end

    test "a non-positive income is a no-op either way" do
      online = %{gold: 50, banked_gold: 0, bank_cap: 100}
      offline = %{gold: 50, banked_gold: 10, bank_cap: 100}

      assert Bank.settle_income(online, 0, true) == online
      assert Bank.settle_income(offline, -3, false) == offline
    end
  end

  describe "collect/1 and steward_collect/1" do
    test "sweeps the entire bank into the treasury, emptying it" do
      player = %{gold: 10, banked_gold: 25, bank_cap: 100}
      {new_player, swept} = Bank.collect(player)

      assert swept == 25
      assert new_player.gold == 35
      assert new_player.banked_gold == 0
    end

    test "collecting an empty bank moves nothing" do
      player = %{gold: 10, banked_gold: 0, bank_cap: 100}
      {new_player, swept} = Bank.collect(player)

      assert swept == 0
      assert new_player == player
    end

    test "steward_collect/1 is identical, pure-stewardship math — nothing kept back" do
      player = %{gold: 10, banked_gold: 25, bank_cap: 100}
      assert Bank.steward_collect(player) == Bank.collect(player)
    end
  end

  describe "upgrade/1 and can_afford_upgrade?/1" do
    test "an affordable upgrade raises the cap and charges the cost" do
      player = %{gold: 1_000, banked_gold: 0, bank_cap: 100}

      assert Bank.can_afford_upgrade?(player)
      assert {:ok, upgraded} = Bank.upgrade(player)
      assert upgraded.bank_cap == 200
      assert upgraded.gold == 1_000 - Bank.upgrade_cost(100)
    end

    test "an unaffordable upgrade is refused, with the player untouched" do
      player = %{gold: 0, banked_gold: 0, bank_cap: 100}

      refute Bank.can_afford_upgrade?(player)
      assert Bank.upgrade(player) == {:error, :insufficient_gold}
    end

    test "affordability is exact — the boundary itself succeeds" do
      cost = Bank.upgrade_cost(100)
      player = %{gold: cost, banked_gold: 0, bank_cap: 100}

      assert Bank.can_afford_upgrade?(player)
      assert {:ok, upgraded} = Bank.upgrade(player)
      assert upgraded.gold == 0
    end
  end

  describe "status/1" do
    test "reads the bank's own holdings and cap off any player-shaped map" do
      assert Bank.status(%{banked_gold: 7, bank_cap: 100}) == %{gold: 7, cap: 100}
    end
  end
end
