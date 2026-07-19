defmodule BrokenOathsSpex.Story908.Criterion7678Spex do
  @moduledoc """
  Story 908 — Tribute Payments
  Criterion 7678 — the refusal branch of `criterion_7677`'s own call to
  arms: "Refusal spikes Oath Strain and dings the Honor ledger (a
  publicly-legible broken obligation). A refused call is first-class
  drama" (`.code_my_spec/knowledge/feudal_vassalage_design.md`, §C).

  See `criterion_7677`'s own moduledoc for the `BrokenOaths.Game.Levy`
  schema, the `"issue_levy"` judgment call, and why the war's target is
  a third, independently-joined player. This criterion refuses instead
  of answering: `"refuse_levy"`, `%{"lord_user_id" => ...}`.

  ## Oath Strain: a new observable this criterion needs, Honor: none

  Story 907's own `criterion_7669` deliberately did NOT invent a
  surface for Oath Strain or Honor — nothing in this batch surfaced
  either yet. This criterion is the first that NEEDS Oath Strain to be
  observable (its own plain-language text is explicit: "takes strain"),
  so THIS spec's own judgment call introduces it: a sibling `data-test=
  "vassal-oath-strain"` badge on the lord's own `vassal-row` (alongside
  `vassal-tribute-rate`), reading a plain 0-100 integer — this spec
  only asserts it becomes POSITIVE after a refusal, not any exact
  number (the design doc's own "Round-5 decisions": "Exact numbers are
  a balancing pass, not a blocker").

  Honor still gets no surface here, matching
  `BrokenOathsSpex.Story906.Criterion7662Spex`'s own precedent (Honor
  has no UI anywhere in this batch, not even a schema field yet) — this
  spec's own RED signal is the Oath Strain spike and the levy's own
  `"refused"` status, not a Honor number nothing could observe.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a vassal refuses the call to arms and takes strain and Honor hits",
    fail_on_error_logs: false do
    scenario "refusing a levy marks it refused and spikes the vassal's own Oath Strain" do
      given_ "a world with room for three players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 1, frequency: 9}))}
      end

      given_(:registered_player)
      given_(:second_registered_player)
      given_(:third_registered_player)

      given_ "my vassal has a pending call to arms against a third player", context do
        context = a_freshly_subjugated_vassal(context)

        {:ok, third_join_live, _html} = live(context.third_conn, "/play")

        third_join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        attempt_event(context.play_live, "issue_levy", %{
          "vassal_user_id" => to_string(context.other_user.id),
          "target_user_id" => to_string(context.third_user.id),
          "share" => "0.5"
        })

        {:ok, context}
      end

      when_ "the vassal refuses the call", context do
        attempt_event(context.other_play_live, "refuse_levy", %{
          "lord_user_id" => to_string(context.user.id)
        })

        {:ok, context}
      end

      then_ "the levy reads refused, and the vassal's own Oath Strain is now positive", context do
        assert context.my_lord.tile_id == context.other_city.tile_id

        {:ok, fresh_lord_live, _html} = live(context.conn, "/play/#{context.world.id}")

        assert has_element?(
                 fresh_lord_live,
                 "[data-test='vassal-row-#{context.other_user.id}'] [data-test='levy-status']",
                 "refused"
               )

        assert has_element?(
                 fresh_lord_live,
                 "[data-test='vassal-row-#{context.other_user.id}'] [data-test='vassal-oath-strain']"
               )

        strain_html = render(fresh_lord_live)

        assert [_, strain_text] =
                 Regex.run(~r/data-test="vassal-oath-strain"[^>]*>(\d+)/, strain_html)

        assert String.to_integer(strain_text) > 0
        {:ok, context}
      end
    end
  end
end
