defmodule BrokenOathsSpex.Story947.Criterion2702Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2702 — an accepted ally's ONE real steward-initiated unit
  action, `"steward_defend"` (`BrokenOaths.Feudal.Stewardship.defend/5`),
  actually repositions the offline owner's threatened unit to safety
  once `under_attack?/1` is true — proven the same way criterion
  7693 (story 910) proves it for an ally, reused here under story
  947's own name.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a Defensive-only ally repels an attacker on the owner's city", fail_on_error_logs: false do
    scenario "an accepted ally moves the offline, attacked owner's unit to a safe tile" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my offline Lord was just struck by a barbarian and survived", context do
        %{play_live_a: owner_live, play_live_b: ally_live} =
          establish_accepted_alliance(
            context.world,
            context.conn,
            context.user,
            context.other_conn,
            context.other_user
          )

        go_offline(owner_live)

        [my_lord | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        [barbarian_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(my_lord.tile_id)
          |> Enum.filter(land?)

        barbarian = Fixtures.spawn_barbarian(context.world, barbarian_target)

        {:ok, _result} = Fixtures.resolve_barbarian_attack(context.world, barbarian.id, my_lord.id)

        [my_lord_now] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == my_lord.id,
            do: u

        assert my_lord_now.hp < my_lord.hp, "setup's own barbarian strike never landed"
        assert my_lord_now.hp > 0, "setup's own barbarian strike killed the Lord outright"

        safe_target = adjacent_land_tile(context.world, my_lord_now.tile_id, [barbarian_target])

        context
        |> Map.put(:ally_live, ally_live)
        |> Map.put(:my_lord, my_lord_now)
        |> Map.put(:safe_target, safe_target)
        |> then(&{:ok, &1})
      end

      when_ "the ally orders my defending Lord to a safe adjacent tile", context do
        attempt_event(context.ally_live, "steward_defend", %{
          "owner_user_id" => to_string(context.user.id),
          "unit_id" => to_string(context.my_lord.id),
          "to_tile" => context.safe_target
        })

        {:ok, context}
      end

      then_ "the defensive order actually moved my Lord to safety", context do
        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [lord_now] =
            for u <- Fixtures.player_units(context.world, context.user),
                u.id == context.my_lord.id,
                do: u

          if lord_now.tile_id == context.safe_target do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [lord_now] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == context.my_lord.id,
            do: u

        assert lord_now.tile_id == context.safe_target
        {:ok, context}
      end

      then_ "the ally was not given unrelated offensive control", context do
        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        [target_tile | _] =
          context.world |> Fixtures.adjacent_tiles(context.my_lord.tile_id) |> Enum.filter(land?)

        barbarian = Fixtures.spawn_barbarian(context.world, target_tile)

        attempt_event(context.ally_live, "steward_attack", %{
          "owner_user_id" => to_string(context.user.id),
          "unit_id" => to_string(context.my_lord.id),
          "target_camp_id" => to_string(barbarian.id)
        })

        [barbarian_now] =
          for u <- Fixtures.visible_units(context.world, context.user), u.id == barbarian.id,
            do: u

        assert barbarian_now.hp == barbarian.hp
        {:ok, context}
      end
    end
  end
end
