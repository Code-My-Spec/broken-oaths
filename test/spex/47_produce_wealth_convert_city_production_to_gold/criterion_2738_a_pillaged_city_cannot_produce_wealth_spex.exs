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
        wealth_banked0 = wealth_banked(context.world, context.user, context.city.id)
        Fixtures.advance_turn(context.world)
        {:ok, Map.put(context, :wealth_banked0, wealth_banked0)}
      end

      then_ "the production halt prevents Produce Wealth from adding gold", context do
        # `Fixtures.gold/2` also carries story 909/912's baseline per-turn
        # city gold income (`Yields.city_gold_income/2`, unrelated to and
        # never halted by Produce Wealth's own pillage freeze), so the
        # wealth project's own `banked` progress is the precise thing this
        # criterion is actually about.
        assert wealth_banked(context.world, context.user, context.city.id) == context.wealth_banked0
        {:ok, context}
      end

      then_ "the city panel shows that its production is halted", context do
        assert has_element?(context.play_live, "[data-test='city-production-halted']")
        {:ok, context}
      end
    end
  end

  defp wealth_banked(world, user, city_id) do
    world
    |> Fixtures.player_cities(user)
    |> Enum.find(&(&1.id == city_id))
    |> Map.fetch!(:queue)
    |> hd()
    |> Map.fetch!(:banked)
  end
end
