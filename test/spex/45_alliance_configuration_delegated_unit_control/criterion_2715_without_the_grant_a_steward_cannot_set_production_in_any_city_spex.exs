defmodule BrokenOathsSpex.Story947.Criterion2715Spex do
  use BrokenOathsSpex.Case
  import BrokenOathsSpex.SharedGivens

  spex "without steward production permission a steward cannot set production in any city" do
    scenario "an eligible steward has no empire-wide production grant" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)
      given_ "the owner is offline and has not granted steward production", context do
        {:ok, steward_live, _} = live(context.other_conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :steward_live, steward_live)}
      end
      when_ "the steward tries to queue production in the owner's city", context do
        render_hook(context.steward_live, "steward_queue_production", %{"owner_user_id" => to_string(context.user.id), "city_id" => "1", "item" => "warrior"})
        {:ok, context}
      end
      then_ "the production change is refused for every owner city", context do
        refute has_element?(context.steward_live, "[data-test='steward-production-accepted']")
        assert has_element?(context.steward_live, "[data-test='steward-error']", "production")
        {:ok, context}
      end
    end
  end
end
