defmodule BrokenOathsSpex.Story910.Criterion7692Spex do
  @moduledoc """
  Story 910 — Feudal Stewardship
  Criterion 7692 — "EMERGENCY DEFENSE: normally stewards CANNOT move
  the offline player's units"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Feudal
  Stewardship (910)") — the default-closed baseline `criterion_7693`'s
  own "under attack" exception opens against. With no attack in
  progress, a steward's attempt to move the owner's unit must be
  refused outright.

  ## This criterion's own new judgment call

  `"steward_queue_move"`, `%{"owner_user_id" => ..., "unit_id" => ...,
  "to_tile" => ...}` — mirrors the ordinary `"queue_move"` event's own
  `"unit_id"`/`"to_tile"` param shape, scoped through stewardship.
  Driven through `attempt_event/3` since no `handle_event/3` clause
  exists for it yet.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the steward cannot move units when the owner is not under attack",
    fail_on_error_logs: false do
    scenario "a steward's move order for an offline, unthreatened vassal's unit is refused" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my vassal is offline and not under attack", context do
        %{lord_play_live: lord_play_live, vassal_play_live: vassal_play_live} =
          subjugate(
            context.world,
            context.conn,
            context.user,
            context.other_conn,
            context.other_user
          )

        [vassal_lord | _] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :lord,
              do: u

        go_offline(vassal_play_live)

        target = adjacent_land_tile(context.world, vassal_lord.tile_id)

        context
        |> Map.put(:lord_play_live, lord_play_live)
        |> Map.put(:vassal_lord, vassal_lord)
        |> Map.put(:target, target)
        |> then(&{:ok, &1})
      end

      when_ "I, the steward, attempt to move their Lord", context do
        attempt_event(context.lord_play_live, "steward_queue_move", %{
          "owner_user_id" => to_string(context.other_user.id),
          "unit_id" => to_string(context.vassal_lord.id),
          "to_tile" => context.target
        })

        {:ok, context}
      end

      then_ "the vassal's Lord never moved — the steward's order was refused", context do
        for _ <- 1..3, do: Fixtures.advance_turn(context.world)

        [lord_now] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.vassal_lord.id,
              do: u

        assert lord_now.tile_id == context.vassal_lord.tile_id
        {:ok, context}
      end
    end
  end
end
