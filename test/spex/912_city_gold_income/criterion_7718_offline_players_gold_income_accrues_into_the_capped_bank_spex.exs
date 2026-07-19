defmodule BrokenOathsSpex.Story912.Criterion7718Spex do
  @moduledoc """
  Story 912 — City Gold Income
  Criterion 7718 — an offline player's REAL per-turn city gold income
  accrues into their own capped Gold Bank (story 909's
  `BrokenOaths.Game.Bank.settle_income/3`, fed a real figure —
  `BrokenOaths.Game.Yields.city_gold_income/2` summed by `WorldServer.
  gold_income_by_player/1` — rather than story 909's own original
  test-only `set_player_gold_income_for_test` seam, which
  `apply_bank/1` no longer reads at all).

  See `BrokenOathsSpex.SharedGivens.go_offline/1`'s own moduledoc for
  why a disconnected LiveView socket is this codebase's real "offline"
  signal, and `criterion_7717`'s own moduledoc for why a single, grown
  city already exercises the SAME per-player summation a multi-city
  player would.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "an offline player's gold income accrues into the capped bank" do
    scenario "a real, grown city's income banks while its owner is offline, leaving the treasury untouched" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "my city has grown to size 4, and I've gone offline", context do
        grow_city_to(context.world, context.user, context.city.id, 4)
        go_offline(context.play_live)
        {:ok, context}
      end

      when_ "a turn boundary passes while I'm offline", context do
        treasury0 = Fixtures.gold(context.world, context.user)
        income = real_gold_income(context.world, context.user)
        Fixtures.advance_turn(context.world)

        {:ok, context |> Map.put(:treasury0, treasury0) |> Map.put(:income, income)}
      end

      then_ "the bank holds exactly that income, and my treasury never moved", context do
        assert context.income >= 3
        assert Fixtures.gold(context.world, context.user) == context.treasury0
        assert Fixtures.bank_status(context.world, context.user).gold == context.income
        {:ok, context}
      end
    end
  end
end
