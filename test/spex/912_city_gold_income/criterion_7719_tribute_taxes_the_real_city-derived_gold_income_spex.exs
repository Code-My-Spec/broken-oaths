defmodule BrokenOathsSpex.Story912.Criterion7719Spex do
  @moduledoc """
  Story 912 — City Gold Income
  Criterion 7719 — `BrokenOaths.Feudal.Tribute` now taxes a vassal's REAL
  per-turn city gold income (`Yields.city_gold_income/2`, summed by
  `WorldServer.gold_income_by_player/1`), not the test-only
  `set_player_gold_income_for_test` seam story 908 originally shipped
  against (QA issue 589386f2's own root cause: that seam was never
  exposed anywhere in the live game, so gold tribute could never fire
  for real). This is story 912's own proof that the dependency gap is
  closed; `BrokenOathsSpex.Story908.Criterion7674Spex` carries the
  equivalent reconciled worked-example test from story 908's own side.

  Grows the vassal's captured city to size 4 (`SharedGivens.
  grow_city_to/5`) so its real income is deterministically >= 3
  (`base_gold(4) = 3`, `tile_gold/1` only ever adds on top) —
  comfortably enough for `Tribute.tribute_amount/2`'s own
  `round(income * rate)` to skim a real, non-zero tribute at the
  default 25% rate regardless of whichever tiles this run's own growth
  happened to claim.

  The LORD never goes offline in this scenario (`a_freshly_subjugated_
  vassal/1` never calls `go_offline` on `context.play_live`), so their
  OWN city also earns its own real income on the SAME boundary — folded
  into the lord's own expected gain here (`real_gold_income/2` read for
  BOTH players) so this isn't mistaken for a tribute-only measurement.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "tribute taxes the real city-derived gold income" do
    scenario "a lord's tribute skim exactly matches the vassal's real per-turn gold income times the rate" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my vassal's captured city has grown to size 4, and they've gone offline", context do
        context = a_freshly_subjugated_vassal(context)
        grow_city_to(context.world, context.other_user, context.other_city.id, 4)
        go_offline(context.other_play_live)
        {:ok, context}
      end

      when_ "a turn boundary passes", context do
        vassal_income = real_gold_income(context.world, context.other_user)
        lord_income = real_gold_income(context.world, context.user)
        vassal_gold0 = Fixtures.gold(context.world, context.other_user)
        lord_gold0 = Fixtures.gold(context.world, context.user)

        Fixtures.advance_turn(context.world)

        {:ok,
         context
         |> Map.put(:vassal_income, vassal_income)
         |> Map.put(:lord_income, lord_income)
         |> Map.put(:vassal_gold0, vassal_gold0)
         |> Map.put(:lord_gold0, lord_gold0)}
      end

      then_ "tribute = round(real income x 25%) moved from the vassal's own treasury to the lord's",
            context do
        assert context.my_lord.tile_id == context.other_city.tile_id
        assert context.vassal_income >= 3

        expected_tribute = round(context.vassal_income * 0.25)
        assert expected_tribute > 0

        assert Fixtures.gold(context.world, context.other_user) ==
                 context.vassal_gold0 - expected_tribute

        assert Fixtures.gold(context.world, context.user) ==
                 context.lord_gold0 + expected_tribute + context.lord_income

        {:ok, context}
      end
    end
  end
end
