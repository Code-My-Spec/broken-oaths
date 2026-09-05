defmodule BrokenOathsSpex.Story955.Criterion2851Spex do
  @moduledoc """
  Story 955 — Library
  Criterion 2851 — a city cannot queue a Library before Writing is
  researched: without Writing complete, the production menu never
  offers a Library option at all (`Production.maybe_offer/3` omits it
  entirely, rather than showing it disabled).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "a city cannot queue a Library before Writing is researched" do
    scenario "no Library option is offered without Writing researched" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      when_ "the player views their city's production options", context do
        render_hook(context.play_live, "select_city", %{"city_id" => to_string(context.city.id)})
        {:ok, context}
      end

      then_ "no Library option is offered", context do
        refute has_element?(context.play_live, "[data-test='production-option-library']")

        {:ok, context}
      end

      then_ "the city's production panel still renders other options normally", context do
        assert has_element?(context.play_live, "[data-test='production-option-warrior']")

        {:ok, context}
      end
    end
  end
end
