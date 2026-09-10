defmodule BrokenOathsSpex.Story947.Criterion2708Spex do
  use BrokenOathsSpex.Case
  import BrokenOathsSpex.SharedGivens

  spex "an always-on Full grant lets the delegate act while the owner is online" do
    scenario "an online owner grants an ally always-on Full control" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)
      given_ "the owner is online and has granted always-on Full control", context do
        {:ok, delegate_live, _} = live(context.other_conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :delegate_live, delegate_live)}
      end
      when_ "the delegate orders the owner's unit to move", context do
        render_hook(context.delegate_live, "steward_move", %{"owner_user_id" => to_string(context.user.id), "unit_id" => "1", "to_tile" => "2"})
        {:ok, context}
      end
      then_ "the delegated order is accepted despite the owner's online presence", context do
        assert has_element?(context.delegate_live, "[data-test='steward-order-accepted']")
        {:ok, context}
      end
    end
  end
end
