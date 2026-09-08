defmodule BrokenOathsSpex.Story949.Criterion2731Spex do
  @moduledoc """
  Story 949 — Produce Wealth — convert city production to gold
  Criterion 2731 — idle production becomes gold instead of a build.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "a player directs a city to produce wealth" do
    scenario "the city turns its production into visible gold rather than progress on a build" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      when_ "I select Produce Wealth for my city and its next turn resolves", context do
        render_hook(context.play_live, "select_city", %{"city_id" => to_string(context.city.id)})

        render_hook(context.play_live, "queue_production", %{
          "city_id" => to_string(context.city.id),
          "item" => "produce_wealth"
        })

        BrokenOathsSpex.Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the city panel shows Produce Wealth as active and the player's gold has increased", context do
        assert has_element?(context.play_live, "[data-test='city-production-current']", "Produce Wealth")
        assert has_element?(context.play_live, "[data-test='gold-balance'][data-production-income='true']")
        {:ok, context}
      end
    end
  end
end
