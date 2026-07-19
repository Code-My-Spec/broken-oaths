defmodule BrokenOathsSpex.Story915.Criterion7734Spex do
  @moduledoc """
  Story 915 — Declare Independence and Free Your Cities
  Criterion 7734 — the full tyrant scenario: a dishonorable, heavy-
  taxing lord loses most of the rebel's cities AND faces a real,
  strain-sized temporary army, with the results banner naming the
  outcome — "Mira's dishonor and heavy tribute make most of the five
  cities rise back to Wes... a temporary rebellion army sized by Wes's
  strain-80 grievance spawns... those units are flagged temporary...
  a results banner reads 'Your cities rise — a rebellion rallies to
  your cause!'" (story 915's own gherkin).

  ## Judgment call: substituting "5 occupied cities" / Oath Strain "80"

  Same substitution as `criterion_7732`: reuses
  `BrokenOathsSpex.SharedGivens.a_freshly_subjugated_vassal_with_two_
  cities/1` (TWO real cities, not five — see that helper's own
  moduledoc) and six real refused-levy spikes for "high grievance"
  rather than the illustrative literal "80".

  ## Judgment call: reaching "Mira's low Honor" for real

  Same substitution as `criterion_7732`/`criterion_7733`: drives the
  one real, already-shipped dishonorable act
  (`SharedGivens.lord_executes_a_throwaway_garrison/1`) against a
  THROWAWAY third player.

  ## Isolating the temporary army from any defecting garrison

  `a_freshly_subjugated_vassal_with_two_cities/1` deliberately leaves
  NEITHER captured city garrisoned by the lord's own Lord unit (it
  marches off to a neutral tile as that helper's own last step) — so
  every unit that appears on Wes's own roster for the FIRST time after
  declaring independence is attributable to the temporary rebellion
  army itself, not a defecting garrison (`criterion_7733`'s own
  separate subject).

  ## New judgment calls this criterion establishes

  1. **Reading the "flagged temporary" fact.** `Fixtures.player_units/2`
     is the already-sanctioned board-state read (see
     `BrokenOathsSpex.Story906.Criterion7662Spex`); this spec asserts
     directly on a `:temporary` key in the newly-spawned units' own
     returned maps — the natural place for the not-yet-built spawner to
     carry that flag, observed through the SAME bridge every other
     906-913 spec already reads units through, not a new schema read.
  2. **The results banner.** A pushed `"game:rebellion"` event on the
     rebel's own session carrying a `:message` string — mirrors story
     907's own `"game:vassalized"`/`"game:new_vassal"` push-notification
     pattern (`BrokenOathsSpex.Story907.Criterion7670Spex`). Unlike
     those, the criterion's own gherkin quotes the banner text
     verbatim, so this spec asserts it verbatim rather than a loose
     substring match.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a tyrant's cities rise and a grievance army rallies", fail_on_error_logs: false do
    scenario "declaring independence against a dishonorable, heavy-taxing lord rises both cities, spawns a temporary army, and shows the results banner" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)
      given_(:third_registered_player)

      given_ "Wes has two occupied cities under Lord Mira, taxed at 40%", context do
        context = a_freshly_subjugated_vassal_with_two_cities(context)

        attempt_event(context.play_live, "set_tribute_rate", %{
          "vassal_user_id" => to_string(context.other_user.id),
          "rate" => "40"
        })

        {:ok, context}
      end

      given_ "Mira has low Honor from executing a captured garrison elsewhere", context do
        {:ok, lord_executes_a_throwaway_garrison(context)}
      end

      given_ "Wes's Oath Strain is high, driven by repeated refused calls to arms", context do
        for _ <- 1..6 do
          attempt_event(context.play_live, "issue_levy", %{
            "vassal_user_id" => to_string(context.other_user.id),
            "target_user_id" => to_string(context.third_user.id),
            "share" => "0.5"
          })

          attempt_event(context.other_play_live, "refuse_levy", %{
            "lord_user_id" => to_string(context.user.id)
          })
        end

        {:ok, context}
      end

      when_ "Wes declares independence", context do
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

      then_ "a results banner reads \"Your cities rise — a rebellion rallies to your cause!\"",
            context do
        assert_push_event(context.other_play_live, "game:rebellion", %{message: message}, 500)

        assert message == "Your cities rise — a rebellion rallies to your cause!"

        {:ok, context}
      end

      then_ "Mira's dishonor and heavy tribute make both of Wes's occupied cities rise back to him",
            context do
        {:ok, fresh_vassal_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        for city <- [context.other_city, context.second_city] do
          render_hook(fresh_vassal_live, "select_city", %{"city_id" => to_string(city.id)})

          refute has_element?(fresh_vassal_live, "[data-test='city-status']"),
                 "city #{city.id} should have risen and no longer render an occupied badge"
        end

        {:ok, context}
      end

      then_ "a temporary rebellion army sized by Wes's strain grievance spawns to fight the war",
            context do
        new_units =
          context.world
          |> Fixtures.player_units(context.other_user)
          |> Enum.reject(&MapSet.member?(context.baseline_unit_ids, &1.id))

        assert new_units != [],
               "declaring independence against a dishonorable, high-grievance lord should spawn a real temporary army"

        {:ok, Map.put(context, :new_units, new_units)}
      end

      then_ "those units are flagged temporary and will disband once the war is won or after the set number of turns",
            context do
        assert Enum.all?(context.new_units, &(Map.get(&1, :temporary) == true)),
               "every newly-spawned rebellion unit should be flagged temporary — got #{inspect(context.new_units)}"

        {:ok, context}
      end
    end
  end
end
