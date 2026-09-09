defmodule BrokenOathsSpex.Story996.Criterion3122Spex do
  @moduledoc """
  Story 996 — Conduct a War
  Criterion 3122 — A wartime player fights for a rival city.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens
  alias BrokenOathsSpex.Fixtures

  spex "a wartime player attacks a rival city" do
    scenario "an adjacent warrior fights for control of the rival city" do
      given_ :a_world
      given_ :registered_player
      given_ :second_registered_player

      given_ "the player is at war with a rival city and has an adjacent Warrior", context do
        context = join_and_found_rival_city(context)

        [my_settler | _] =
          for unit <- Fixtures.player_units(context.world, context.user),
              unit.type == :settler,
              do: unit

        render_hook(context.play_live, "found_city", %{"unit_id" => to_string(my_settler.id)})
        [my_city] = Fixtures.player_cities(context.world, context.user)
        :ok = clear_all_camps(context.world)

        render_hook(context.play_live, "queue_production", %{
          "city_id" => to_string(my_city.id),
          "item" => "warrior"
        })

        for _ <- 1..8, do: Fixtures.advance_turn(context.world)

        [warrior | _] =
          for unit <- Fixtures.player_units(context.world, context.user),
              unit.type == :warrior,
              do: unit

        [lord | _] =
          for unit <- Fixtures.player_units(context.world, context.user), unit.type == :lord, do: unit

        target_tile =
          adjacent_land_tile(context.world, context.other_city.tile_id, [
            my_city.tile_id,
            lord.tile_id,
            warrior.tile_id
          ])

        render_hook(context.play_live, "declare_war", %{
          "neighbor_user_id" => to_string(context.other_user.id)
        })

        warrior = march_to(context.play_live, context.world, context.user, warrior, target_tile)

        {:ok, Map.put(context, :warrior, warrior)}
      end

      when_ "the player orders the Warrior to attack the rival city", context do
        attempt_event(context.play_live, "attack", %{
          "unit_id" => to_string(context.warrior.id),
          "target_city_id" => to_string(context.other_city.id)
        })

        {:ok, context}
      end

      then_ "the player receives a combat report for the city fight", context do
        assert_push_event(context.play_live, "game:combat", %{damage_dealt: dealt}, 500)
        assert dealt > 0
        {:ok, context}
      end
    end
  end
end
