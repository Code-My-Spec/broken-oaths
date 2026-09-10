defmodule BrokenOathsSpex.Story949.Criterion2733Spex do
  @moduledoc """
  Story 949 — Produce Wealth
  Criterion 2733 — switching to Produce Wealth pauses the current build
  and converts production to gold from the next turn.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "switching to Produce Wealth stops the current build" do
    scenario "a city switches from a partially progressed Warrior to Produce Wealth" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player has researched Pottery and the city is building a Warrior", context do
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

      when_ "the player switches the city to Produce Wealth", context do
        render_hook(context.play_live, "produce_wealth", %{"city_id" => to_string(context.city.id)})
        treasury0 = Fixtures.gold(context.world, context.user)
        Fixtures.advance_turn(context.world)
        {:ok, Map.put(context, :treasury0, treasury0)}
      end

      then_ "the city no longer advances the Warrior build", context do
        assert has_element?(context.play_live, "[data-test='city-production-current']", "Produce Wealth")
        {:ok, context}
      end

      then_ "its production is converted to gold from the next turn", context do
        assert Fixtures.gold(context.world, context.user) > context.treasury0
        {:ok, context}
      end
    end
  end
end
