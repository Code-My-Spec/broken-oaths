defmodule BrokenOathsSpex.Story879.Criterion7469Spex do
  @moduledoc """
  Story 879 — City Production Queue
  Criterion 7469 — the city panel always shows the current production
  item with its banked progress against its cost.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "progress reads as banked-over-cost mid-build" do
    scenario "five turns into a Warrior (40) build" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a city five turns into building a Warrior (40)", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)

        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "warrior"})
        for _ <- 1..5, do: Fixtures.advance_turn(context.world)

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:city, city)}
      end

      when_ "the player opens the city panel", context do
        render_hook(context.play_live, "select_city", %{"city_id" => context.city.id})
        {:ok, context}
      end

      # 26, not a flat 25 (5 turns * flat-base-5): a freshly founded
      # size-1 city already works its center plus one assigned tile from
      # turn zero (story 878/880's `persist_found_city!/3`), and within
      # this scenario's 5 turns the city also grows to size 2, which
      # auto-assigns a second worked tile the same way founding does
      # (`Yields.pick_worked_tile/2`). Four turns bank the flat-5 rate
      # before growth lands, the fifth turn banks flat-5 plus the new
      # tile's +1 production: 4*5 + 6 = 26.
      then_ "the current production reads Warrior 26/40 with a progress bar", context do
        assert has_element?(context.play_live, "[data-test='city-production-current']", "26/40")
        assert has_element?(context.play_live, "[data-test='city-production-current']", "Warrior")
        assert has_element?(context.play_live, "[data-test='city-production-progress']")
        {:ok, context}
      end
    end
  end
end
