defmodule BrokenOathsSpex.Story994.Criterion3113Spex do
  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "a unit cannot newly enter after revocation" do
    scenario "a former partner is stopped at the revoked border" do
      given_ :a_world
      given_ :registered_player
      given_ :second_registered_player
      given_ :two_players_discovered_each_other

      given_ "the players had Open Borders and it has been revoked", context do
        {:ok, other_play_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        render_hook(context.play_live, "propose_open_borders", %{
          "neighbor_user_id" => to_string(context.other_user.id)
        })

        render_hook(other_play_live, "accept_open_borders", %{
          "neighbor_user_id" => to_string(context.user.id)
        })

        render_hook(context.play_live, "revoke_open_borders", %{
          "neighbor_user_id" => to_string(context.other_user.id)
        })

        {:ok, context}
      end

      when_ "the former partner tries to enter the rival territory", context do
        render_hook(context.play_live, "move_through_open_border", %{
          "neighbor_user_id" => to_string(context.other_user.id)
        })

        {:ok, context}
      end

      then_ "the board refuses peaceful border entry and keeps Open Borders inactive", context do
        assert has_element?(context.play_live, "[data-test='open-borders-entry-refused']")

        refute has_element?(
                 context.play_live,
                 "[data-test='open-borders-active-#{context.other_user.id}']"
               )

        {:ok, context}
      end
    end
  end
end
