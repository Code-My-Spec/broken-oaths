defmodule BrokenOathsSpex.Story908.Criterion7675Spex do
  @moduledoc """
  Story 908 — Tribute Payments
  Criterion 7675 — changing a vassal's tribute rate takes effect "next
  turn" ("New rate takes effect next turn. Vassal notified of change" —
  `.code_my_spec/stories/more_stories.md` §7.3): raising the rate from
  the default 25% to 50% and then letting a boundary pass must skim the
  NEW rate, not the old one.

  Reuses `criterion_7673`'s own `"set_tribute_rate"` judgment call and
  `criterion_7674`'s own reconciled-against-story-912 approach (see
  that spec's own moduledoc for the full rationale: `SharedGivens.
  grow_city_to/5` to a deterministic size-4 income, `SharedGivens.
  real_gold_income/2` to read it, `go_offline/1` so the vassal's own
  income never lands in their treasury directly, and the lord's own
  income folded into their expected gain since they stay connected).

  Growing to size 4 (`base_gold(4) = 3`, deterministic regardless of
  terrain) guarantees `round(income * 0.25)` and `round(income * 0.50)`
  are DIFFERENT numbers (`round(3 * 0.25) = 1`, `round(3 * 0.50) = 2` —
  and only grows further apart at a higher real income), so this
  criterion's own "the NEW rate applies, not the old one" claim stays
  meaningful rather than vacuously true.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a raised rate is applied on the next turn's tribute", fail_on_error_logs: false do
    scenario "raising the rate to 50% before a turn boundary skims 50%, not the old 25%" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my vassal's captured city has grown to size 4, and I've just raised their rate to 50%",
             context do
        context = a_freshly_subjugated_vassal(context)

        grow_city_to(context.world, context.other_user, context.other_city.id, 4)
        go_offline(context.other_play_live)

        :ok = Fixtures.set_player_gold(context.world, context.other_user, 100)

        attempt_event(context.play_live, "set_tribute_rate", %{
          "vassal_user_id" => to_string(context.other_user.id),
          "rate" => "50"
        })

        {:ok, context}
      end

      when_ "the next turn boundary passes", context do
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

      then_ "the NEW 50% rate was skimmed — not the old rate's smaller cut", context do
        assert context.my_lord.tile_id == context.other_city.tile_id
        assert context.vassal_income >= 3

        expected_at_new_rate = round(context.vassal_income * 0.50)
        expected_at_old_rate = round(context.vassal_income * 0.25)
        assert expected_at_new_rate != expected_at_old_rate

        vassal_gold_now = Fixtures.gold(context.world, context.other_user)
        lord_gold_now = Fixtures.gold(context.world, context.user)

        assert vassal_gold_now == context.vassal_gold0 - expected_at_new_rate
        assert lord_gold_now == context.lord_gold0 + expected_at_new_rate + context.lord_income
        {:ok, context}
      end
    end
  end
end
