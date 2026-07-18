defmodule BrokenOathsSpex.Story908.Criterion7677Spex do
  @moduledoc """
  Story 908 — Tribute Payments
  Criterion 7677 — "Levies — call to arms: the lord issues a call, the
  vassal must send units to the lord's war or refuse... Vassal retains
  command of the pledged units but owes the service"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, §C). This is
  the answer branch: the vassal commits, and "call to arms = pledge a
  SHARE of standing army for the war's duration... Vassal keeps command
  of the pledged units" (same doc, "Round-5 decisions").

  `BrokenOaths.Game.Levy` (the schema this criterion's own relationship
  is built on) already exists: `lord_player_id`, `vassal_player_id`,
  `target_player_id` (the war's target — a THIRD party, per the
  schema's own `validate_target_not_vassal`/`validate_target_not_lord`
  guards), `pledged_share` (0, 1]), `status`
  (`:pending`/`:answered`/`:refused`). No context function or UI wires
  it up yet.

  ## This criterion's own new judgment calls

  1. **Issuing the call**: `"issue_levy"`, `%{"vassal_user_id" => ...,
     "target_user_id" => ..., "share" => "0.5"}` — the target is a
     third, independently-joined player (`context.third_user`), never
     the vassal or the lord themselves (the schema's own guards).
  2. **Answering it**: `"answer_levy"`, `%{"lord_user_id" => ...}` — the
     vassal has at most one pending levy from their own (singular)
     lord, so no further disambiguation is needed.
  3. **The levy's own status badge**: `data-test="levy-status"` on
     BOTH the lord's own Vassals-list row and the vassal's own view,
     reading `"answered"` once accepted.

  Both driven through `attempt_event/3` since no `handle_event/3`
  clauses exist for either yet.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a vassal answers a call to arms and keeps command of the units sent",
       fail_on_error_logs: false do
    scenario "answering a levy shows it answered, and the vassal still commands their own units" do
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

      when_ "the vassal answers the call", context do
        attempt_event(context.other_play_live, "answer_levy", %{
          "lord_user_id" => to_string(context.user.id)
        })

        {:ok, context}
      end

      then_ "the levy reads answered on both the lord's and the vassal's own view", context do
        assert context.my_lord.tile_id == context.other_city.tile_id

        {:ok, fresh_lord_live, _html} = live(context.conn, "/play/#{context.world.id}")
        {:ok, fresh_vassal_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        assert has_element?(
                 fresh_lord_live,
                 "[data-test='vassal-row-#{context.other_user.id}'] [data-test='levy-status']",
                 "answered"
               )

        assert has_element?(fresh_vassal_live, "[data-test='levy-status']", "answered")
        {:ok, context}
      end

      then_ "the vassal still commands their own pledged army — a move order still works",
            context do
        {:ok, fresh_vassal_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        [their_lord] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :lord,
              do: u

        vassal_target =
          adjacent_land_tile(context.world, their_lord.tile_id, [context.other_city.tile_id])

        their_lord = march_to(fresh_vassal_live, context.world, context.other_user, their_lord, vassal_target)

        assert their_lord.tile_id == vassal_target
        {:ok, context}
      end
    end
  end
end
