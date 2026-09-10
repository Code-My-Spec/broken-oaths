defmodule BrokenOathsSpex.Story947.Criterion2707Spex do
  use BrokenOathsSpex.Case
  import BrokenOathsSpex.SharedGivens

  spex "an offline-only Full grant blocks the delegate while the owner is online" do
    scenario "the owner remains connected after granting an ally offline-only Full control" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)
      given_ "the owner is online with an offline-only Full grant to the ally", context do
        {:ok, delegate_live, _} = live(context.other_conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :delegate_live, delegate_live)}
      end
      when_ "the delegate tries to order the owner's unit", context do
        render_hook(context.delegate_live, "steward_move", %{"owner_user_id" => to_string(context.user.id), "unit_id" => "1", "to_tile" => "2"})
        {:ok, context}
      end
      then_ "the delegated order is refused while the owner is online", context do
        refute has_element?(context.delegate_live, "[data-test='steward-order-accepted']")
        assert has_element?(context.delegate_live, "[data-test='steward-error']", "online")
        {:ok, context}
      end
    end
  end
end
