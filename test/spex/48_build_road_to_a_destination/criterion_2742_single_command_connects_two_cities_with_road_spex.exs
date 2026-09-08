defmodule BrokenOathsSpex.Story950.Criterion2742Spex do
  @moduledoc """
  Story 950 — Build road to a destination
  Criterion 2742 — a single command connects two cities with a road.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "a player orders a worker to build a road to another city" do
    scenario "one destination command creates a continuous road connection" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      when_ "I select my worker and choose the second city as the road destination", context do
        render_hook(context.play_live, "select_city", %{"city_id" => to_string(context.city.id)})
        render_hook(context.play_live, "build_road_to", %{
          "city_id" => to_string(context.city.id)
        })

        {:ok, context}
      end

      then_ "the board shows a continuous road route from the worker's city to the destination city", context do
        assert has_element?(context.play_live, "[data-test='road-route'][data-connected='true']")
        assert has_element?(context.play_live, "[data-test='road-destination']")
        {:ok, context}
      end
    end
  end
end
