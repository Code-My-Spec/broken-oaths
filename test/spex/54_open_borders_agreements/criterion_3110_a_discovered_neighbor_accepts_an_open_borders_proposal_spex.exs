defmodule BrokenOathsSpex.Story994.Criterion3110Spex do
  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "a discovered neighbor accepts an Open Borders proposal" do
    scenario "the agreement becomes active between the two players" do
      given_ :a_world
      given_ :registered_player
      given_ :second_registered_player
      given_ :two_players_discovered_each_other

      when_ "one player proposes Open Borders and the other accepts", context do
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

      then_ "an Open Borders agreement is active between them", context do
        assert has_element?(
                 context.play_live,
                 "[data-test='open-borders-active-#{context.other_user.id}']"
               )

        assert has_element?(
                 context.other_play_live,
                 "[data-test='open-borders-active-#{context.user.id}']"
               )

        {:ok, context}
      end
    end
  end
end
