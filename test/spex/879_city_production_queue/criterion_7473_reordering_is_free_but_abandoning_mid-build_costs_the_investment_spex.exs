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

      given_ "a city building a Settler past 60 with a Warrior queued behind it", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)

        # A fresh city is size 1 and cannot queue a settler — grow it to
        # size 2 first so the premise holds STANDALONE (issue d965b3e4:
        # this spec used to depend on cross-file suite state).
        city_now = fn ->
          [cc] =
            for cc <- Fixtures.player_cities(context.world, context.user),
                cc.id == city.id,
                do: cc

          cc
        end

        Enum.reduce_while(1..12, nil, fn _, _ ->
          if city_now.().size >= 2, do: {:halt, :ok}, else: {:cont, Fixtures.advance_turn(context.world)}
        end)

        assert city_now.().size >= 2

        # Queue warrior FIRST, then settler — then exercise the free
        # reorder (story 879's rule) to bring the settler to the head.
        # String ids on purpose: real phx-value-* params are strings
        # (QA issue a1c8741d).
        render_hook(play_live, "queue_production", %{"city_id" => to_string(city.id), "item" => "warrior"})
        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "settler"})

        [%{type: :warrior} = warrior_item, %{type: :settler} = settler_item] = city_now.().queue

        render_hook(play_live, "reorder_production_item", %{
          "city_id" => to_string(city.id),
          "item_id" => to_string(settler_item.id)
        })

        [head, tail] = city_now.().queue
        assert head.id == settler_item.id
        assert tail.id == warrior_item.id
        assert tail.banked == warrior_item.banked

        # Bank past 60 on the settler (income = flat 5 + worked-tile
        # production, so the exact turn count varies by terrain — the
        # settler can never complete from below 60 in one tick).
        Enum.reduce_while(1..20, nil, fn _, _ ->
          [current | _] = city_now.().queue

          if current.type == :settler and current.banked >= 60,
            do: {:halt, :ok},
            else: {:cont, Fixtures.advance_turn(context.world)}
        end)

        [current | _] = city_now.().queue
        assert current.type == :settler
        assert current.banked >= 60 and current.banked < 100

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city_now.())
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
