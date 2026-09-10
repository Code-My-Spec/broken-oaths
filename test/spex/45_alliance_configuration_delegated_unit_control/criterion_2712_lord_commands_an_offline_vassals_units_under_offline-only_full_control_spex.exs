defmodule BrokenOathsSpex.Story947.Criterion2712Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2712 — the lord's real unit-command surface over an
  offline vassal is `"steward_defend"` (emergency, adjacent-only
  reposition) — the SAME mechanism criterion 2702/2705 exercise for an
  ally, exercised here for the lord/vassal relationship. There is no
  separate unrestricted "Full control" unit-move surface for anyone
  (criteria 2706-2708's own offline gate, criterion 2701's own
  war-authority refusal).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a lord commands an offline vassal's unit under offline-only Full control",
    fail_on_error_logs: false do
    scenario "the lord repositions the offline vassal's attacked Lord unit to safety" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my vassal's own Lord was just struck by a barbarian while offline, and survived",
             context do
        %{lord_play_live: lord_play_live, vassal_play_live: vassal_play_live} =
          subjugate(
            context.world,
            context.conn,
            context.user,
            context.other_conn,
            context.other_user
          )

        go_offline(vassal_play_live)

        [vassal_lord | _] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :lord,
              do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        [barbarian_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(vassal_lord.tile_id)
          |> Enum.filter(land?)

        barbarian = Fixtures.spawn_barbarian(context.world, barbarian_target)

        {:ok, _result} =
          Fixtures.resolve_barbarian_attack(context.world, barbarian.id, vassal_lord.id)

        [vassal_lord_now] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == vassal_lord.id,
              do: u

        assert vassal_lord_now.hp < vassal_lord.hp, "setup's own barbarian strike never landed"
        assert vassal_lord_now.hp > 0, "setup's own barbarian strike killed the Lord outright"

        safe_target =
          adjacent_land_tile(context.world, vassal_lord_now.tile_id, [barbarian_target])

        context
        |> Map.put(:lord_play_live, lord_play_live)
        |> Map.put(:vassal_lord, vassal_lord_now)
        |> Map.put(:safe_target, safe_target)
        |> then(&{:ok, &1})
      end

      when_ "the lord orders the vassal's threatened Lord to a safe adjacent tile", context do
        attempt_event(context.lord_play_live, "steward_defend", %{
          "owner_user_id" => to_string(context.other_user.id),
          "unit_id" => to_string(context.vassal_lord.id),
          "to_tile" => context.safe_target
        })

        {:ok, context}
      end

      then_ "the lord's delegated order actually moved the vassal's Lord to safety", context do
        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [lord_now] =
            for u <- Fixtures.player_units(context.world, context.other_user),
                u.id == context.vassal_lord.id,
                do: u

          if lord_now.tile_id == context.safe_target do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [lord_now] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.vassal_lord.id,
              do: u

        assert lord_now.tile_id == context.safe_target
        {:ok, context}
      end
    end
  end
end
