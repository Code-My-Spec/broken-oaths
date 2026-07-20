defmodule BrokenOathsSpex.Story913.Criterion7720Spex do
  @moduledoc """
  Story 913 — Oath Strain and Liberty Pressure
  Criterion 7720 — "Oath Strain is a per-relationship gauge (0-100) on
  the Vassalage schema, visible to BOTH the lord and the vassal"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Rebellion
  batch — LOCKED model").

  ## Judgment call: substituting the illustrative "42"

  The gherkin's own precondition ("an Oath Strain of 42") has no real
  production path today — `BrokenOaths.Feudal.OathStrain` (this
  criterion's own component) doesn't exist yet, so nothing accrues or
  decays Oath Strain over time or from lord/vassal actions except one
  thing that IS already real and shipped: story 908's refused-call-to-
  arms spike (`BrokenOaths.Feudal.Tribute.spike_oath_strain/1`, +15 per
  refusal, clamped at 100). Rather than fabricate a new test-only
  setter for an arbitrary starting figure (a seam this story doesn't
  own and the task brief doesn't sanction inventing), this given drives
  that REAL consequence repeatedly (seven refusals, 7×15=105 raw) so
  the observed figure is simultaneously non-zero, shared, deterministic,
  AND exercises the 0-100 clamp for real — the scenario's own subject,
  "both lord and vassal see the SAME gauge," survives this substitution
  intact; only the illustrative literal "42" does not.

  ## New judgment call: the vassal's own oath-strain badge

  Story 908's own `criterion_7678` introduced `data-test=
  "vassal-oath-strain"` on the LORD's own `vassal-row` — but
  deliberately never gave the VASSAL's own view (the `vassal-status`
  badge cluster on their own `GameLive.Play`, alongside `my-tribute-
  rate`/`levy-status`) a matching element. THIS criterion is the first
  that needs the vassal to see their OWN strain too ("visible to BOTH
  the lord and the vassal") — this spec asserts a new sibling
  `data-test="my-oath-strain"`. It does not exist yet; that gap is the
  RED signal this file is for.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "both the lord and the vassal see the same Oath Strain gauge for their bond",
    fail_on_error_logs: false do
    scenario "a shared, clamped reading is visible on both the lord's and the vassal's own views" do
      given_ "a world with room for three players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 1, frequency: 9}))}
      end

      given_(:registered_player)
      given_(:second_registered_player)
      given_(:third_registered_player)

      given_ "my rival is already my vassal", context do
        {:ok, a_freshly_subjugated_vassal(context)}
      end

      given_ "a third player exists as a legal levy target", context do
        {:ok, third_join_live, _html} = live(context.third_conn, "/play")

        third_join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, context}
      end

      given_ "the vassal has refused several calls to arms, driving their real Oath Strain to the clamp ceiling",
             context do
        for _ <- 1..7 do
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

      when_ "Wes opens his oath panel and Mira opens her Vassals panel", context do
        {:ok, lord_live, _html} = live(context.conn, "/play/#{context.world.id}")
        {:ok, vassal_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        {:ok,
         context
         |> Map.put(:lord_live, lord_live)
         |> Map.put(:vassal_live, vassal_live)}
      end

      then_ "both see the same gauge reading, clamped to the 0-100 range", context do
        assert has_element?(
                 context.lord_live,
                 "[data-test='vassal-row-#{context.other_user.id}'] [data-test='vassal-oath-strain']"
               )

        assert has_element?(context.vassal_live, "[data-test='my-oath-strain']")

        lord_html = render(context.lord_live)

        [_, lord_strain_text] =
          Regex.run(~r/data-test="vassal-oath-strain"[^>]*>(\d+)/, lord_html)

        vassal_html = render(context.vassal_live)

        [_, vassal_strain_text] =
          Regex.run(~r/data-test="my-oath-strain"[^>]*>(\d+)/, vassal_html)

        lord_strain = String.to_integer(lord_strain_text)
        vassal_strain = String.to_integer(vassal_strain_text)

        assert lord_strain == vassal_strain,
               "lord read #{lord_strain}, vassal read #{vassal_strain} — same bond, same gauge"

        assert lord_strain >= 0 and lord_strain <= 100

        assert lord_strain == 100,
               "seven 15-point refusal spikes (105 raw) should clamp at the 100 ceiling, got #{lord_strain}"

        {:ok, context}
      end
    end
  end
end
