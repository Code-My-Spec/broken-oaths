defmodule BrokenOathsSpex.Story949.Criterion2731Spex do
  @moduledoc """
  Story 949 — Produce Wealth
  Criterion 2731 — a Pottery-unlocked city converts 8 production into
  2 gold on the next economy tick instead of advancing a build.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "idle production becomes gold instead of a build" do
    scenario "a Pottery-unlocked city producing 8 production selects Produce Wealth" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player has researched Pottery and opened the city production panel", context do
        render_hook(context.play_live, "select_city", %{"city_id" => to_string(context.city.id)})
        render_hook(context.play_live, "toggle_tech_panel", %{})
        render_hook(context.play_live, "select_research", %{"tech" => "pottery"})
        for _ <- 1..25, do: Fixtures.advance_turn(context.world)

        {:ok, context}
      end

      when_ "the player selects Produce Wealth", context do
        render_hook(context.play_live, "produce_wealth", %{"city_id" => to_string(context.city.id)})
        treasury0 = Fixtures.gold(context.world, context.user)
        Fixtures.advance_turn(context.world)
        {:ok, Map.put(context, :treasury0, treasury0)}
      end

      then_ "the next economy tick adds 2 gold from the city's 8 production", context do
        assert Fixtures.gold(context.world, context.user) == context.treasury0 + 2
        {:ok, context}
      end

      then_ "the city has not advanced a unit or building build", context do
        assert has_element?(context.play_live, "[data-test='city-production-current']", "Produce Wealth")
        {:ok, context}
      end
    end
  end
end
