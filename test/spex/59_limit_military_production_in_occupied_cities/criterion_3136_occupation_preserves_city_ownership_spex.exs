defmodule BrokenOathsSpex.Story999.Criterion3136Spex do
  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "occupation preserves city ownership" do
    scenario "the original owner still sees the occupied city" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "a wartime rival occupies my city", context do
        {:ok, a_freshly_subjugated_vassal(context)}
      end

      when_ "the occupation begins", context do
        {:ok, context}
      end

      then_ "the original owner can still select the city and it reads occupied", context do
        render_hook(context.other_play_live, "select_city", %{"city_id" => to_string(context.other_city.id)})
        assert has_element?(context.other_play_live, "[data-test='city-panel']")
        assert has_element?(context.other_play_live, "[data-test='city-status']", "occupied")
        {:ok, context}
      end
    end
  end
end
