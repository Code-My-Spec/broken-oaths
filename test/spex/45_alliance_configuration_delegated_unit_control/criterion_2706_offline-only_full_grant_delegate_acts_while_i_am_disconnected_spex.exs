defmodule BrokenOathsSpex.Story947.Criterion2706Spex do
  use BrokenOathsSpex.Case
  import BrokenOathsSpex.SharedGivens

  spex "an offline-only Full grant lets the delegate act while the owner is disconnected" do
    scenario "the owner disconnects after granting an ally offline-only Full control" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)
      given_ "the owner has granted offline-only Full control and is disconnected", context do
        {:ok, delegate_live, _} = live(context.other_conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :delegate_live, delegate_live)}
      end
      when_ "the delegate orders the owner's unit to move", context do
        render_hook(context.delegate_live, "steward_move", %{"owner_user_id" => to_string(context.user.id), "unit_id" => "1", "to_tile" => "2"})
        {:ok, context}
      end
      then_ "the delegated order is accepted while the owner is offline", context do
        assert has_element?(context.delegate_live, "[data-test='steward-order-accepted']")
        {:ok, context}
      end
    end
  end
end
