defmodule BrokenOathsSpex.Story914.Criterion7729Spex do
  @moduledoc """
  Story 914 — Protection Pact
  Criterion 7729 — "Letting a protection call expire unanswered is a
  broken oath: the lord takes a public Honor hit and EVERY vassal in
  the lord's realm takes an Oath Strain spike"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`). The mirror
  branch of `Criterion7728Spex`: the lord does nothing, the window
  lapses, and THREE separate consequences land — the direct victim's
  own large spike, the lord's public Honor hit, and a smaller
  "realm-wide contagion" spike on every OTHER vassal of the same lord.

  ## No new invented event

  Same reasoning as `Criterion7728Spex`: "the window expires with no
  relieving action" needs no invented player-facing event — it's pure
  turn-advancement while the lord simply does nothing. A real 914
  implementation would hang this consequence off `Turn.tick`'s own
  pipeline (an expired, still-pending obligation), not a player action.
  This spec only drives real, already-shipped surfaces (`join_world`,
  `subjugate/5`, `advance_turn`) and asserts the missing side effects.

  ## Judgment call: reaching THREE vassals under one lord

  Reuses `BrokenOathsSpex.Story908.Criterion7679Spex`'s own precedent
  for "a lord with several vassals" (inline `Fixtures.user_fixture/1` +
  `BrokenOathsTest.ConnCase.log_in_user/2`, then
  `SharedGivens.subjugate/5` per additional vassal) — that criterion
  needed three vassals for a DIFFERENT reason (tribute scaling); this
  one needs them because 7729's own gherkin explicitly names "Ada and
  Bo" as fellow vassals who take the CONTAGION spike alongside Wes, the
  direct victim. A fifth, independent player (the besieger) is layered
  on top, so this world needs room for five joined players —
  `frequency: 11`, one step up from `criterion_7679`'s own
  `frequency: 10` (four players), following that file's own documented
  "pick a bigger deterministic world" precedent.

  ## Judgment call: reading each vassal's strain SCOPED to their own row

  Unlike `Criterion7722Spex`'s single-vassal `read_strain/2` (a safe
  whole-page regex when only one `vassal-oath-strain` span can ever
  exist), THIS criterion has three vassal rows on the same page at
  once — a whole-page regex would only ever find the FIRST one,
  silently misreading Ada's or Bo's figure as Wes's. Each read here is
  scoped with `element(lord_live, "[data-test='vassal-row-<id>']")
  |> render()` first, then regexed within just that fragment — the
  `vassal-row`/`vassal-oath-strain` elements themselves are REAL,
  already-shipped story 908 markup, so this scoping is safe today even
  though the CONTAGION mechanic this criterion tests is not.

  ## Judgment call: asserting deltas and their RELATIVE size, not the illustrative numbers

  Same "Round-5 decisions" posture as `Criterion7728Spex`: this spec
  never hardcodes "-8"/"+25"/"+8". It asserts the shape the criterion's
  own text locks in: Mira's Honor falls; Wes (the direct victim) rises;
  Ada and Bo (contagion) also rise, but by LESS than Wes's own rise —
  mirroring `Criterion7722Spex`'s own "large spike vs. smaller rise"
  relational assertion (`pact_delta > refusal_delta`), generalized here
  to "direct victim's delta > each bystander's delta."

  ## Judgment call: no re-assertion of `protection-call` existence here

  `Criterion7726Spex`/`Criterion7727Spex` already cover "a call was
  raised and is visible" — re-asserting that in `given_` here would
  violate the "a given_ should not assert" convention
  (`bdd/spex/boundaries.md`), and the `then_` steps below carry the
  full RED signal on their own via the Honor/strain deltas, all of
  which read REAL, already-shipped elements (`player-honor`,
  `vassal-oath-strain`) — no dependency on the yet-to-be-built
  `protection-call` markup is needed for this criterion's own
  assertions to be meaningful.
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

  spex "letting the call expire is a broken oath with realm-wide consequences",
    fail_on_error_logs: false do
    scenario "an expired, unanswered protection call docks the lord's Honor, spikes the victim's strain heavily, and spikes every fellow vassal's strain more lightly" do
      given_ "a world with room for five players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 7, frequency: 11}))}
      end

      given_(:registered_player)
      given_(:second_registered_player)
      given_(:third_registered_player)

      given_ "Wes is already Lord Mira's vassal", context do
        {:ok, a_freshly_subjugated_vassal(context)}
      end

      given_ "Lord Mira also holds two further vassals, Ada and Bo, sworn before Wes's siege begins",
             context do
        extra_vassals =
          for _ <- 1..2 do
            vassal_user = Fixtures.user_fixture()

            vassal_conn =
              Phoenix.ConnTest.build_conn()
              |> BrokenOathsTest.ConnCase.log_in_user(vassal_user)

            %{} = subjugate(context.world, context.conn, context.user, vassal_conn, vassal_user)

            %{user: vassal_user, conn: vassal_conn}
          end

        [ada, bo] = extra_vassals

        {:ok, context |> Map.put(:ada, ada) |> Map.put(:bo, bo)}
      end

      given_ "a fifth player joins the world as the besieger who will go unanswered", context do
        {:ok, rival_join_live, _html} = live(context.third_conn, "/play")

        rival_join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, rival_play_live, _html} = live(context.third_conn, "/play/#{context.world.id}")
        {:ok, rival_player} = Fixtures.join_world(context.world, context.third_user)

        {:ok,
         context
         |> Map.put(:rival_play_live, rival_play_live)
         |> Map.put(:rival_player, rival_player)}
      end

      given_ "a protection call is active on Wes with a 3-turn window, and the household's starting readings are recorded",
             context do
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

        wes_strain_before = vassal_strain(lord_live, context.other_user.id)
        ada_strain_before = vassal_strain(lord_live, context.ada.user.id)
        bo_strain_before = vassal_strain(lord_live, context.bo.user.id)

        {:ok,
         context
         |> Map.put(:honor_before, honor_before)
         |> Map.put(:wes_strain_before, wes_strain_before)
         |> Map.put(:ada_strain_before, ada_strain_before)
         |> Map.put(:bo_strain_before, bo_strain_before)}
      end

      when_ "the window expires with no relieving action from Mira", context do
        for _ <- 1..5, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the call resolves as broken: Mira's Honor takes a public hit", context do
        {:ok, lord_live, _html} = live(context.conn, "/play/#{context.world.id}")

        assert has_element?(lord_live, "[data-test='player-honor']")

        honor_html = render(lord_live)
        [_, honor_text] = Regex.run(~r/data-test="player-honor"[^>]*>(-?\d+)/, honor_html)
        honor_after = String.to_integer(honor_text)

        assert honor_after < context.honor_before,
               "an unanswered Protection Pact call should DOCK the lord's Honor publicly " <>
                 "(started at #{context.honor_before}); got #{honor_after}, no drop"

        {:ok, context}
      end

      then_ "Wes takes the large, direct unhonored-pact strain spike", context do
        {:ok, lord_live, _html} = live(context.conn, "/play/#{context.world.id}")
        wes_strain_after = vassal_strain(lord_live, context.other_user.id)

        assert wes_strain_after > context.wes_strain_before,
               "the direct victim of an unhonored Protection Pact should take a LARGE Oath " <>
                 "Strain spike (started at #{context.wes_strain_before}); " <>
                 "got #{wes_strain_after}, no rise"

        {:ok, Map.put(context, :wes_strain_after, wes_strain_after)}
      end

      then_ "Ada and Bo each take a smaller realm-wide contagion spike than Wes's own", context do
        {:ok, lord_live, _html} = live(context.conn, "/play/#{context.world.id}")

        ada_strain_after = vassal_strain(lord_live, context.ada.user.id)
        bo_strain_after = vassal_strain(lord_live, context.bo.user.id)

        assert ada_strain_after > context.ada_strain_before,
               "a fellow vassal (Ada) should take a realm-wide contagion Oath Strain spike " <>
                 "when her lord breaks a Protection Pact with ANOTHER vassal (started at " <>
                 "#{context.ada_strain_before}); got #{ada_strain_after}, no rise"

        assert bo_strain_after > context.bo_strain_before,
               "a fellow vassal (Bo) should take a realm-wide contagion Oath Strain spike too " <>
                 "(started at #{context.bo_strain_before}); got #{bo_strain_after}, no rise"

        wes_delta = context.wes_strain_after - context.wes_strain_before
        ada_delta = ada_strain_after - context.ada_strain_before
        bo_delta = bo_strain_after - context.bo_strain_before

        assert ada_delta < wes_delta,
               "Ada's contagion spike (#{ada_delta}) should be SMALLER than Wes's own direct " <>
                 "spike (#{wes_delta}) — the direct victim always takes the bigger hit"

        assert bo_delta < wes_delta,
               "Bo's contagion spike (#{bo_delta}) should be SMALLER than Wes's own direct " <>
                 "spike (#{wes_delta}) — the direct victim always takes the bigger hit"

        {:ok, context}
      end
    end
  end
end
