defmodule BrokenOathsSpex.Story913.Criterion7722Spex do
  @moduledoc """
  Story 913 — Oath Strain and Liberty Pressure
  Criterion 7722 — "a broken Protection Pact (914)... a large spike...
  Refusal spikes Oath Strain" (`.code_my_spec/knowledge/
  feudal_vassalage_design.md`). 913's own story description says it
  plainly: "Depends on... Protection Pact (914)" — and 914 hasn't been
  built or speced yet: no schema, no protection window, no attack-
  response tracking exists anywhere in this codebase.

  ## Judgment call: reaching a real "45" starting figure

  Same substitution as `criterion_7720`/`criterion_7721`: three real,
  already-shipped refused-call-to-arms spikes (`BrokenOaths.Game.
  Tribute.spike_oath_strain/1`, +15 each) land exactly on the gherkin's
  own illustrative "45" — no fabricated setter needed for the starting
  figure.

  ## Invented surface: "the pact is marked unhonored"

  Rather than skip this criterion or invent 914's own design wholesale,
  this spec adds the narrowest possible seam a future 914 implementation
  would plausibly expose: a `"mark_pact_unhonored"` hook fired on the
  VASSAL's own connection (they're the one whose protection lapsed),
  driven through `attempt_event/3` since no `handle_event/3` clause
  exists for it yet — the same "invent the event name, trap the crash"
  move story 908's own `criterion_7673` made for `"set_tribute_rate"`
  before ITS handler existed. Today this is a pure no-op (RED): no
  spike occurs, so both assertions below are expected to fail.

  ## Encoding "large spike" vs. "smaller rise" without the illustrative numbers

  The scenario's own numbers ("illustratively +25, to 70" / "smaller
  rise, illustratively +10") are explicitly marked illustrative — not a
  locked contract (design doc: "exact numbers are a balancing pass, not
  a blocker"). What IS locked is the *relationship*: an unhonored pact
  must spike strain by MORE than a plain refused levy does. This spec
  asserts that relationship directly — `pact_delta > refusal_delta` —
  rather than hardcoding either illustrative figure.
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

  spex "an unhonored Protection Pact spikes Oath Strain by more than a mere refused levy would",
    fail_on_error_logs: false do
    scenario "marking the pact unhonored produces a large one-time spike, bigger than a plain refusal's own rise" do
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

      given_ "Wes is under attack and his lord fails to respond within the protection window — his Oath Strain is 45",
             context do
        for _ <- 1..3 do
          attempt_event(context.play_live, "issue_levy", %{
            "vassal_user_id" => to_string(context.other_user.id),
            "target_user_id" => to_string(context.third_user.id),
            "share" => "0.5"
          })

          attempt_event(context.other_play_live, "refuse_levy", %{
            "lord_user_id" => to_string(context.user.id)
          })
        end

        45 = read_strain(context.conn, context.world)

        {:ok, Map.put(context, :strain_before_pact, 45)}
      end

      when_ "the pact is marked unhonored", context do
        attempt_event(context.other_play_live, "mark_pact_unhonored", %{
          "lord_user_id" => to_string(context.user.id)
        })

        strain_after_pact = read_strain(context.conn, context.world)

        {:ok, Map.put(context, :strain_after_pact, strain_after_pact)}
      end

      then_ "his Oath Strain takes a large one-time spike", context do
        pact_delta = context.strain_after_pact - context.strain_before_pact

        assert pact_delta >= 20,
               "an unhonored Protection Pact should spike Oath Strain by a large one-time amount " <>
                 "(illustratively +25); got a delta of #{pact_delta} (#{context.strain_before_pact} -> " <>
                 "#{context.strain_after_pact})"

        {:ok, context}
      end

      then_ "a refused call to arms applies a smaller rise than the pact spike did", context do
        attempt_event(context.play_live, "issue_levy", %{
          "vassal_user_id" => to_string(context.other_user.id),
          "target_user_id" => to_string(context.third_user.id),
          "share" => "0.5"
        })

        attempt_event(context.other_play_live, "refuse_levy", %{
          "lord_user_id" => to_string(context.user.id)
        })

        strain_after_refusal = read_strain(context.conn, context.world)

        pact_delta = context.strain_after_pact - context.strain_before_pact
        refusal_delta = strain_after_refusal - context.strain_after_pact

        assert refusal_delta < pact_delta,
               "a refused call to arms (delta #{refusal_delta}) should rise Oath Strain by LESS than " <>
                 "an unhonored Protection Pact did (delta #{pact_delta})"

        {:ok, context}
      end
    end
  end
end
