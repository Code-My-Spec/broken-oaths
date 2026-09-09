defmodule BrokenOathsSpex.Story995.Criterion3116Spex do
  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens
  alias BrokenOathsSpex.Fixtures

  spex "a declared war permits border crossing" do
    scenario "a hostile unit enters the rival's territory" do
      given_ :a_world
      given_ :registered_player
      given_ :second_registered_player
      given_ :two_players_discovered_each_other

      given_ "the rival has founded a city and the player has declared war", context do
        {:ok, other_play_live, _html} = live(context.other_conn, "/play/#{context.world.id}")
        [settler | _] = for unit <- Fixtures.player_units(context.world, context.other_user), unit.type == :settler, do: unit
        render_hook(other_play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        [city] = Fixtures.player_cities(context.world, context.other_user)

        render_hook(context.play_live, "declare_war", %{
          "neighbor_user_id" => to_string(context.other_user.id)
        })

        [lord | _] = for unit <- Fixtures.player_units(context.world, context.user), unit.type == :lord, do: unit
        {:ok, context |> Map.put(:lord, lord) |> Map.put(:rival_city, city)}
      end

      when_ "the player moves the lord across the rival's border", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(context.lord.id),
          "to_tile" => context.rival_city.tile_id
        })

        {:ok, context}
      end

      then_ "the movement order is accepted as hostile border crossing", context do
        assert has_element?(context.play_live, "[data-test='hostile-border-entry']")
        {:ok, context}
      end
    end
  end
end
