defmodule BrokenOathsSpex.Story914.Criterion7728Spex do
  @moduledoc """
  Story 914 — Protection Pact
  Criterion 7728 — "Honoring a protection call by relieving the vassal
  within the window LOWERS that vassal's Oath Strain and BUILDS the
  lord's Honor"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`). Builds on
  `Criterion7726Spex`'s trigger and `Criterion7727Spex`'s visibility —
  this criterion is the FIRST of the two resolution branches: the lord
  actually acts, in time, and both consequences land.

  ## No new invented event — resolution is an automatic engine reaction

  Unlike story 913's own `mark_pact_unhonored` (a deliberately narrow,
  invented seam for the BROKEN branch only, before this story existed
  to own the real thing), the HONORED branch needs no invented
  player-facing event at all: "Lord Mira's army defeats or drives off
  the attacker" is exactly `Game.Combat`'s own REAL, already-shipped
  `"attack"`/`target_unit_id` handler (story 891). A real 914
  implementation would hang its "was this vassal's pact honored?" check
  off that SAME real combat resolution — this spec drives that real
  surface and asserts the side effects a real implementation would add
  on top of it, exactly as `Criterion7726Spex` did for the trigger.

  ## Judgment call: substituting the illustrative starting strain (55 -> 45)

  Same substitution `BrokenOathsSpex.Story913.Criterion7722Spex` already
  made for the same "an unhonored/honored Protection Pact" family: no
  real production path sets an arbitrary starting Oath Strain figure
  (`BrokenOaths.Game.OathStrain` doesn't exist), but THREE real,
  already-shipped refused-call-to-arms spikes
  (`BrokenOaths.Game.Tribute.spike_oath_strain/1`, +15 each) land
  deterministically at 45 — non-zero, real, and leaves headroom below
  the 100 ceiling for the "falls" assertion below to mean something.
  Only the illustrative literal "55" does not survive; the scenario's
  own subject (a real elevated baseline that a HONORED pact should
  lower) survives intact.

  ## Judgment call: guaranteeing the killing blow

  `Fixtures.set_unit_hp/3` (the same documented, narrow exception
  `BrokenOathsSpex.Story891.Criterion7539Spex` and siblings already
  use) sets the besieging warrior to 1 HP right before Lord Mira's own
  attack, so "defeats... the attacker" is deterministic regardless of
  the random damage roll — this spec's own subject is the Protection
  Pact CONSEQUENCE of a successful defense, not combat RNG.

  ## Judgment call: asserting deltas, not the illustrative numbers

  Per the design doc's own "Round-5 decisions: exact numbers are a
  balancing pass, not a blocker," and mirroring `Criterion7722Spex`'s
  own precedent, this spec asserts DIRECTION only (`strain_after <
  strain_before`, `honor_after > honor_before`), never the illustrative
  "-15, to 40" / "+3" literals.

  ## Judgment call: Honor is read off the AFFECTED player's own board

  "Public, world-visible Honor" has no cross-player viewing surface
  anywhere in this codebase yet (`data-test="player-honor"` only ever
  renders on the logged-in player's OWN `GameLive.Play` — see
  `BrokenOathsSpex.Story908.Criterion7678Spex`/`Story910.Criterion7696Spex`
  for the established precedent of reading the AFFECTED player's own
  board before/after). Same precedent reused here, reading Lord Mira's
  own board rather than fabricating a new public leaderboard this
  story never asked for.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the lord relieves the siege in time and both consequences land",
    fail_on_error_logs: false do
    scenario "defeating the besieger before the window expires lowers the vassal's strain and raises the lord's Honor" do
      given_ "a world with room for three players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 1, frequency: 9}))}
      end

      given_(:registered_player)
      given_(:second_registered_player)
      given_(:third_registered_player)

      given_ "Wes is already Lord Mira's vassal", context do
        {:ok, a_freshly_subjugated_vassal(context)}
      end

      given_ "a rival player joins the world as the eventual besieger", context do
        {:ok, third_join_live, _html} = live(context.third_conn, "/play")

        third_join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, rival_play_live, _html} = live(context.third_conn, "/play/#{context.world.id}")
        {:ok, rival_player} = Fixtures.join_world(context.world, context.third_user)

        {:ok,
         context
         |> Map.put(:rival_play_live, rival_play_live)
         |> Map.put(:rival_player, rival_player)}
      end

      given_ "Wes has already refused three calls to arms, giving him a real, positive Oath Strain baseline",
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

        {:ok, lord_live, _html} = live(context.conn, "/play/#{context.world.id}")

        row_html =
          lord_live
          |> element("[data-test='vassal-row-#{context.other_user.id}']")
          |> render()

        [_, strain_text] = Regex.run(~r/data-test="vassal-oath-strain"[^>]*>(\d+)/, row_html)
        strain_before = String.to_integer(strain_text)

        assert strain_before == 45,
               "setup expected three real 15-point refusal spikes to land at 45, got #{strain_before}"

        {:ok, Map.put(context, :strain_before, strain_before)}
      end

      given_ "a protection call is active — the rival's army besieges Wes's city", context do
        rival_target =
          adjacent_land_tile(context.world, context.other_city.tile_id, [context.my_lord.tile_id])

        warrior =
          Fixtures.spawn_unit(context.world, context.rival_player.id, :warrior, rival_target)

        attempt_event(context.rival_play_live, "attack", %{
          "unit_id" => to_string(warrior.id),
          "target_city_id" => to_string(context.other_city.id)
        })

        {:ok, lord_live, _html} = live(context.conn, "/play/#{context.world.id}")
        honor_html = render(lord_live)
        [_, honor_text] = Regex.run(~r/data-test="player-honor"[^>]*>(-?\d+)/, honor_html)
        honor_before = String.to_integer(honor_text)

        {:ok,
         context
         |> Map.put(:besieger, warrior)
         |> Map.put(:honor_before, honor_before)}
      end

      when_ "Lord Mira's army defeats the attacker before the window would expire", context do
        [besieger_now] =
          for u <- Fixtures.player_units(context.world, context.third_user),
              u.id == context.besieger.id,
              do: u

        Fixtures.set_unit_hp(context.world, besieger_now.id, 1)
        Fixtures.recharge_unit(context.world, context.my_lord.id)

        attempt_event(context.play_live, "attack", %{
          "unit_id" => to_string(context.my_lord.id),
          "target_unit_id" => to_string(besieger_now.id)
        })

        {:ok, context}
      end

      then_ "the call resolves as honored: Wes's Oath Strain falls", context do
        {:ok, lord_live, _html} = live(context.conn, "/play/#{context.world.id}")

        row_html =
          lord_live
          |> element("[data-test='vassal-row-#{context.other_user.id}']")
          |> render()

        [_, strain_text] = Regex.run(~r/data-test="vassal-oath-strain"[^>]*>(\d+)/, row_html)
        strain_after = String.to_integer(strain_text)

        assert strain_after < context.strain_before,
               "honoring a Protection Pact call should LOWER the vassal's Oath Strain " <>
                 "(started at #{context.strain_before}); got #{strain_after}, no decrease"

        {:ok, context}
      end

      then_ "Mira's Honor rises", context do
        {:ok, lord_live, _html} = live(context.conn, "/play/#{context.world.id}")

        assert has_element?(lord_live, "[data-test='player-honor']")

        honor_html = render(lord_live)
        [_, honor_text] = Regex.run(~r/data-test="player-honor"[^>]*>(-?\d+)/, honor_html)
        honor_after = String.to_integer(honor_text)

        assert honor_after > context.honor_before,
               "honoring a Protection Pact call should RAISE the lord's Honor " <>
                 "(started at #{context.honor_before}); got #{honor_after}, no rise"

        {:ok, context}
      end
    end
  end
end
