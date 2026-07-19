defmodule BrokenOathsSpex.Story914.Criterion7730Spex do
  @moduledoc """
  Story 914 — Protection Pact
  Criterion 7730 — "Repeated honored protection makes vassalage a
  net-positive": across many turns and three separately honored
  protection calls, Wes's Oath Strain "sits low... because protection
  has been reliably delivered," and Wes "gains defense he could not
  muster alone" — the design doc's own retention thesis
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Why this is
  rare (research finding)": "vassalage must not *always* be negative").

  ## Judgment call: avoiding a vacuous pass

  A naive reading — "just check Wes's final Oath Strain is a small
  number" — would pass TODAY for the wrong reason: no story in this
  batch (913's accrual, 914's honored-easing) is implemented yet, so
  `oath_strain` never moves from its schema default (0) regardless of
  whether protection was ever delivered. That would be exactly the
  self-fulfilling-pass anti-pattern this task's own brief warns
  against ("do not soften the assertion to match current behavior").

  This spec instead builds a genuine COUNTERFACTUAL: Wes first takes
  ONE real, already-shipped refused-call-to-arms spike (`Tribute.
  spike_oath_strain/1`, +15, the same real mechanic `Criterion7722Spex`/
  `Criterion7728Spex` already use as a deterministic baseline-setter),
  establishing that his strain CAN and DOES rise for a real reason.
  THEN Lord Mira reliably honors three separate, real sieges. The
  criterion's own causal claim — repeated honored protection EASES
  strain — is only true if Wes's FINAL reading ends up LOWER than that
  post-refusal baseline. Today, since nothing eases strain, the final
  reading EQUALS the baseline (never drops below it) — a genuine,
  non-vacuous RED. Once 914 lands for real, three honored defenses
  should pull it back down.

  ## Judgment call: the invented "protection-honored-count" ledger

  New sibling to `Criterion7727Spex`'s own `protection-call`/
  `protection-window` family: `[data-test="vassal-row-<id>"]
  [data-test="protection-honored-count"]` — a running integer count of
  protection calls HONORED for that vassal, mirroring the innermost-
  span convention every other counter in this codebase already uses.
  This is the most direct, literal encoding of "repeated... three
  protection calls" the gherkin's own text asks for, distinct from (and
  additional to) the Oath Strain easing claim above.

  ## Judgment call: "defense he could not muster alone"

  No numeric criterion attaches to this clause — it's the design
  doc's own THESIS, not a separate measurable rule. This spec treats it
  as satisfied by the same observable facts already asserted: Wes's
  city survives three real sieges (still his, on his own roster) and
  three calls are recorded as honored. No further invented metric.

  ## Setup efficiency note

  Each of the three siege rounds uses `Fixtures.spawn_unit/4` to place
  a fresh besieging warrior directly (no march needed — the besieger's
  own starting position doesn't matter, only that it lands adjacent to
  Wes's city) and `Fixtures.set_unit_hp/3` to guarantee Lord Mira's own
  follow-up strike is lethal, the same deterministic-kill idiom
  `Criterion7728Spex` already established. The besieging unit is
  defensively re-fetched before Mira's own strike in case the CITY's
  own counter-fire already killed it during its own attack — that still
  counts as the attacker having been driven off, so the round simply
  skips Mira's own swing in that case.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  defp vassal_strain(lord_live, vassal_user_id) do
    row_html =
      lord_live
      |> element("[data-test='vassal-row-#{vassal_user_id}']")
      |> render()

    [_, strain_text] = Regex.run(~r/data-test="vassal-oath-strain"[^>]*>(\d+)/, row_html)
    String.to_integer(strain_text)
  end

  spex "reliably honored protection makes vassalage a net-positive for the vassal",
    fail_on_error_logs: false do
    scenario "three separately honored sieges leave Wes's Oath Strain below what the plain refusal baseline alone would have left, and his lord's own record shows all three honored" do
      given_ "a world with room for three players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 1, frequency: 9}))}
      end

      given_(:registered_player)
      given_(:second_registered_player)
      given_(:third_registered_player)

      given_ "Wes is already Lord Mira's vassal", context do
        {:ok, a_freshly_subjugated_vassal(context)}
      end

      given_ "a rival player joins the world as the repeat besieger", context do
        {:ok, rival_join_live, _html} = live(context.third_conn, "/play")

        rival_join_live
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

      given_ "Wes has already refused one call to arms — a real, positive strain baseline unrelated to protection",
             context do
        attempt_event(context.play_live, "issue_levy", %{
          "vassal_user_id" => to_string(context.other_user.id),
          "target_user_id" => to_string(context.third_user.id),
          "share" => "0.5"
        })

        attempt_event(context.other_play_live, "refuse_levy", %{
          "lord_user_id" => to_string(context.user.id)
        })

        {:ok, lord_live, _html} = live(context.conn, "/play/#{context.world.id}")
        strain_baseline = vassal_strain(lord_live, context.other_user.id)

        assert strain_baseline > 0,
               "setup expected the real refusal spike to leave a positive baseline, got #{strain_baseline}"

        {:ok, Map.put(context, :strain_baseline, strain_baseline)}
      end

      when_ "Lord Mira reliably answers three separate protection calls for Wes, over three separate sieges",
            context do
        for _ <- 1..3 do
          warrior =
            Fixtures.spawn_unit(context.world, context.rival_player.id, :warrior, context.rival_target)

          attempt_event(context.rival_play_live, "attack", %{
            "unit_id" => to_string(warrior.id),
            "target_city_id" => to_string(context.other_city.id)
          })

          case for(u <- Fixtures.player_units(context.world, context.third_user), u.id == warrior.id, do: u) do
            [alive] ->
              Fixtures.set_unit_hp(context.world, alive.id, 1)
              Fixtures.recharge_unit(context.world, context.my_lord.id)

              attempt_event(context.play_live, "attack", %{
                "unit_id" => to_string(context.my_lord.id),
                "target_unit_id" => to_string(alive.id)
              })

            [] ->
              :ok
          end

          Fixtures.advance_turn(context.world)
        end

        {:ok, context}
      end

      then_ "Wes's Oath Strain ends up LOWER than the plain refusal baseline alone would have left it",
            context do
        {:ok, lord_live, _html} = live(context.conn, "/play/#{context.world.id}")
        strain_final = vassal_strain(lord_live, context.other_user.id)

        assert strain_final < context.strain_baseline,
               "three reliably honored Protection Pact calls should EASE Oath Strain below " <>
                 "the plain refusal-only baseline (#{context.strain_baseline}); " <>
                 "got #{strain_final}, no easing at all — vassalage isn't paying off"

        {:ok, context}
      end

      then_ "Mira's own record shows all three calls honored, and Wes's city is still his",
            context do
        {:ok, lord_live, _html} = live(context.conn, "/play/#{context.world.id}")

        assert has_element?(
                 lord_live,
                 "[data-test='vassal-row-#{context.other_user.id}'] [data-test='protection-honored-count']",
                 "3"
               ),
               "no \"protection-honored-count\" ledger showing 3 honored calls rendered for " <>
                 "Wes yet — ProtectionPact doesn't record honored calls"

        [still_his] =
          for c <- Fixtures.player_cities(context.world, context.other_user),
              c.id == context.other_city.id,
              do: c

        assert still_his.id == context.other_city.id,
               "Wes's city should have survived three reliably-defended sieges, still on his own roster"

        {:ok, context}
      end
    end
  end
end
