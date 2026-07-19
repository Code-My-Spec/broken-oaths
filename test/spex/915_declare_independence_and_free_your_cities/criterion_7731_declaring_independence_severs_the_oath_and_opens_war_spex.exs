defmodule BrokenOathsSpex.Story915.Criterion7731Spex do
  @moduledoc """
  Story 915 — Declare Independence and Free Your Cities
  Criterion 7731 — the oath-severing half of declaring independence:
  "Rule: Clicking Declare Independence, after a confirming warning,
  immediately severs the Vassalage, stops tribute, and declares war
  with the former lord" (story 915's own gherkin). This criterion is
  the mechanical foundation every other 915 criterion builds on — the
  Vassalage ends, tribute stops moving, and a state of war begins,
  regardless of what happens to any occupied city (that's
  criteria 7732-7736's own subject).

  `BrokenOaths.Game.Rebellion` does not exist yet — nothing severs a
  Vassalage, stops tribute, or declares war today. This spec is
  expected to fail entirely on first run.

  ## New judgment calls (shared by every 915 criterion below)

  1. **The two-step confirm.** Mirrors story 902/903's own
     `"select_research"`/`"bronze_working_confirm"` two-step pattern
     for an irreversible choice (`BrokenOathsSpex.SharedGivens.
     player_reached_bronze_age/1`): `"declare_independence"` raises the
     confirming warning (does not commit anything), and
     `"confirm_declare_independence"` is what actually severs the oath.
     Both take `%{"lord_user_id" => ...}` — the same param-naming
     convention story 908's own `"answer_levy"`/`"refuse_levy"` and
     story 913's own `"mark_pact_unhonored"` already use for "which of
     my (at most one) lord relationships." Both driven through
     `attempt_event/3` since no `handle_event/3` clause exists for
     either yet.
  2. **The "at war" badge.** No war-state UI exists anywhere in this
     codebase yet. This spec's own judgment call:
     `data-test="at-war-with"` on `GameLive.Play`, rendering the OTHER
     party's own `user.email` — present on BOTH the former vassal's own
     view and the former lord's own view once a Rebellion is active,
     the same "identify a player by email" convention story 899's
     `known-player-<id>` and story 907's `vassal-status`/`vassal-row`
     already established.
  3. **Proving tribute stopped, without inventing a dedicated "stopped"
     badge.** This spec reuses story 908/912's own reconciled
     real-economy proof idiom
     (`BrokenOathsSpex.Story908.Criterion7674Spex`): read the former
     lord's own real per-turn city income (`SharedGivens.
     real_gold_income/2`) and treasury (`Fixtures.gold/2`) immediately
     before a turn boundary, advance it, and assert the lord's own gold
     gain is EXACTLY her own real income — no tribute component on top.
     If tribute were still flowing, this assertion would fail by
     exactly the tribute amount. The mirror check on the vassal's own
     side (his gold gain is exactly his own full income, nothing
     skimmed away) proves the same fact from the other side.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "declaring independence severs the oath and opens war", fail_on_error_logs: false do
    scenario "confirming the warning severs the Vassalage, stops tribute, and declares war" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "Wes is a vassal of Lord Mira paying 40% tribute", context do
        context = a_freshly_subjugated_vassal(context)

        attempt_event(context.play_live, "set_tribute_rate", %{
          "vassal_user_id" => to_string(context.other_user.id),
          "rate" => "40"
        })

        {:ok, context}
      end

      when_ "Wes clicks Declare Independence and confirms the warning", context do
        attempt_event(context.other_play_live, "declare_independence", %{
          "lord_user_id" => to_string(context.user.id)
        })

        attempt_event(context.other_play_live, "confirm_declare_independence", %{
          "lord_user_id" => to_string(context.user.id)
        })

        {:ok, context}
      end

      then_ "no further tribute transfers from Wes to Mira on the next turn boundary", context do
        lord_income = real_gold_income(context.world, context.user)
        lord_gold0 = Fixtures.gold(context.world, context.user)
        vassal_income = real_gold_income(context.world, context.other_user)
        vassal_gold0 = Fixtures.gold(context.world, context.other_user)

        Fixtures.advance_turn(context.world)

        assert Fixtures.gold(context.world, context.user) == lord_gold0 + lord_income,
               "Mira's own gold gain should be exactly her own real income, with no tribute on top"

        assert Fixtures.gold(context.world, context.other_user) == vassal_gold0 + vassal_income,
               "Wes should keep his own full income now — nothing skimmed to Mira"

        {:ok, context}
      end

      then_ "a state of war exists between Wes and Mira, visible to both", context do
        {:ok, fresh_vassal_live, _html} = live(context.other_conn, "/play/#{context.world.id}")
        {:ok, fresh_lord_live, _html} = live(context.conn, "/play/#{context.world.id}")

        assert has_element?(fresh_vassal_live, "[data-test='at-war-with']", context.user.email)
        assert has_element?(fresh_lord_live, "[data-test='at-war-with']", context.other_user.email)

        refute has_element?(fresh_vassal_live, "[data-test='vassal-status']", context.user.email),
               "Wes should no longer read as sworn to Mira — the oath is severed"

        {:ok, context}
      end
    end
  end
end
