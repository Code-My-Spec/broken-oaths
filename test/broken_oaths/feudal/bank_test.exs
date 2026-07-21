defmodule BrokenOaths.Feudal.BankTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Feudal.Bank
  alias BrokenOaths.Players.Presence

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

  # -------------------------------------------------------------------
  # Upkeep and disband-when-broke (stories 922/923)
  # -------------------------------------------------------------------

  describe "maintenance_by_player/1" do
    test "sums unit upkeep and building upkeep per owning player" do
      state = %{
        units: %{
          1 => unit(1, 10, :archer),
          2 => unit(2, 10, :bronze_spearman),
          3 => unit(3, 20, :warrior)
        },
        cities: %{1 => city(1, 10, has_granary: true), 2 => city(2, 20, has_granary: false)}
      }

      # Player 10: archer (1) + bronze_spearman (1) + granary (1) == 3.
      # Player 20: warrior (0), no granary == 0.
      assert Bank.maintenance_by_player(state) == %{10 => 3, 20 => 0}
    end

    # Story 930 — the four newer buildings owe upkeep exactly like the
    # Granary, read off the SAME `Buildings.city_upkeep/1` this test's
    # sibling above already exercises for `has_granary`.
    test "the four newer buildings owe their own maintenance too" do
      state = %{
        units: %{},
        cities: %{
          1 => city(1, 10, buildings: [:library, :barracks, :water_mill]),
          2 => city(2, 20, buildings: [:ancient_walls])
        }
      }

      # Player 10: library (1) + barracks (1) + water_mill (1) == 3.
      # Player 20: ancient_walls (0) == 0.
      assert Bank.maintenance_by_player(state) == %{10 => 3, 20 => 0}
    end

    test "a unit with no owner (a barbarian) never counts toward anyone's bill" do
      state = %{
        units: %{1 => %{id: 1, type: :barbarian_warrior, player_id: nil}},
        cities: %{}
      }

      assert Bank.maintenance_by_player(state) == %{}
    end
  end

  describe "apply_upkeep/2" do
    test "a surplus flows to the treasury exactly like apply_income/3" do
      player = player(1, gold: 50)
      # `Presence.online?/2` reads live off the registry — connect this
      # test process as `player.user_id`'s own live session, same as
      # `settle_income/3`'s own `true` branch requires, so the surplus
      # lands in `gold`, not the offline `banked_gold` accrual.
      Presence.connect(%{id: 1}, %{id: player.user_id})
      # One archer (upkeep 1); income of 5 nets to +4.
      state = state_with([player], [unit(1, 1, :archer)], [])

      {new_state, alerts} = Bank.apply_upkeep(state, %{1 => 5})

      assert new_state.players[1].gold == 54
      assert new_state.players[1].banked_gold == 0
      assert alerts == []
    end

    test "a deficit smaller than savings deducts straight from the treasury" do
      player = player(1, gold: 10)
      # Two archers, upkeep 2; zero income nets to -2, well within savings.
      state = state_with([player], [unit(1, 1, :archer), unit(2, 1, :archer)], [])

      {new_state, alerts} = Bank.apply_upkeep(state, %{})

      assert new_state.players[1].gold == 8
      assert alerts == []
      assert map_size(new_state.units) == 2
    end

    test "a deficit larger than savings clamps gold to 0 and disbands the newest non-Lord military unit" do
      player = player(1, gold: 0)
      # lord (0 upkeep, never eligible), an old settler, a newer warrior
      # (0 upkeep but IS military-eligible), and a bronze_spearman (id 4,
      # the newest military unit, upkeep 1) — with no gold saved at all,
      # the -1 deficit can't be covered.
      units = [
        %{id: 1, type: :lord, player_id: 1},
        %{id: 2, type: :settler, player_id: 1},
        %{id: 3, type: :warrior, player_id: 1},
        unit(4, 1, :bronze_spearman)
      ]

      state = state_with([player], units, [])

      {new_state, alerts} = Bank.apply_upkeep(state, %{})

      assert new_state.players[1].gold == 0
      refute Map.has_key?(new_state.units, 4)
      assert Map.has_key?(new_state.units, 1)
      assert Map.has_key?(new_state.units, 2)
      assert Map.has_key?(new_state.units, 3)
      assert [{:city_alert, 999, message}] = alerts
      assert message =~ "bronze spearman"
    end

    test "military is preferred over civilian regardless of which is newer" do
      player = player(1, gold: 0)
      # settler (id 9, newest overall, but civilian) vs. archer (id 2,
      # older, but military) — the archer must go.
      units = [unit(2, 1, :archer), %{id: 9, type: :settler, player_id: 1}]
      state = state_with([player], units, [])

      {new_state, _alerts} = Bank.apply_upkeep(state, %{})

      refute Map.has_key?(new_state.units, 2)
      assert Map.has_key?(new_state.units, 9)
    end

    test "the newest unit within the preferred pool is the one disbanded" do
      player = player(1, gold: 0)
      units = [unit(2, 1, :archer), unit(5, 1, :galley)]
      state = state_with([player], units, [])

      {new_state, _alerts} = Bank.apply_upkeep(state, %{})

      refute Map.has_key?(new_state.units, 5)
      assert Map.has_key?(new_state.units, 2)
    end

    test "a broke player with only a Lord stays clamped at 0 with no disband" do
      player = player(1, gold: 0)
      state = state_with([player], [%{id: 1, type: :lord, player_id: 1}], [%{id: 1, player_id: 1, has_granary: true}])

      {new_state, alerts} = Bank.apply_upkeep(state, %{})

      assert new_state.players[1].gold == 0
      assert Map.has_key?(new_state.units, 1)
      assert alerts == []
    end

    test "a zero-upkeep world ticks identically to plain apply_income/3" do
      player = player(1, gold: 50)
      units = [%{id: 1, type: :lord, player_id: 1}, %{id: 2, type: :warrior, player_id: 1}]
      state = state_with([player], units, [])

      {upkeep_state, alerts} = Bank.apply_upkeep(state, %{1 => 7})
      plain_players = Bank.apply_income(state.players, %{1 => 7}, state.world)

      assert upkeep_state.players == plain_players
      assert alerts == []
      assert map_size(upkeep_state.units) == 2
    end
  end

  defp state_with(players, units, cities) do
    %{
      world: %{id: 1},
      players: Map.new(players, &{&1.id, &1}),
      units: Map.new(units, &{&1.id, &1}),
      cities: Map.new(cities, &{&1.id, &1})
    }
  end

  defp player(id, overrides),
    do: Map.merge(%{id: id, user_id: 999, gold: 0, banked_gold: 0, bank_cap: 100}, Map.new(overrides))

  defp unit(id, player_id, type), do: %{id: id, type: type, player_id: player_id}

  defp city(id, player_id, overrides),
    do: Map.merge(%{id: id, player_id: player_id}, Map.new(overrides))
end
