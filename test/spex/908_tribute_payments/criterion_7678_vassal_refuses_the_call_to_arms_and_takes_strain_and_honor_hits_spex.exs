defmodule BrokenOathsSpex.Story908.Criterion7678Spex do
  @moduledoc """
  Story 908 — Tribute Payments
  Criterion 7678 — the refusal branch of `criterion_7677`'s own call to
  arms: "Refusal spikes Oath Strain and dings the Honor ledger (a
  publicly-legible broken obligation). A refused call is first-class
  drama" (`.code_my_spec/knowledge/feudal_vassalage_design.md`, §C).

  See `criterion_7677`'s own moduledoc for the `BrokenOaths.Feudal.Levy`
  schema, the `"issue_levy"` judgment call, and why the war's target is
  a third, independently-joined player. This criterion refuses instead
  of answering: `"refuse_levy"`, `%{"lord_user_id" => ...}`.

  ## Oath Strain AND Honor — both halves of the pair now asserted

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

  QA issue c0ec53ed: this criterion's own text ALSO says "Honor hits,"
  but the shipped `refuse_levy` handler only ever spiked Oath Strain —
  Honor never moved, a gap this criterion's own moduledoc used to
  document rather than catch. `Tribute.apply_refusal_honor_penalty/1`
  closes it, and this spec now asserts the drop for real — reading the
  vassal's OWN `data-test="player-honor"` badge (story 910's
  `criterion_7696` precedent, `BrokenOaths.Game.honor/2`'s own board
  surface) before and after the refusal, the same before/after
  comparison that criterion already established for the steward
  sabotage penalty, never asserting an exact starting number or delta.
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

        # QA issue c0ec53ed — the vassal's own Honor reading BEFORE the
        # refusal, off their OWN board (`data-test="player-honor"`,
        # `criterion_7696`'s own precedent), to compare against after.
        honor_before_html = render(context.other_play_live)

        honor_before =
          Regex.run(~r/data-test="player-honor"[^>]*>(-?\d+)/, honor_before_html)

        {:ok, Map.put(context, :honor_before, honor_before)}
      end

      when_ "the vassal refuses the call", context do
        attempt_event(context.other_play_live, "refuse_levy", %{
          "lord_user_id" => to_string(context.user.id)
        })

        {:ok, context}
      end

      then_ "the levy reads refused, and the vassal's own Oath Strain is now positive, and their Honor dropped",
            context do
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

        # QA issue c0ec53ed — the paired Honor consequence: a fresh
        # mount of the VASSAL's own board (same "don't trust a stale
        # live socket's own timing" posture `criterion_7696` already
        # establishes) must now read a LOWER Honor than before refusing.
        {:ok, fresh_vassal_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        assert has_element?(fresh_vassal_live, "[data-test='player-honor']")

        honor_after_html = render(fresh_vassal_live)

        assert [_, honor_after_text] =
                 Regex.run(~r/data-test="player-honor"[^>]*>(-?\d+)/, honor_after_html)

        honor_after = String.to_integer(honor_after_text)

        assert context.honor_before != nil,
               "no \"player-honor\" element rendered BEFORE the refusal either — nothing to compare against"

        [_, honor_before_text] = context.honor_before
        honor_before = String.to_integer(honor_before_text)

        assert honor_after < honor_before

        {:ok, context}
      end
    end
  end
end
