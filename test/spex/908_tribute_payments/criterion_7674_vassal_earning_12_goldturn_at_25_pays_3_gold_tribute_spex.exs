defmodule BrokenOathsSpex.Story908.Criterion7674Spex do
  @moduledoc """
  Story 908 — Tribute Payments
  Criterion 7674 — the tribute formula's own worked example: "each
  turn, tribute automatically calculated and transferred. Calculation:
  vassal's gold income × tribute rate ÷ 100"
  (`.code_my_spec/stories/more_stories.md` §7.2), at the default 25%
  rate: 12 × 0.25 = 3 gold, moving from the vassal's own treasury into
  the lord's.

  ## The gold-income gap this spec works around

  No per-turn city gold YIELD mechanic exists ANYWHERE in this codebase
  yet — `BrokenOaths.Game.Yields` only ever produces food/production; a
  player's `gold` column only ever moves via one-off barbarian bounty/
  camp-destroy rewards (`BarbarianAI.bounty_gold/0`,
  `Camps.destroy_reward/0`), never a recurring income. This predates
  and is independent of `BrokenOaths.Game.Tribute` itself. Rather than
  leave this formula untestable, this spec uses the SAME kind of
  narrow, documented test-only stand-in story 881 already established
  for the equivalent "no real source exists yet" gap on healing
  (`Fixtures.set_unit_hp/3`, before any combat existed to produce a
  damaged unit): `Fixtures.set_player_gold_income/3` declares the
  vassal's per-turn gold income directly — see `BrokenOaths.Game.
  WorldServer`'s `:set_player_gold_income_for_test` handler for the
  full rationale (a documented CONTRACT for `Game.Tribute` to read at
  its own turn-boundary phase, not a wired-up mechanic today, exactly
  like every other not-yet-implemented seam in this batch).
  `Fixtures.set_player_gold/3` independently sets the ACTUAL treasury
  balance the tribute payment moves gold out of/into — see
  `criterion_7676`'s own moduledoc for why the two are kept separate.

  ## Story 909 postscript: the vassal goes offline too

  Once `BrokenOaths.Game.Bank` shipped, this SAME `set_player_gold_income/3`
  seam grew a second reader: a LOGGED-IN player's own declared income
  now genuinely credits their treasury each boundary (story 909,
  criterion 7682), not just this criterion's own tribute skim. Left
  connected, `a_freshly_subjugated_vassal/1`'s own vassal would net
  `income - tribute` instead of this criterion's own `-tribute` alone —
  a real behavior change, not a bug. `go_offline(context.other_play_live)`
  keeps this criterion's own worked example (12 × 25% = 3, moving from
  the vassal's treasury to the lord's, nothing more) exactly what it
  always was: income the OFFLINE vassal accrues into their own Gold
  Bank instead (untouched by `Fixtures.gold/2`), not their treasury.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a vassal earning 12 gold/turn at 25% pays 3 gold tribute" do
    scenario "a turn boundary moves exactly 3 gold from the vassal's treasury to the lord's" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my vassal earns 12 gold/turn, and I still tax them at the default 25%", context do
        context = a_freshly_subjugated_vassal(context)

        go_offline(context.other_play_live)

        :ok = Fixtures.set_player_gold(context.world, context.other_user, 100)
        :ok = Fixtures.set_player_gold_income(context.world, context.other_user, 12)

        vassal_gold0 = Fixtures.gold(context.world, context.other_user)
        lord_gold0 = Fixtures.gold(context.world, context.user)

        context
        |> Map.put(:vassal_gold0, vassal_gold0)
        |> Map.put(:lord_gold0, lord_gold0)
        |> then(&{:ok, &1})
      end

      when_ "a turn boundary passes", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "exactly 3 gold moved from the vassal's own treasury to the lord's", context do
        assert context.my_lord.tile_id == context.other_city.tile_id

        vassal_gold_now = Fixtures.gold(context.world, context.other_user)
        lord_gold_now = Fixtures.gold(context.world, context.user)

        assert vassal_gold_now == context.vassal_gold0 - 3
        assert lord_gold_now == context.lord_gold0 + 3
        {:ok, context}
      end
    end
  end
end
