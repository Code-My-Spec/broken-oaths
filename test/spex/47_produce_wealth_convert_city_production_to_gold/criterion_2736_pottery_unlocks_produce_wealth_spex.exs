defmodule BrokenOathsSpex.Story949.Criterion2736Spex do
  @moduledoc """
  Story 949 — Produce Wealth
  Criterion 2736 — completing Pottery unlocks Produce Wealth in a city's
  production panel.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Pottery unlocks Produce Wealth" do
    scenario "a player completes Pottery before opening their city's production panel" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player has researched Pottery", context do
        render_hook(context.play_live, "toggle_tech_panel", %{})
        render_hook(context.play_live, "select_research", %{"tech" => "pottery"})
        for _ <- 1..25, do: Fixtures.advance_turn(context.world)

        {:ok, context}
      end

      when_ "they open the city's production panel", context do
        render_hook(context.play_live, "select_city", %{"city_id" => to_string(context.city.id)})
        {:ok, context}
      end

      then_ "Produce Wealth is available to select", context do
        assert has_element?(
                 context.play_live,
                 "[data-test='production-option-produce_wealth'][data-disabled='false']",
                 "Produce Wealth"
               )

        {:ok, context}
      end
    end
  end
end
