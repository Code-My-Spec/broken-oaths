defmodule BrokenOathsSpex.Story883.Criterion7486Spex do
  @moduledoc """
  Story 883 — Settler Production and Expansion
  Criterion 7486 — a Settler costs 100 production, and completing one
  costs the producing city one population point at the moment it
  spawns.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a settler is paid for in people" do
    scenario "a size-2 city completes Settler production" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a size-2 city completing Settler production", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)

        Enum.reduce_while(1..60, :ok, fn _, :ok ->
          [c] = for cc <- Fixtures.player_cities(context.world, context.user), cc.id == city.id, do: cc
          if c.size >= 2 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "settler"})

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:city, city)}
      end

      when_ "the settler spawns", context do
        # Settler (100) at the flat 5/turn base rate (story 879) completes
        # in exactly 20 turns.
        for _ <- 1..20, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the city drops to size 1", context do
        [city] =
          for cc <- Fixtures.player_cities(context.world, context.user), cc.id == context.city.id, do: cc

        assert city.size == 1
        {:ok, context}
      end

      then_ "the settler stands ready with 2 movement", context do
        settlers =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        assert length(settlers) == 1
        [settler] = settlers
        assert settler.max_movement == 2
        assert settler.movement == 2
        {:ok, context}
      end
    end
  end
end
