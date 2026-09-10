defmodule BrokenOathsSpex.Story949.Criterion2738Spex do
  @moduledoc """
  Story 949 — Produce Wealth
  Criterion 2738 — a city whose production is halted by pillaging cannot
  select or earn gold from Produce Wealth.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a pillaged city cannot produce wealth" do
    scenario "a city is pillaged while Produce Wealth is selected" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player has researched Pottery and selected Produce Wealth", context do
        render_hook(context.play_live, "toggle_tech_panel", %{})
        render_hook(context.play_live, "select_research", %{"tech" => "pottery"})
        for _ <- 1..25, do: Fixtures.advance_turn(context.world)

        render_hook(context.play_live, "produce_wealth", %{"city_id" => to_string(context.city.id)})
        {:ok, context}
      end

      when_ "the city is pillaged and an economy tick passes", context do
        render_hook(context.play_live, "pillage_city", %{"city_id" => to_string(context.city.id)})
        treasury0 = Fixtures.gold(context.world, context.user)
        Fixtures.advance_turn(context.world)
        {:ok, Map.put(context, :treasury0, treasury0)}
      end

      then_ "the production halt prevents Produce Wealth from adding gold", context do
        assert Fixtures.gold(context.world, context.user) == context.treasury0
        {:ok, context}
      end

      then_ "the city panel shows that its production is halted", context do
        assert has_element?(context.play_live, "[data-test='city-production-halted']")
        {:ok, context}
      end
    end
  end
end
