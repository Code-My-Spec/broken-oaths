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

  See `criterion_7674`'s own moduledoc for the gold-income gap this
  spec works around the same way. This criterion is WHY that spec kept
  `Fixtures.set_player_gold/3` (the treasury BALANCE) and `Fixtures.
  set_player_gold_income/3` (this turn's gold INCOME) as two SEPARATE
  test-only facts rather than one: an "empty treasury" going into debt
  only makes sense if tribute is computed from an income figure
  independent of what the vassal's treasury already holds — otherwise
  a rate capped at 100% could never skim more than the balance itself
  contains, and debt would be structurally impossible to reach.

  ## An existing obstacle this spec's own RED signal also catches

  `Game.Player.changeset/2` already calls `validate_number(:gold,
  greater_than_or_equal_to: 0)` — the schema itself currently FORBIDS a
  negative balance outright. Whatever writes a tribute-driven negative
  balance will need to loosen that constraint (or bypass the changeset
  for tribute writes), a second, independent gap this criterion's own
  failure surfaces alongside `BrokenOaths.Game.Tribute` not existing at
  all yet.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a vassal with an empty treasury goes into debt paying tribute" do
    scenario "tribute due against an empty treasury drives the vassal's balance negative" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my vassal's treasury is empty, yet they still earn 12 gold/turn income", context do
        context = a_freshly_subjugated_vassal(context)

        :ok = Fixtures.set_player_gold(context.world, context.other_user, 0)
        :ok = Fixtures.set_player_gold_income(context.world, context.other_user, 12)

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
