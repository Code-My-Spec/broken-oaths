defmodule BrokenOathsSpex.Story947.Criterion2710Spex do
  use BrokenOathsSpex.Case
  import BrokenOathsSpex.SharedGivens

  spex "a grant to an ally does not grant reciprocal control" do
    scenario "an owner grants Full control to an accepted ally" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)
      given_ "the owner has granted Full control to the ally only", context do
        {:ok, owner_live, _} = live(context.conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :owner_live, owner_live)}
      end
      when_ "the owner tries to command the ally's unit without a grant back", context do
        render_hook(context.owner_live, "steward_move", %{"owner_user_id" => to_string(context.other_user.id), "unit_id" => "1", "to_tile" => "2"})
        {:ok, context}
      end
      then_ "the reciprocal delegated order is refused", context do
        refute has_element?(context.owner_live, "[data-test='steward-order-accepted']")
        assert has_element?(context.owner_live, "[data-test='steward-error']", "control")
        {:ok, context}
      end
    end
  end
end
