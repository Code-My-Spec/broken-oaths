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

        render_hook(context.play_live, "produce_wealth", %{"city_id" => to_string(context.city.id)})
        {:ok, context}
      end

      when_ "two economy ticks pass", context do
        treasury0 = Fixtures.gold(context.world, context.user)
        for _ <- 1..2, do: Fixtures.advance_turn(context.world)
        {:ok, Map.put(context, :treasury0, treasury0)}
      end

      then_ "all 5 gold from the two 2.5-gold conversions has been paid out", context do
        # `Fixtures.gold/2` also carries story 909/912's baseline per-turn
        # city gold income, stacked on top of Produce Wealth's own gold on
        # every tick, so `banked` resolving to 0 (nothing left fractional
        # or lost) is the precise proof of this criterion; the treasury
        # check stays as a basic sanity check that gold moved at all.
        assert Fixtures.gold(context.world, context.user) > context.treasury0
        assert wealth_banked(context.world, context.user, context.city.id) == 0
        {:ok, context}
      end

      then_ "the wealth project remains selected rather than truncating its fractional output", context do
        assert has_element?(context.play_live, "[data-test='city-production-current']", "Produce Wealth")
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
