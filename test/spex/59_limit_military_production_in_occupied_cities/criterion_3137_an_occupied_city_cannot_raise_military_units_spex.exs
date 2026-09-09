defmodule BrokenOathsSpex.Story999.Criterion3137Spex do
  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "an occupied city cannot raise military units" do
    scenario "the city owner cannot select a warrior while the city is occupied" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my city is occupied by a wartime rival", context do
        {:ok, a_freshly_subjugated_vassal(context)}
      end

      when_ "the city owner opens production choices", context do
        render_hook(context.other_play_live, "select_city", %{"city_id" => to_string(context.other_city.id)})
        {:ok, context}
      end

      then_ "military production is unavailable in the occupied city", context do
        refute has_element?(context.other_play_live, "[data-test='production-option-warrior']")
        {:ok, context}
      end
    end
  end
end
