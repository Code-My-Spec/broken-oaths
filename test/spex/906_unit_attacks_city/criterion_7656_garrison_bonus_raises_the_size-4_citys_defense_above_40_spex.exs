defmodule BrokenOathsSpex.Story906.Criterion7656Spex do
  @moduledoc """
  Story 906 — Unit Attacks City
  Criterion 7656 — garrisoning a Warrior (Defense 10) on a size-4
  city's own tile raises its defensive strength from the undefended
  baseline of 40 (`criterion_7655`) to `40 + 10 = 50`
  (`Game.CityDefense.defensive_strength/2`'s additive garrison term),
  and the garrison now delivers real counter-attack damage on an
  assault instead of `criterion_7655`'s zero.

  Already-implemented behavior — see `criterion_7652`'s own moduledoc
  for why city assault and the additive garrison formula predate this
  story; this is this story's own acceptance test that the SAME formula
  applies to a rival's city under a real cross-player assault, not just
  the player's own city (`criterion_7562`, story 895).

  Growth to size 4 mirrors `criterion_7655`'s own idiom; garrisoning
  mirrors `BrokenOathsSpex.Story895.Criterion7562Spex`'s own "produce a
  Warrior, confirm it lands on the city's own tile" idiom.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a garrison raises the size-4 city's defense above 40" do
    scenario "a garrisoned size-4 rival city shows defense 50 and lands a real counter" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "a rival city has grown to size 4 with a Warrior garrisoned on its own tile, and my Lord stands adjacent",
             context do
        context = join_and_found_rival_city(context)
        :ok = clear_all_camps(context.world)

        Enum.reduce_while(1..300, :ok, fn _, :ok ->
          [c] =
            for cc <- Fixtures.player_cities(context.world, context.other_user),
                cc.id == context.other_city.id,
                do: cc

          if c.size >= 4 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        render_hook(context.other_play_live, "queue_production", %{
          "city_id" => to_string(context.other_city.id),
          "item" => "warrior"
        })

        for _ <- 1..8, do: Fixtures.advance_turn(context.world)

        [garrison] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :warrior,
              do: u

        garrison =
          if garrison.tile_id == context.other_city.tile_id do
            garrison
          else
            march_to(
              context.other_play_live,
              context.world,
              context.other_user,
              garrison,
              context.other_city.tile_id
            )
          end

        assert garrison.tile_id == context.other_city.tile_id

        [my_lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        target = adjacent_land_tile(context.world, context.other_city.tile_id, [my_lord.tile_id])
        my_lord = march_to(context.play_live, context.world, context.user, my_lord, target)

        context
        |> Map.put(:my_lord, my_lord)
        |> Map.put(:garrison, garrison)
        |> then(&{:ok, &1})
      end

      when_ "I order my Lord to attack the garrisoned rival city", context do
        attempt_event(context.play_live, "attack", %{
          "unit_id" => to_string(context.my_lord.id),
          "target_city_id" => to_string(context.other_city.id)
        })

        {:ok, context}
      end

      then_ "the rival's own city panel shows defense 50, and my Lord takes real counter damage",
            context do
        render_hook(context.other_play_live, "select_city", %{
          "city_id" => to_string(context.other_city.id)
        })

        assert has_element?(context.other_play_live, "[data-test='city-defense']", "50")
        refute has_element?(context.other_play_live, "[data-test='city-defense']", "40")

        assert_push_event(context.play_live, "game:combat", %{damage_taken: taken}, 500)
        assert taken > 0
        {:ok, context}
      end
    end
  end
end
