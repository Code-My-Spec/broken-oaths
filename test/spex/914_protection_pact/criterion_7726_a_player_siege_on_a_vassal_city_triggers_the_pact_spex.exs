defmodule BrokenOathsSpex.Story914.Criterion7726Spex do
  @moduledoc """
  Story 914 — Protection Pact
  Criterion 7726 — "When a vassal's city or units come under attack by a
  third party, the lord is notified and is expected to defend"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Rebellion
  batch — LOCKED model"). This is the TRIGGER half: a real attack on a
  vassal — by either a rival player OR a barbarian warband — must raise
  a Protection Pact obligation against the vassal's lord.

  `BrokenOaths.Game.ProtectionPact` (this story's own component) does
  not exist anywhere in this codebase yet — no schema, no attack
  listener, no obligation record, no UI. This spec drives the REAL
  attack surfaces this codebase already ships (story 906's `"attack"`/
  `target_city_id` for a player siege, story 893's `resolve_barbarian_
  attack_for_test` for a barbarian strike) and asserts the SIDE EFFECT
  a real 914 implementation would need to add on top of them — nothing
  here invents a new player-facing event, because the design is
  explicit that raising the call is automatic ("the lord is notified"),
  not something either player triggers by hand.

  ## Judgment call: the invented "protection-call" surface

  No UI exists for an active obligation. This spec's own judgment
  call, following the naming precedent story 908 set for `vassal-row`/
  `vassal-oath-strain`: a sibling `data-test="protection-call"` element
  nested inside the LORD's own `[data-test="vassal-row-<vassal_user_id>"]`
  row, present only while a call is active for that vassal. Later
  criteria in this story (7727-7730) extend this same family of
  selectors (`protection-window`, `my-protection-call`,
  `protection-honored-count`) — this criterion only needs the
  coarsest signal: does an obligation exist at all.

  ## Judgment call: "vassal's city OR units" — the barbarian sub-case

  The gherkin's own second clause ("the same obligation arises if the
  attacker is a barbarian warband") doesn't specify city vs. unit. Per
  the design doc's own wording ("a vassal's city OR UNITS"), this spec
  drives the barbarian case against the vassal's own LORD UNIT (still
  standing wherever the world placed it — vassalization never touches
  a player's OTHER units, only the city that triggered subjugation),
  via `Fixtures.spawn_barbarian/2` + `Fixtures.resolve_barbarian_
  attack/3` — the same narrow, ownerless-attacker bridge story 893/910
  already use. This is lighter than orchestrating a full barbarian-vs-
  city pillage sequence (camp isolation, city growth within a camp's
  leash, etc. — see story 895's own `criterion_7568` for how heavy that
  path is) and is equally faithful to the criterion's own text.

  ## FLAGGED — genuinely ambiguous (Three Amigos open question)

  The story's own "Three Amigos" note asks "what counts as 'under
  attack' (the hp<max_hp proxy vs. a first-class flag)" and leaves it
  open. This spec does not resolve that question — it treats "a real
  attack event was just registered against the vassal" as the trigger,
  which is compatible with EITHER eventual answer (a first-class flag
  would still be set at the moment of a real attack; an hp<max_hp proxy
  would become true as this same attack's direct side effect). Whoever
  implements 914 still has a real design choice to make here.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a real siege registers a Protection Pact obligation against the lord",
    fail_on_error_logs: false do
    scenario "the obligation is created whether the attacker is a rival player or a barbarian warband" do
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

      when_ "the rival's army besieges Wes's city — a real attack is registered", context do
        warrior =
          Fixtures.spawn_unit(context.world, context.rival_player.id, :warrior, context.rival_target)

        attempt_event(context.rival_play_live, "attack", %{
          "unit_id" => to_string(warrior.id),
          "target_city_id" => to_string(context.other_city.id)
        })

        {:ok, context}
      end

      then_ "a Protection Pact obligation is created against Lord Mira for that attack", context do
        {:ok, lord_live, _html} = live(context.conn, "/play/#{context.world.id}")

        assert has_element?(
                 lord_live,
                 "[data-test='vassal-row-#{context.other_user.id}'] [data-test='protection-call']"
               ),
               "no \"protection-call\" obligation rendered for Wes yet — " <>
                 "BrokenOaths.Game.ProtectionPact doesn't exist"

        {:ok, context}
      end

      then_ "the same obligation arises if the attacker is a barbarian warband rather than a player",
            context do
        [wes_lord] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :lord,
              do: u

        barbarian_target = adjacent_land_tile(context.world, wes_lord.tile_id, [])
        barbarian = Fixtures.spawn_barbarian(context.world, barbarian_target)

        {:ok, _result} =
          Fixtures.resolve_barbarian_attack(context.world, barbarian.id, wes_lord.id)

        {:ok, lord_live, _html} = live(context.conn, "/play/#{context.world.id}")

        assert has_element?(
                 lord_live,
                 "[data-test='vassal-row-#{context.other_user.id}'] [data-test='protection-call']"
               ),
               "no \"protection-call\" obligation rendered for Wes after the barbarian strike " <>
                 "either — ProtectionPact must react the same way to a barbarian attacker as to " <>
                 "a rival player"

        {:ok, context}
      end
    end
  end
end
