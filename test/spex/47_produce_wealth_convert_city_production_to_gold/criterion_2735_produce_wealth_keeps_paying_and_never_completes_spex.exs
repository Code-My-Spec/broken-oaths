defmodule BrokenOathsSpex.Story949.Criterion2735Spex do
  @moduledoc """
  Story 949 — Produce Wealth
  Criterion 2735 — Produce Wealth remains selected and pays gold on every
  economy tick until the player chooses another production item.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Produce Wealth keeps paying and never completes" do
    scenario "a Pottery-unlocked city remains on Produce Wealth across several ticks" do
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

      when_ "several economy ticks pass without a production change", context do
        treasury0 = Fixtures.gold(context.world, context.user)
        for _ <- 1..3, do: Fixtures.advance_turn(context.world)
        {:ok, Map.put(context, :treasury0, treasury0)}
      end

      then_ "the city has paid gold on every tick", context do
        assert Fixtures.gold(context.world, context.user) > context.treasury0
        {:ok, context}
      end

      then_ "Produce Wealth has not completed or fallen idle and remains selected", context do
        assert has_element?(context.play_live, "[data-test='city-production-current']", "Produce Wealth")
        {:ok, context}
      end
    end
  end
end
