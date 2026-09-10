defmodule BrokenOathsSpex.Story947.Criterion2705Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2705 — the same real `"steward_defend"` mechanism
  (criterion 2702) covers a raider freshly inside the owner's own
  borders: `BrokenOaths.Feudal.Stewardship.under_attack?/1` is a
  literal "took damage this instant" signal, not a border check, so
  it fires the moment the raider actually lands a hit — reposition
  only, never a counter-strike (`steward_attack` stays permanently
  refused regardless, criterion 2701).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a Defensive-only delegate strikes a raider inside the owner's borders",
    fail_on_error_logs: false do
    scenario "an accepted ally repositions my freshly attacked Lord to safety" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "a raider has just struck my offline Lord inside my own borders", context do
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
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord,
            do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        [raider_tile | _] =
          context.world
          |> Fixtures.adjacent_tiles(my_lord.tile_id)
          |> Enum.filter(land?)

        raider = Fixtures.spawn_barbarian(context.world, raider_tile)

        {:ok, _result} =
          Fixtures.resolve_barbarian_attack(context.world, raider.id, my_lord.id)

        [my_lord_now] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == my_lord.id,
              do: u

        assert my_lord_now.hp < my_lord.hp, "setup's own raider strike never landed"
        assert my_lord_now.hp > 0, "setup's own raider strike killed the Lord outright"

        safe_target = adjacent_land_tile(context.world, my_lord_now.tile_id, [raider_tile])

        context
        |> Map.put(:ally_live, ally_live)
        |> Map.put(:my_lord, my_lord_now)
        |> Map.put(:raider_tile, raider_tile)
        |> Map.put(:safe_target, safe_target)
        |> then(&{:ok, &1})
      end

      when_ "the ally orders my threatened Lord clear of the raider", context do
        attempt_event(context.ally_live, "steward_defend", %{
          "owner_user_id" => to_string(context.user.id),
          "unit_id" => to_string(context.my_lord.id),
          "to_tile" => context.safe_target
        })

        {:ok, context}
      end

      then_ "the defensive strike actually moved my Lord to safety", context do
        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [settler_now] =
            for u <- Fixtures.player_units(context.world, context.user),
                u.id == context.my_lord.id,
                do: u

          if settler_now.tile_id == context.safe_target do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [settler_now] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.my_lord.id,
              do: u

        assert settler_now.tile_id == context.safe_target
        {:ok, context}
      end
    end
  end
end
