defmodule BrokenOathsSpex.Story1001.Criterion3126Spex do
  @moduledoc """
  Story 1001 — Mutual Peace Without Settlements
  Criterion 3126 — Peace preserves wartime conquests.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "peace preserves the cities each wartime player controls" do
    scenario "accepting peace does not transfer a conquered city back to its former owner" do
      given_ :a_world
      given_ :registered_player
      given_ :second_registered_player
      given_ :two_players_discovered_each_other

      given_ "the players are at war and the player controls the rival's conquered city", context do
        {:ok, other_play_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        [settler | _] =
          for unit <- BrokenOathsSpex.Fixtures.player_units(context.world, context.other_user), unit.type == :settler, do: unit

        render_hook(other_play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        [city] = BrokenOathsSpex.Fixtures.player_cities(context.world, context.other_user)
        :ok = clear_all_camps(context.world)

        render_hook(context.play_live, "declare_war", %{
          "neighbor_user_id" => to_string(context.other_user.id)
        })

        [lord] =
          for unit <- BrokenOathsSpex.Fixtures.player_units(context.world, context.user), unit.type == :lord, do: unit

        target = adjacent_land_tile(context.world, city.tile_id, [lord.tile_id])
        lord = march_to(context.play_live, context.world, context.user, lord, target)
        {_lord, _broken_city} = capture_city(context.play_live, context.world, context.user, lord, context.other_user, city)

        {:ok, context |> Map.put(:other_play_live, other_play_live) |> Map.put(:conquered_city_id, city.id)}
      end

      when_ "both players accept a peace offer", context do
        render_hook(context.play_live, "offer_peace", %{
          "counterparty_user_id" => to_string(context.other_user.id)
        })

        {:ok, rival_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        rival_live
        |> element("[data-test='accept-peace']")
        |> render_click()

        {:ok, context}
      end

      then_ "the conquered city remains under its wartime controller's ownership", context do
        {:ok, player_live, _html} = live(context.conn, "/play/#{context.world.id}")
        {:ok, rival_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        assert has_element?(player_live, "[data-test='captured-city-#{context.conquered_city_id}']")
        refute has_element?(rival_live, "[data-test='captured-city-#{context.conquered_city_id}']")
        refute has_element?(player_live, "[data-test='at-war-with']")
        refute has_element?(rival_live, "[data-test='at-war-with']")

        {:ok, context}
      end
    end
  end
end
