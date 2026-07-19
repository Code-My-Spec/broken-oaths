defmodule BrokenOathsSpex.Story908.Criterion7676Spex do
  @moduledoc """
  Story 908 — Tribute Payments
  Criterion 7676 — "If vassal has insufficient gold, they go into debt
  (negative balance)" (`.code_my_spec/stories/more_stories.md` §7.2),
  confirmed as an intentional design choice, not a bug to guard
  against: "Tribute debt: accrues; negative balance allowed; NO
  auto-penalty. Being in the red blocks the vassal's own spending until
  repaid, and the lord simply goes unpaid"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Round-5
  decisions").

  ## Reconciled against story 912's REAL gold-income mechanic
  (QA issue 589386f2)

  This spec used to declare the vassal's per-turn gold income directly
  (`Fixtures.set_player_gold_income/3`), independent of the treasury
  balance `Fixtures.set_player_gold/3` sets — see `criterion_7674`'s
  own moduledoc for why that seam no longer feeds `apply_tribute/1` at
  all now that story 912 shipped a real per-turn city gold income
  mechanic. Rather than grow the vassal's captured city to a specific
  income figure, this instead raises the tribute RATE to 100%
  (`"set_tribute_rate"`, the same real, sanctioned lever
  `criterion_7673`/`criterion_7675` already drive) — `base_gold(1) = 1`
  alone guarantees ANY freshly captured city's real per-turn income is
  at least 1 gold, so a 100% rate against an empty treasury drives the
  vassal negative deterministically, with no dependency on whichever
  tiles this run's own worked-tile assignment happened to pick.

  ## An existing obstacle this spec's own RED signal also caught, before `Tribute` existed

  `Game.Player.changeset/2` already calls `validate_number(:gold,
  greater_than_or_equal_to: 0)` — the schema itself would otherwise
  forbid a negative balance outright; `Tribute`'s own write path bypasses
  the changeset for exactly this reason (see its own moduledoc).

  ## Story 909 postscript: the vassal goes offline too

  `go_offline(context.other_play_live)` keeps this criterion's own
  premise intact (an income figure that feeds tribute but never itself
  reaches the treasury): a LOGGED-IN vassal's own real income would
  land in their own treasury too (story 909), more than covering a
  modest tribute and making "goes into debt" much harder to reach
  reliably.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a vassal with an empty treasury goes into debt paying tribute" do
    scenario "tribute due against an empty treasury, at a 100% rate, drives the vassal's balance negative" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my vassal's treasury is empty, and I've raised their tribute rate to 100%",
             context do
        context = a_freshly_subjugated_vassal(context)

        go_offline(context.other_play_live)

        :ok = Fixtures.set_player_gold(context.world, context.other_user, 0)

        attempt_event(context.play_live, "set_tribute_rate", %{
          "vassal_user_id" => to_string(context.other_user.id),
          "rate" => "100"
        })

        assert Fixtures.gold(context.world, context.other_user) == 0
        {:ok, context}
      end

      when_ "a turn boundary passes and tribute comes due", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the vassal's own treasury reads negative — in debt, not floored at zero", context do
        assert context.my_lord.tile_id == context.other_city.tile_id

        vassal_gold_now = Fixtures.gold(context.world, context.other_user)
        assert vassal_gold_now < 0
        {:ok, context}
      end
    end
  end
end
