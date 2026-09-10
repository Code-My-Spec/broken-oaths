defmodule BrokenOathsSpex.Story947.Criterion2714Spex do
  use BrokenOathsSpex.Case
  import BrokenOathsSpex.SharedGivens

  spex "granting steward production applies to every city at once" do
    scenario "an offline owner grants an eligible steward production permission" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)
      given_ "the owner has cities and an eligible offline steward", context do
        {:ok, steward_live, _} = live(context.other_conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :steward_live, steward_live)}
      end
      when_ "the owner grants steward production for their empire", context do
        render_hook(context.steward_live, "set_steward_production", %{"owner_user_id" => to_string(context.user.id), "enabled" => true})
        {:ok, context}
      end
      then_ "the steward can select production in every owner city", context do
        assert has_element?(context.steward_live, "[data-test='steward-production-enabled']")
        {:ok, context}
      end
    end
  end
end
