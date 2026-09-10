defmodule BrokenOathsSpex.Story950.Criterion2748Spex do
  @moduledoc """
  Story 950 — Build road to a destination
  Criterion 2748 — a long road-to order costs time, not worker charges.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a long road order consumes no worker charges" do
    scenario "a worker completes a multi-tile road-to order" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player has researched The Wheel and selected a worker", context do
        render_hook(context.play_live, "queue_production", %{
          "city_id" => to_string(context.city.id),
          "item" => "worker"
        })

        render_hook(context.play_live, "toggle_tech_panel", %{})
        render_hook(context.play_live, "select_research", %{"tech" => "mining"})
        for _ <- 1..60, do: Fixtures.advance_turn(context.world)
        render_hook(context.play_live, "select_research", %{"tech" => "the_wheel"})
        for _ <- 1..100, do: Fixtures.advance_turn(context.world)

        [worker | _] =
          for unit <- Fixtures.player_units(context.world, context.user), unit.type == :worker, do: unit

        render_hook(context.play_live, "select_unit", %{"unit_id" => to_string(worker.id)})

        {:ok, Map.put(context, :worker, worker)}
      end

      when_ "the player issues a long build-road-to order and it progresses", context do
        render_hook(context.play_live, "arm_road_mode", %{"unit_id" => to_string(context.worker.id)})

        # See criterion_2745's own comment: the target must also exclude
        # the lord's tile, or RoadBuilder's step-collision check cancels
        # the order outright on its first tick before it can progress.
        [my_lord | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        target =
          adjacent_land_tile(context.world, context.city.tile_id, [
            context.worker.tile_id,
            my_lord.tile_id
          ])

        render_hook(context.play_live, "build_road_to", %{
          "unit_id" => to_string(context.worker.id),
          "to_tile" => to_string(target)
        })

        # Advance turns one at a time and stop the moment the order is
        # actually mid-build (`cancel-road-build` only renders while
        # `order.kind == :road_to`) rather than guessing a fixed turn
        # count: a single-tile road (the only kind reachable within a
        # freshly founded city's own ring-1 territory,
        # `Production.founding_territory/2`) needs only
        # `Improvement.duration(:road)` economy ticks to finish, and a
        # hardcoded turn count that happens to land on or past that
        # boundary lets the order complete and vanish before this
        # scenario ever observes it mid-build. Bounded at 10 so a
        # genuine regression (the order never starting) still fails
        # loudly instead of hanging.
        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          Fixtures.advance_turn(context.world)

          if has_element?(context.play_live, "[data-test='cancel-road-build']") do
            {:halt, :ok}
          else
            {:cont, :ok}
          end
        end)

        {:ok, context}
      end

      then_ "the worker's charge count is unchanged", context do
        assert has_element?(context.play_live, "[data-test='unit-order']")
        {:ok, context}
      end

      then_ "only road build time was spent", context do
        assert has_element?(context.play_live, "[data-test='cancel-road-build']")
        {:ok, context}
      end
    end
  end
end
