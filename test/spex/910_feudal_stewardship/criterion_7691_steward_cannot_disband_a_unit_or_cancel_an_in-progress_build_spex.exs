defmodule BrokenOathsSpex.Story910.Criterion7691Spex do
  @moduledoc """
  Story 910 — Feudal Stewardship
  Criterion 7691 — the disallowed half of `criterion_7690`'s own
  whitelist: "No disbanding, no cancel-griefing, no nonsense"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Feudal
  Stewardship (910)"). A steward's own command surface must refuse
  BOTH destructive actions outright, leaving the owner's already-queued
  build and already-existing unit completely untouched.

  ## Why steward-scoped events, not the ordinary owner-only ones

  `Game.cancel_production_item/4` already exists (story 879) and
  already refuses a non-owner outright (`:not_owner`) — driving that
  event AS the steward would trivially "pass" today for a reason that
  has nothing to do with story 910's own constructive-only whitelist
  (general non-ownership, not a stewardship-specific rule). This
  criterion is about the whitelist a NEW steward command surface must
  itself enforce, so it drives NEW, steward-scoped events instead —
  mirroring `criterion_7690`'s own `"steward_queue_production"` shape:
  `"steward_cancel_production_item"` (`%{"owner_user_id" => ...,
  "city_id" => ..., "item_id" => ...}`) and `"steward_disband_unit"`
  (`%{"owner_user_id" => ..., "unit_id" => ...}`). Neither
  `handle_event/3` clause exists yet — driven through `attempt_event/3`.
  No "disband" mechanic exists anywhere in this codebase yet, for
  anyone, owner or steward — this criterion's OWN new ground either
  way.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the steward cannot disband a unit or cancel an in-progress build",
       fail_on_error_logs: false do
    scenario "cancel and disband attempts through the steward surface change nothing" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my vassal is offline, already building a Warrior, with their Settler still standing",
             context do
        %{lord_play_live: lord_play_live, vassal_city: vassal_city, vassal_play_live: vassal_play_live} =
          subjugate(context.world, context.conn, context.user, context.other_conn, context.other_user)

        render_hook(vassal_play_live, "queue_production", %{
          "city_id" => to_string(vassal_city.id),
          "item" => "worker"
        })

        [city_before] =
          for c <- Fixtures.player_cities(context.world, context.other_user),
              c.id == vassal_city.id,
              do: c

        [queued_item | _] = city_before.queue

        [vassal_lord | _] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :lord,
              do: u

        go_offline(vassal_play_live)

        context
        |> Map.put(:lord_play_live, lord_play_live)
        |> Map.put(:vassal_city, vassal_city)
        |> Map.put(:queued_item, queued_item)
        |> Map.put(:vassal_lord, vassal_lord)
        |> then(&{:ok, &1})
      end

      when_ "I, the steward, attempt to cancel their build and disband their Lord", context do
        attempt_event(context.lord_play_live, "steward_cancel_production_item", %{
          "owner_user_id" => to_string(context.other_user.id),
          "city_id" => to_string(context.vassal_city.id),
          "item_id" => to_string(context.queued_item.id)
        })

        attempt_event(context.lord_play_live, "steward_disband_unit", %{
          "owner_user_id" => to_string(context.other_user.id),
          "unit_id" => to_string(context.vassal_lord.id)
        })

        {:ok, context}
      end

      then_ "the build is still queued", context do
        [city_now] =
          for c <- Fixtures.player_cities(context.world, context.other_user),
              c.id == context.vassal_city.id,
              do: c

        assert city_now.queue != [], "the steward's cancel attempt succeeded — it must not"
        [current | _] = city_now.queue
        assert current.id == context.queued_item.id
        {:ok, context}
      end

      then_ "their Lord still stands", context do
        survivors =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.vassal_lord.id,
              do: u

        assert survivors != [], "the steward's disband attempt succeeded — it must not"
        {:ok, context}
      end
    end
  end
end
