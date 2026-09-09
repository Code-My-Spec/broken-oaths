defmodule BrokenOathsSpex.Story949.Criterion2741Spex do
  @moduledoc """
  Story 949 — Produce Wealth
  Criterion 2741 — switching a city to Produce Wealth preserves its
  partial build progress until that build is selected again.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a paused build keeps its progress across a Produce Wealth stint" do
    scenario "a city resumes a partially completed Warrior after producing wealth" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player has Pottery and the city has partial Warrior progress", context do
        render_hook(context.play_live, "toggle_tech_panel", %{})
        render_hook(context.play_live, "select_research", %{"tech" => "pottery"})
        for _ <- 1..25, do: Fixtures.advance_turn(context.world)

        render_hook(context.play_live, "queue_production", %{
          "city_id" => to_string(context.city.id),
          "item" => "warrior"
        })

        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      when_ "the player produces wealth for several ticks and then selects Warrior again", context do
        render_hook(context.play_live, "produce_wealth", %{"city_id" => to_string(context.city.id)})
        for _ <- 1..3, do: Fixtures.advance_turn(context.world)

        render_hook(context.play_live, "queue_production", %{
          "city_id" => to_string(context.city.id),
          "item" => "warrior"
        })

        {:ok, context}
      end

      then_ "the Warrior resumes with its earlier stored production intact", context do
        assert has_element?(context.play_live, "[data-test='city-production-current']", "Warrior")
        assert has_element?(context.play_live, "[data-test='city-production-progress'][value]:not([value='0'])")
        {:ok, context}
      end

      then_ "the earlier production was not forfeited during the wealth stint", context do
        refute has_element?(context.play_live, "[data-test='city-production-current']", "Produce Wealth")
        {:ok, context}
      end
    end
  end
end
