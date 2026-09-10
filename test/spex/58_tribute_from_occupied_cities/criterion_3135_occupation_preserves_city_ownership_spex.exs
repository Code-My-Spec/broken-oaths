defmodule BrokenOathsSpex.Story998.Criterion3135Spex do
  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens
  alias BrokenOathsSpex.Fixtures

  spex "occupation preserves city ownership" do
    scenario "tribute does not transfer ownership from the original city owner" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "I occupy the rival's city", context do
        {:ok, a_freshly_subjugated_vassal(context)}
      end

      when_ "the city pays tribute to its occupying player", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the original owner can still select the city as their own while it is occupied", context do
        render_hook(context.other_play_live, "select_city", %{"city_id" => to_string(context.other_city.id)})
        assert has_element?(context.other_play_live, "[data-test='city-panel']")
        assert has_element?(context.other_play_live, "[data-test='city-status']", "occupied")
        {:ok, context}
      end
    end
  end
end
