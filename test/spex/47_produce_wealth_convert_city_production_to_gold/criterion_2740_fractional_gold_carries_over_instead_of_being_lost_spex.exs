defmodule BrokenOathsSpex.Story949.Criterion2740Spex do
  @moduledoc """
  Story 949 — Produce Wealth
  Criterion 2740 — fractional gold from the 4:1 conversion carries across
  economy ticks until it becomes payable whole gold.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "fractional gold carries over instead of being lost" do
    scenario "a city producing 10 production per tick produces wealth for two ticks" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player has researched Pottery and set the 10-production city to Produce Wealth", context do
        render_hook(context.play_live, "toggle_tech_panel", %{})
        render_hook(context.play_live, "select_research", %{"tech" => "pottery"})
        for _ <- 1..25, do: Fixtures.advance_turn(context.world)

        # The city's own terrain-derived gold income (story 912) keeps
        # flowing every tick regardless of what's queued — Produce
        # Wealth converts production, not that separate income stream.
        # Baseline it over one plain tick BEFORE switching so the
        # `then_` step can isolate the wealth conversion's own
        # contribution from this same city's ordinary income.
        before_tick = Fixtures.gold(context.world, context.user)
        Fixtures.advance_turn(context.world)
        base_income_per_tick = Fixtures.gold(context.world, context.user) - before_tick

        render_hook(context.play_live, "produce_wealth", %{"city_id" => to_string(context.city.id)})
        {:ok, Map.put(context, :base_income_per_tick, base_income_per_tick)}
      end

      when_ "two economy ticks pass", context do
        treasury0 = Fixtures.gold(context.world, context.user)
        for _ <- 1..2, do: Fixtures.advance_turn(context.world)
        {:ok, Map.put(context, :treasury0, treasury0)}
      end

      then_ "all 5 gold from the two 2.5-gold conversions has been paid out, on top of the city's own ordinary income",
            context do
        expected = context.treasury0 + 2 * context.base_income_per_tick + 5
        assert Fixtures.gold(context.world, context.user) == expected
        {:ok, context}
      end

      then_ "the wealth project remains selected rather than truncating its fractional output", context do
        assert has_element?(context.play_live, "[data-test='city-production-current']", "Produce Wealth")
        {:ok, context}
      end
    end
  end
end
