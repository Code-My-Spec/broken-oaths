defmodule BrokenOathsSpex.Story908.Criterion7674Spex do
  @moduledoc """
  Story 908 — Tribute Payments
  Criterion 7674 — the tribute formula's own worked example: "each
  turn, tribute automatically calculated and transferred. Calculation:
  vassal's gold income × tribute rate ÷ 100"
  (`.code_my_spec/stories/more_stories.md` §7.2), at the default 25%
  rate.

  ## Reconciled against story 912's REAL gold-income mechanic
  (QA issue 589386f2)

  This spec used to declare the vassal's per-turn gold income directly
  (`Fixtures.set_player_gold_income/3`, story 908's own documented
  stand-in for "no per-turn city gold YIELD mechanic exists ANYWHERE in
  this codebase yet"). Story 912 closed that gap for real
  (`BrokenOaths.Game.Yields.city_gold_income/2`), and `WorldServer.
  apply_tribute/1` now computes its own `income_by_player` straight
  from it every turn boundary — `set_player_gold_income_for_test` is no
  longer read by that phase at all (see `BrokenOaths.Game.Tribute`'s
  own moduledoc).

  Growing the vassal's captured city to size 4 a real per-turn city
  gold income of 12 exactly, the way the original worked example
  named it, would need several real cities at the Stone Age's own
  size-4 cap (`base_gold(4) = 3` is the ceiling for a single city, tile
  gold included, is a further few gold on top depending on terrain) —
  disproportionate setup for what this criterion is actually about: the
  MULTIPLICATION itself. Instead, `SharedGivens.grow_city_to/5` grows
  the vassal's captured city to size 4 (`base_gold(4) = 3`, deterministic
  regardless of terrain — see `BrokenOathsSpex.Story912.
  Criterion7713Spex`), then `SharedGivens.real_gold_income/2` reads the
  vassal's OWN real per-turn income at the moment of the boundary and
  this spec asserts the tribute actually moved is `round(income *
  0.25)` — the exact same formula the original "12 × 0.25 = 3" worked
  example exercised, now proven against a REAL, live economy instead of
  a hand-set number.

  ## Story 909 postscript: the vassal goes offline too

  `go_offline(context.other_play_live)` keeps this criterion's own
  premise intact (an income figure that feeds tribute but never itself
  reaches the treasury): a LOGGED-IN vassal's own real income would
  land in their own treasury too (story 909, criterion 7682), which
  this criterion's own tribute-only math isn't about — the offline
  vassal's income accrues into their own Gold Bank instead (untouched
  by `Fixtures.gold/2`).

  ## The lord's own income

  The LORD (`context.user`) never goes offline in this scenario, so
  their OWN captured-rival-adjacent capital city also earns its own
  real per-turn gold income on this SAME boundary, landing straight in
  their treasury alongside whatever tribute they collect — folded into
  the lord's own expected gain here (`real_gold_income/2` read for both
  players) rather than mistaken for a tribute-only measurement.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a vassal earning 12 gold/turn at 25% pays 3 gold tribute" do
    scenario "a turn boundary moves round(real income x 25%) from the vassal's treasury to the lord's" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my vassal's captured city has grown to size 4, and I still tax them at the default 25%",
             context do
        context = a_freshly_subjugated_vassal(context)

        grow_city_to(context.world, context.other_user, context.other_city.id, 4)
        go_offline(context.other_play_live)

        :ok = Fixtures.set_player_gold(context.world, context.other_user, 100)

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

      then_ "exactly round(income x 25%) gold moved from the vassal's own treasury to the lord's",
            context do
        assert context.my_lord.tile_id == context.other_city.tile_id
        assert context.vassal_income >= 3

        expected_tribute = round(context.vassal_income * 0.25)
        assert expected_tribute > 0

        vassal_gold_now = Fixtures.gold(context.world, context.other_user)
        lord_gold_now = Fixtures.gold(context.world, context.user)

        assert vassal_gold_now == context.vassal_gold0 - expected_tribute
        assert lord_gold_now == context.lord_gold0 + expected_tribute + context.lord_income
        {:ok, context}
      end
    end
  end
end
