defmodule BrokenOathsSpex.Story947.Criterion2713Spex do
  use BrokenOathsSpex.Case
  import BrokenOathsSpex.SharedGivens

  spex "a vassal's grant to their lord is independent of the lord's grant back" do
    scenario "a lord and vassal configure different delegated-control levels" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)
      given_ "the players have a lord-vassal bond", context do
        {:ok, vassal_live, _} = live(context.conn, ~p"/play/#{context.world.id}")
        {:ok, lord_live, _} = live(context.other_conn, ~p"/play/#{context.world.id}")
        {:ok, context |> Map.put(:vassal_live, vassal_live) |> Map.put(:lord_live, lord_live)}
      end
      when_ "the vassal grants Full control to the lord and the lord grants None back", context do
        render_hook(context.vassal_live, "set_delegated_control", %{"ally_user_id" => to_string(context.other_user.id), "level" => "full"})
        render_hook(context.lord_live, "set_delegated_control", %{"ally_user_id" => to_string(context.user.id), "level" => "none"})
        {:ok, context}
      end
      then_ "each direction retains its own configured level", context do
        assert has_element?(context.vassal_live, "[data-test='delegated-control-level']", "Full")
        assert has_element?(context.lord_live, "[data-test='delegated-control-level']", "None")
        {:ok, context}
      end
    end
  end
end
