defmodule BrokenOathsSpex.Story949.Criterion2732Spex do
  @moduledoc """
  Story 949 — Produce Wealth
  Criterion 2732 — Produce Wealth is selectable from the city production panel.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Produce Wealth appears as a selectable option in the city panel" do
    scenario "a player with Pottery views a city's production choices" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player has researched Pottery and opened their city panel", context do
        render_hook(context.play_live, "toggle_tech_panel", %{})
        render_hook(context.play_live, "select_research", %{"tech" => "pottery"})
        for _ <- 1..25, do: Fixtures.advance_turn(context.world)
        render_hook(context.play_live, "select_city", %{"city_id" => to_string(context.city.id)})

        {:ok, context}
      end

      when_ "they view the list of things the city can produce", context do
        {:ok, context}
      end

      then_ "Produce Wealth is listed alongside the available production items", context do
        assert has_element?(context.play_live, "[data-test='production-option-produce_wealth']", "Produce Wealth")
        assert has_element?(context.play_live, "[data-test='production-option-warrior']")
        {:ok, context}
      end

      then_ "they can select Produce Wealth as the city's current production", context do
        assert has_element?(context.play_live, "[data-test='production-option-produce_wealth'][data-disabled='false']")
        {:ok, context}
      end
    end
  end
end
