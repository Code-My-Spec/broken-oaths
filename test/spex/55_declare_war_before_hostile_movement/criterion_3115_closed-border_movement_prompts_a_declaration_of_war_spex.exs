defmodule BrokenOathsSpex.Story995.Criterion3115Spex do
  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens
  alias BrokenOathsSpex.Fixtures

  spex "closed-border movement prompts a declaration of war" do
    scenario "a unit cannot enter a rival's territory before war is declared" do
      given_ :a_world
      given_ :registered_player
      given_ :second_registered_player

      given_ "both players have joined and the rival has founded a city", context do
        {:ok, join_live, _html} = live(context.conn, "/play")
        join_live |> element("[data-test='join-world-#{context.world.id}']") |> render_click()
        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        {:ok, other_join_live, _html} = live(context.other_conn, "/play")
        other_join_live |> element("[data-test='join-world-#{context.world.id}']") |> render_click()
        {:ok, other_play_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        [settler | _] = for unit <- Fixtures.player_units(context.world, context.other_user), unit.type == :settler, do: unit
        render_hook(other_play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        [city] = Fixtures.player_cities(context.world, context.other_user)
        [lord | _] = for unit <- Fixtures.player_units(context.world, context.user), unit.type == :lord, do: unit

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:lord, lord) |> Map.put(:rival_city, city)}
      end

      when_ "the player attempts to move the lord into the rival's territory", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(context.lord.id),
          "to_tile" => context.rival_city.tile_id
        })

        {:ok, context}
      end

      then_ "the board prompts the player to declare war before crossing the border", context do
        assert has_element?(context.play_live, "[data-test='declare-war-required']")
        {:ok, context}
      end
    end
  end
end
