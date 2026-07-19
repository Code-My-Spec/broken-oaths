defmodule BrokenOathsSpex.Story914.Criterion7727Spex do
  @moduledoc """
  Story 914 — Protection Pact
  Criterion 7727 — "When a vassal comes under attack, a protection call
  is raised that the LORD can see, with a response window that counts
  down"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`). Builds
  directly on `Criterion7726Spex`'s own trigger (a real siege on the
  vassal's city) — this criterion is about VISIBILITY: both sides of
  the bond see the same call, and the lord additionally sees a
  countdown that genuinely ticks down as turns pass.

  ## Judgment call: the invented selectors

  Extends `Criterion7726Spex`'s own `protection-call` family:

    * `[data-test="vassal-row-<vassal_user_id>"] [data-test="protection-call"]`
      — the lord's own call, already established by 7726.
    * `[data-test="vassal-row-<vassal_user_id>"] [data-test="protection-window"]`
      — NEW: a plain integer countdown nested inside the same row,
      mirroring the `vassal-oath-strain` innermost-span convention
      story 908 already set (a spec's own regex needs the digit
      immediately after this span's own closing tag).
    * `[data-test="my-protection-call"]` — NEW: the VASSAL's own view,
      a sibling to the existing `vassal-status`/`my-tribute-rate`/
      `my-oath-strain` cluster on their own `GameLive.Play` (only
      rendered `:if={{@vassal_status}}`, same gating those already use).

  ## Judgment call: the quoted UI copy is flavor, not a locked contract

  The gherkin quotes illustrative copy verbatim ("Wes is under attack —
  respond within N turns" / "protection requested from Mira"). Unlike
  the numeric deltas in later criteria (explicitly marked
  "illustratively" in the design doc's own "Round-5 decisions: exact
  numbers are a balancing pass, not a blocker"), nothing marks this
  COPY as non-binding — but our fixture-generated players are never
  literally named "Wes"/"Mira" (`Fixtures.user_fixture/1` mints random
  emails), so asserting the exact quoted sentence verbatim is
  impossible without inventing a name-injection contract nobody has
  designed. This spec asserts the SUBSTANCE instead: the lord's own
  call names the fact of being under attack and a numeric response
  window; the vassal's own call literally contains "protection
  requested" (the one phrase from the quote that doesn't depend on
  either player's name). FLAGGED as a judgment call, not a fabrication
  of new criteria.

  ## Judgment call: the "3-turn window" default

  7727's own intro text marks "illustratively 3 turns" — but
  `Criterion7728Spex`/`Criterion7729Spex` both state "a protection call
  on Wes with a 3-turn window" as a plain GIVEN fact, not hedged. This
  spec treats 3 as the working default every sibling criterion in this
  story assumes, without hardcoding it into an assertion here — only
  the RELATIONAL fact ("counts down by exactly one turn per boundary")
  is asserted, so this spec survives a future tuning pass that picks a
  different exact number.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a protection call is visible to both the lord and the vassal, with a live countdown",
    fail_on_error_logs: false do
    scenario "Lord Mira sees the call and its countdown; Wes sees his own protection-requested notice" do
      given_ "a world with room for three players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 1, frequency: 9}))}
      end

      given_(:registered_player)
      given_(:second_registered_player)
      given_(:third_registered_player)

      given_ "Wes is already Lord Mira's vassal", context do
        {:ok, a_freshly_subjugated_vassal(context)}
      end

      given_ "a rival player stands ready to march on Wes's city", context do
        {:ok, third_join_live, _html} = live(context.third_conn, "/play")

        third_join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, rival_play_live, _html} = live(context.third_conn, "/play/#{context.world.id}")
        {:ok, rival_player} = Fixtures.join_world(context.world, context.third_user)

        rival_target =
          adjacent_land_tile(context.world, context.other_city.tile_id, [context.my_lord.tile_id])

        {:ok,
         context
         |> Map.put(:rival_play_live, rival_play_live)
         |> Map.put(:rival_player, rival_player)
         |> Map.put(:rival_target, rival_target)}
      end

      when_ "the rival besieges Wes's city and the protection call is raised", context do
        warrior =
          Fixtures.spawn_unit(context.world, context.rival_player.id, :warrior, context.rival_target)

        attempt_event(context.rival_play_live, "attack", %{
          "unit_id" => to_string(warrior.id),
          "target_city_id" => to_string(context.other_city.id)
        })

        {:ok, context}
      end

      then_ "Lord Mira sees a call naming Wes as under attack, with a numeric response window",
            context do
        {:ok, lord_live, _html} = live(context.conn, "/play/#{context.world.id}")

        assert has_element?(
                 lord_live,
                 "[data-test='vassal-row-#{context.other_user.id}'] [data-test='protection-call']",
                 "under attack"
               ),
               "no \"protection-call\" naming Wes as under attack rendered on Lord Mira's own " <>
                 "board — ProtectionPact doesn't exist"

        assert has_element?(
                 lord_live,
                 "[data-test='vassal-row-#{context.other_user.id}'] [data-test='protection-window']"
               ),
               "no numeric \"protection-window\" countdown rendered alongside the call"

        {:ok, context}
      end

      then_ "Wes sees his own protection-requested notice", context do
        {:ok, vassal_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        assert has_element?(
                 vassal_live,
                 "[data-test='my-protection-call']",
                 "protection requested"
               ),
               "no \"my-protection-call\" notice rendered on Wes's own board — " <>
                 "ProtectionPact doesn't exist"

        {:ok, context}
      end

      then_ "the response window counts down by exactly one turn as a boundary passes", context do
        {:ok, lord_live, _html} = live(context.conn, "/play/#{context.world.id}")

        assert has_element?(
                 lord_live,
                 "[data-test='vassal-row-#{context.other_user.id}'] [data-test='protection-window']"
               ),
               "no \"protection-window\" countdown rendered yet — ProtectionPact doesn't exist"

        html_before = render(lord_live)

        [_, window_before_text] =
          Regex.run(~r/data-test="protection-window"[^>]*>(\d+)/, html_before)

        window_before = String.to_integer(window_before_text)

        Fixtures.advance_turn(context.world)

        {:ok, lord_live2, _html} = live(context.conn, "/play/#{context.world.id}")
        html_after = render(lord_live2)

        [_, window_after_text] =
          Regex.run(~r/data-test="protection-window"[^>]*>(\d+)/, html_after)

        window_after = String.to_integer(window_after_text)

        assert window_after == window_before - 1,
               "expected the protection window to count down by exactly one turn " <>
                 "(#{window_before} -> #{window_before - 1}); got #{window_after}"

        {:ok, context}
      end
    end
  end
end
