defmodule BrokenOathsSpex.Story915.Criterion7735Spex do
  @moduledoc """
  Story 915 — Declare Independence and Free Your Cities
  Criterion 7735 — the mirror case of `criterion_7734`: a just,
  light-handed lord keeps his subjects' loyalty and faces little to no
  uprising — "few or none of Ada's occupied cities rise... only a small
  temporary force, or none at all, spawns, because low grievance raises
  little... Wes remains at war with Ada with those cities still to be
  taken by force" (story 915's own gherkin).

  ## Judgment call: "high Honor" and "low grievance" are simply the
  untouched defaults

  Unlike `criterion_7732`/`criterion_7733`/`criterion_7734`, this
  scenario needs NO throwaway-garrison depression step at all: Honor
  only ever moves DOWNWARD in this codebase today (executing a fallen
  garrison is the sole real, shipped Honor delta —
  `BrokenOaths.Combat.Siege.apply_execute_honor_penalty/1` — releasing
  one is neutral, and nothing raises Honor). A lord who has captured
  nobody dishonorably (this scenario's own Mira-analog, "Ada," never
  executes any garrison) is therefore, by construction, already the
  MOST honorable state achievable — a fair, real-surface stand-in for
  "high Honor" without inventing a raise-Honor mechanic this batch
  never asked for. Likewise, Oath Strain starts at 0 and nothing in
  this given_ ever spikes it (no refused levy, no unhonored pact) —
  "low grievance" is the real, untouched, default state, the same
  substitution status `BrokenOathsSpex.Story913.Criterion7725Spex`'s own
  "max strain never auto-rebels" scenario relies on for its OWN
  baseline-strain assumption.

  A single occupied city is enough here (unlike `criterion_7734`'s own
  two) — this criterion's own claim is "few OR NONE rise," which a lone
  city already tests cleanly: it either stays loyal (the expected,
  documented outcome under a just lord) or it doesn't, and either way
  the war itself still opens.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a just lord's cities stay loyal and little rises", fail_on_error_logs: false do
    scenario "declaring independence against an honorable, light-taxing lord leaves the city loyal and raises little to no army" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "Wes is Ada's vassal, taxed lightly, and has given her no cause for grievance",
             context do
        context = a_freshly_subjugated_vassal(context)

        attempt_event(context.play_live, "set_tribute_rate", %{
          "vassal_user_id" => to_string(context.other_user.id),
          "rate" => "10"
        })

        {:ok, context}
      end

      when_ "the uprising resolves", context do
        baseline_ids =
          context.world
          |> Fixtures.player_units(context.other_user)
          |> MapSet.new(& &1.id)

        attempt_event(context.other_play_live, "declare_independence", %{
          "lord_user_id" => to_string(context.user.id)
        })

        attempt_event(context.other_play_live, "confirm_declare_independence", %{
          "lord_user_id" => to_string(context.user.id)
        })

        {:ok, Map.put(context, :baseline_unit_ids, baseline_ids)}
      end

      then_ "few or none of Ada's occupied cities rise — a just lord keeps his subjects' loyalty",
            context do
        {:ok, fresh_vassal_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        render_hook(fresh_vassal_live, "select_city", %{
          "city_id" => to_string(context.other_city.id)
        })

        assert has_element?(fresh_vassal_live, "[data-test='city-status']", "occupied"),
               "under a just, light-handed lord the vassal's own city should stay loyal, still occupied"

        {:ok, context}
      end

      then_ "only a small temporary force, or none at all, spawns — low grievance raises little",
            context do
        new_units =
          context.world
          |> Fixtures.player_units(context.other_user)
          |> Enum.reject(&MapSet.member?(context.baseline_unit_ids, &1.id))

        assert length(new_units) <= 1,
               "a just lord facing low grievance should raise at most a token force — spawned #{length(new_units)} units"

        {:ok, context}
      end

      then_ "Wes remains at war with Ada, with those cities still to be taken by force", context do
        {:ok, fresh_vassal_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        assert has_element?(fresh_vassal_live, "[data-test='at-war-with']", context.user.email)

        {:ok, context}
      end
    end
  end
end
