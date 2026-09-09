defmodule BrokenOathsSpex.Story947.Criterion2711Spex do
  use BrokenOathsSpex.Case
  import BrokenOathsSpex.SharedGivens

  spex "a lord-vassal bond qualifies for a delegated-control grant" do
    scenario "a vassal configures control for their lord" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)
      given_ "the players are joined by a lord-vassal bond", context do
        {:ok, vassal_live, _} = live(context.conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :vassal_live, vassal_live)}
      end
      when_ "the vassal grants the lord Full delegated control", context do
        render_hook(context.vassal_live, "set_delegated_control", %{"ally_user_id" => to_string(context.other_user.id), "level" => "full"})
        {:ok, context}
      end
      then_ "the lord-vassal grant is accepted", context do
        assert has_element?(context.vassal_live, "[data-test='delegated-control-level']", "Full")
        {:ok, context}
      end
    end
  end
end
