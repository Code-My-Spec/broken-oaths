defmodule BrokenOathsSpex.Story994.Criterion3112Spex do
  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "a partner revokes Open Borders" do
    scenario "the agreement is no longer active between the players" do
      given_ :a_world
      given_ :registered_player
      given_ :second_registered_player
      given_ :two_players_discovered_each_other

      given_ "the players have an active Open Borders agreement", context do
        {:ok, other_play_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        render_hook(context.play_live, "propose_open_borders", %{
          "neighbor_user_id" => to_string(context.other_user.id)
        })

        render_hook(other_play_live, "accept_open_borders", %{
          "neighbor_user_id" => to_string(context.user.id)
        })

        {:ok, Map.put(context, :other_play_live, other_play_live)}
      end

      when_ "either partner revokes the agreement", context do
        render_hook(context.play_live, "revoke_open_borders", %{
          "neighbor_user_id" => to_string(context.other_user.id)
        })

        {:ok, context}
      end

      then_ "Open Borders is no longer active between them", context do
        refute has_element?(
                 context.play_live,
                 "[data-test='open-borders-active-#{context.other_user.id}']"
               )

        refute has_element?(
                 context.other_play_live,
                 "[data-test='open-borders-active-#{context.user.id}']"
               )

        {:ok, context}
      end
    end
  end
end
