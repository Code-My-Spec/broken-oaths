defmodule BrokenOathsSpex.Story949.Criterion2737Spex do
  @moduledoc """
  Story 949 — Produce Wealth
  Criterion 2737 — Produce Wealth is hidden until Pottery is researched.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "Produce Wealth is hidden before Pottery" do
    scenario "a player without Pottery opens a city's production panel" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      when_ "they open the city's production panel before researching Pottery", context do
        render_hook(context.play_live, "select_city", %{"city_id" => to_string(context.city.id)})
        {:ok, context}
      end

      then_ "Produce Wealth is not offered as a selectable option", context do
        assert has_element?(context.play_live, "[data-test='production-option-warrior']")
        refute has_element?(context.play_live, "[data-test='production-option-produce_wealth']")
        {:ok, context}
      end
    end
  end
end
