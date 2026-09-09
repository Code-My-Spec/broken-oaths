defmodule BrokenOathsSpex.Story949.Criterion2739Spex do
  @moduledoc """
  Story 949 — Produce Wealth
  Criterion 2739 — the Produce Wealth card displays its estimated gold per
  turn, and choosing a normal production item deselects it.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the wealth card shows gold per turn and is deselected by another item" do
    scenario "a player changes a Pottery-unlocked city's production from wealth to a Warrior" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player has researched Pottery and opened the city production panel", context do
        render_hook(context.play_live, "toggle_tech_panel", %{})
        render_hook(context.play_live, "select_research", %{"tech" => "pottery"})
        for _ <- 1..25, do: Fixtures.advance_turn(context.world)
        render_hook(context.play_live, "select_city", %{"city_id" => to_string(context.city.id)})

        {:ok, context}
      end

      when_ "the player selects Produce Wealth and then selects a Warrior", context do
        render_hook(context.play_live, "produce_wealth", %{"city_id" => to_string(context.city.id)})

        render_hook(context.play_live, "queue_production", %{
          "city_id" => to_string(context.city.id),
          "item" => "warrior"
        })

        {:ok, context}
      end

      then_ "the Produce Wealth card shows its estimated gold per turn", context do
        assert has_element?(context.play_live, "[data-test='production-option-produce_wealth']", "gold/turn")
        {:ok, context}
      end

      then_ "the city switches to the Warrior without a separate wealth stop action", context do
        assert has_element?(context.play_live, "[data-test='city-production-current']", "Warrior")
        refute has_element?(context.play_live, "[data-test='city-production-current']", "Produce Wealth")
        {:ok, context}
      end
    end
  end
end
