defmodule BrokenOathsSpex.Story879.Criterion7473Spex do
  @moduledoc """
  Story 879 — City Production Queue
  Criterion 7473 — queue edits are free, but canceling the in-progress
  item forfeits its invested production (PM decision: progress sticks
  to the item, not the city).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "reordering is free but abandoning mid-build costs the investment" do
    scenario "canceling a Settler at 60/100 with a Warrior queued behind it" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a city building a Settler at 60/100 with a Warrior queued behind it", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)

        # String id on purpose: real phx-value-* params are strings (QA issue a1c8741d).
        render_hook(play_live, "queue_production", %{"city_id" => to_string(city.id), "item" => "settler"})
        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "warrior"})

        # Flat 5/turn (story 879's own scope) reaches 60 in exactly 12 turns.
        for _ <- 1..12, do: Fixtures.advance_turn(context.world)

        [city] = for cc <- Fixtures.player_cities(context.world, context.user), cc.id == city.id, do: cc
        [current | _] = city.queue

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:settler_item, current)}
      end

      when_ "the player removes the Settler from the queue", context do
        render_hook(context.play_live, "cancel_production_item", %{
          "city_id" => context.city.id,
          "item_id" => context.settler_item.id
        })

        {:ok, context}
      end

      then_ "the Warrior becomes current at 0/40", context do
        [city] =
          for cc <- Fixtures.player_cities(context.world, context.user), cc.id == context.city.id, do: cc

        [current | _] = city.queue
        assert current.type == :warrior
        assert current.banked == 0
        assert current.cost == 40
        {:ok, context}
      end

      then_ "the 60 invested production is forfeited", context do
        [city] =
          for cc <- Fixtures.player_cities(context.world, context.user), cc.id == context.city.id, do: cc

        refute Enum.any?(city.queue, &(&1.type == :settler))
        {:ok, context}
      end
    end
  end
end
