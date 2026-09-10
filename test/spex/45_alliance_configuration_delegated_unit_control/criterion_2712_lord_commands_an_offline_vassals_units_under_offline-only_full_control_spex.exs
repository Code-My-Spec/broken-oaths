defmodule BrokenOathsSpex.Story947.Criterion2712Spex do
  use BrokenOathsSpex.Case
  import BrokenOathsSpex.SharedGivens

  spex "a lord commands an offline vassal's unit under offline-only Full control" do
    scenario "an offline vassal has granted their lord offline-only Full control" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)
      given_ "the vassal is offline and has granted their lord offline-only Full control", context do
        {:ok, lord_live, _} = live(context.other_conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :lord_live, lord_live)}
      end
      when_ "the lord orders the vassal's unit to move", context do
        render_hook(context.lord_live, "steward_move", %{"owner_user_id" => to_string(context.user.id), "unit_id" => "1", "to_tile" => "2"})
        {:ok, context}
      end
      then_ "the lord's delegated order is accepted", context do
        assert has_element?(context.lord_live, "[data-test='steward-order-accepted']")
        {:ok, context}
      end
    end
  end
end
