defmodule BrokenOathsSpex.Story947.Criterion2709Spex do
  use BrokenOathsSpex.Case
  import BrokenOathsSpex.SharedGivens

  spex "a Full-control delegate cannot disband the owner's unit" do
    scenario "an accepted delegate with Full control tries to disband a unit" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)
      given_ "the owner has granted the offline delegate Full control", context do
        {:ok, delegate_live, _} = live(context.other_conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :delegate_live, delegate_live)}
      end
      when_ "the delegate tries to disband the owner's unit", context do
        render_hook(context.delegate_live, "steward_disband", %{"owner_user_id" => to_string(context.user.id), "unit_id" => "1"})
        {:ok, context}
      end
      then_ "the unit is not disbanded", context do
        refute has_element?(context.delegate_live, "[data-test='steward-disband-accepted']")
        assert has_element?(context.delegate_live, "[data-test='steward-error']", "disband")
        {:ok, context}
      end
    end
  end
end
