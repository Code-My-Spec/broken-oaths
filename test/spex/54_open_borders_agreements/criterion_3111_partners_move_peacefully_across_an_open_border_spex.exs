defmodule BrokenOathsSpex.Story994.Criterion3111Spex do
  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "partners move peacefully across an open border" do
    scenario "a partner enters the other player's territory without starting a war" do
      given_ :a_world
      given_ :registered_player
      given_ :second_registered_player
      given_ :two_players_discovered_each_other

      given_ "the players have an active Open Borders agreement", context do
        {:ok, other_play_live, _html} =
          live(context.other_conn, "/play/#{context.world.id}")

        render_hook(context.play_live, "propose_open_borders", %{
          "neighbor_user_id" => to_string(context.other_user.id)
        })

        render_hook(other_play_live, "accept_open_borders", %{
          "neighbor_user_id" => to_string(context.user.id)
        })

        {:ok, Map.put(context, :other_play_live, other_play_live)}
      end

      when_ "a player moves a unit through the partner's territory", context do
        render_hook(context.play_live, "move_through_open_border", %{
          "neighbor_user_id" => to_string(context.other_user.id)
        })

        {:ok, context}
      end

      then_ "the unit enters peacefully and no war begins", context do
        assert has_element?(context.play_live, "[data-test='open-borders-peaceful-entry']")
        refute has_element?(context.play_live, "[data-test='war-active-#{context.other_user.id}']")
        {:ok, context}
      end
    end
  end
end
