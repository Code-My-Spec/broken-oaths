defmodule BrokenOathsSpex.Story913.Criterion7721Spex do
  @moduledoc """
  Story 913 — Oath Strain and Liberty Pressure
  Criterion 7721 — "Oath Strain rises from extraction and neglect: a
  high tribute rate... slow and sticky — it moves over many turns, not
  in one tick" (`.code_my_spec/knowledge/feudal_vassalage_design.md`).
  No `BrokenOaths.Game.OathStrain` accrual engine exists yet, so this
  scenario is expected to fail: the vassal's own real tribute rate
  (`BrokenOaths.Game.Tribute.set_rate_changeset/2`, already shipped by
  story 908) is raised for real, and REAL turn boundaries
  (`Fixtures.advance_turn/1`) are advanced for real, but nothing today
  reads that rate into an Oath Strain delta.

  ## Judgment call: reaching a real "30" starting figure

  Same substitution rationale as `criterion_7720`'s own moduledoc: the
  gherkin's "current Oath Strain is 30" precondition is reached via two
  real, already-shipped refused-call-to-arms spikes (`Tribute.
  spike_oath_strain/1`, +15 each) — 2×15 happens to land exactly on the
  gherkin's own illustrative "30," so no substitution judgment call is
  even needed for the STARTING figure here (only the eventual "drifts
  further upward" delta is left unconstrained, since the accrual rate
  itself is explicitly a Three Amigos open question — "the exact
  accrual/decay rates per driver... is a balancing pass, not a
  blocker").

  ## New judgment call: "the gauge shows the rate as the driving contributor"

  The scenario's own second assertion needs a tooltip/breakdown surface
  the Three Amigos notes flag as still open ("how the gauge is
  surfaced... tooltip breakdown of drivers") but which the scenario
  text itself locks in as a requirement. This spec asserts a new
  `data-test="oath-strain-drivers"` sibling of `vassal-oath-strain` on
  the lord's own `vassal-row`, containing the word "tribute" — the
  narrowest new surface that satisfies the scenario's own words without
  inventing the breakdown's full visual design.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  defp read_strain(conn, world) do
    {:ok, live, _html} = live(conn, "/play/#{world.id}")
    html = render(live)
    [_, strain_text] = Regex.run(~r/data-test="vassal-oath-strain"[^>]*>(\d+)/, html)
    String.to_integer(strain_text)
  end

  spex "a high tribute rate drifts a vassal's Oath Strain upward over many turns",
    fail_on_error_logs: false do
    scenario "an unchanged 50% rate, well above the 25% default, pushes strain higher over hours of turns" do
      given_ "a world with room for three players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 1, frequency: 9}))}
      end

      given_(:registered_player)
      given_(:second_registered_player)
      given_(:third_registered_player)

      given_ "my rival is already my vassal, at the default 25% rate", context do
        {:ok, a_freshly_subjugated_vassal(context)}
      end

      given_ "a third player exists as a legal levy target", context do
        {:ok, third_join_live, _html} = live(context.third_conn, "/play")

        third_join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, context}
      end

      given_ "I raise their tribute rate to 50%, well above the 25% default, with no offsetting lord obligations",
             context do
        attempt_event(context.play_live, "set_tribute_rate", %{
          "vassal_user_id" => to_string(context.other_user.id),
          "rate" => "50"
        })

        {:ok, context}
      end

      given_ "their current Oath Strain is 30, from two earlier refused calls to arms",
             context do
        for _ <- 1..2 do
          attempt_event(context.play_live, "issue_levy", %{
            "vassal_user_id" => to_string(context.other_user.id),
            "target_user_id" => to_string(context.third_user.id),
            "share" => "0.5"
          })

          attempt_event(context.other_play_live, "refuse_levy", %{
            "lord_user_id" => to_string(context.user.id)
          })
        end

        30 = read_strain(context.conn, context.world)

        {:ok, Map.put(context, :strain_before, 30)}
      end

      when_ "several hours of turns pass with the 50% rate unchanged", context do
        for _ <- 1..40, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the vassal's Oath Strain has drifted upward past its 30 starting point", context do
        strain_after = read_strain(context.conn, context.world)

        assert strain_after > context.strain_before,
               "a 50% rate held across 40 turns should have drifted Oath Strain above its starting " <>
                 "#{context.strain_before}, got #{strain_after}"

        {:ok, context}
      end

      then_ "the gauge names the tribute rate as the driving contributor", context do
        {:ok, lord_live, _html} = live(context.conn, "/play/#{context.world.id}")

        assert has_element?(
                 lord_live,
                 "[data-test='vassal-row-#{context.other_user.id}'] [data-test='oath-strain-drivers']"
               )

        drivers_html = render(lord_live)
        assert drivers_html =~ "tribute"

        {:ok, context}
      end
    end
  end
end
