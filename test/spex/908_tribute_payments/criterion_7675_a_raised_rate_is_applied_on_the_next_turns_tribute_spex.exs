defmodule BrokenOathsSpex.Story908.Criterion7675Spex do
  @moduledoc """
  Story 908 — Tribute Payments
  Criterion 7675 — changing a vassal's tribute rate takes effect "next
  turn" ("New rate takes effect next turn. Vassal notified of change" —
  `.code_my_spec/stories/more_stories.md` §7.3): raising the rate from
  the default 25% to 50% and then letting a boundary pass must skim the
  NEW rate, not the old one.

  Reuses `criterion_7673`'s own `"set_tribute_rate"` judgment call and
  `criterion_7674`'s own gold-income-gap workaround
  (`Fixtures.set_player_gold_income/3`/`Fixtures.set_player_gold/3`) —
  see both moduledocs for the full rationale, including `criterion_7674`'s
  own "Story 909 postscript" for why the vassal goes offline
  (`go_offline(context.other_play_live)`) before their income is
  declared: a logged-in player's own declared income now genuinely
  credits their treasury too (story 909), which this criterion's own
  rate-math isn't about.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a raised rate is applied on the next turn's tribute", fail_on_error_logs: false do
    scenario "raising the rate to 50% before a turn boundary skims 50%, not the old 25%" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my vassal earns 20 gold/turn, and I've just raised their rate to 50%", context do
        context = a_freshly_subjugated_vassal(context)

        go_offline(context.other_play_live)

        :ok = Fixtures.set_player_gold(context.world, context.other_user, 100)
        :ok = Fixtures.set_player_gold_income(context.world, context.other_user, 20)

        attempt_event(context.play_live, "set_tribute_rate", %{
          "vassal_user_id" => to_string(context.other_user.id),
          "rate" => "50"
        })

        vassal_gold0 = Fixtures.gold(context.world, context.other_user)
        lord_gold0 = Fixtures.gold(context.world, context.user)

        context
        |> Map.put(:vassal_gold0, vassal_gold0)
        |> Map.put(:lord_gold0, lord_gold0)
        |> then(&{:ok, &1})
      end

      when_ "the next turn boundary passes", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the NEW 50% rate was skimmed — 10 gold, not the old rate's 5", context do
        assert context.my_lord.tile_id == context.other_city.tile_id

        vassal_gold_now = Fixtures.gold(context.world, context.other_user)
        lord_gold_now = Fixtures.gold(context.world, context.user)

        assert vassal_gold_now == context.vassal_gold0 - 10
        assert lord_gold_now == context.lord_gold0 + 10
        {:ok, context}
      end
    end
  end
end
