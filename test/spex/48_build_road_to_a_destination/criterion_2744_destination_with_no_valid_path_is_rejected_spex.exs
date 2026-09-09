defmodule BrokenOathsSpex.Story950.Criterion2744Spex do
  @moduledoc """
  Story 950 — Build road to a destination
  Criterion 2744 — an unreachable destination is rejected with no road order.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "an unreachable road destination is rejected" do
    scenario "a worker targets a destination with no valid land route" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player has founded a city whose territory ring includes a water tile", context do
        {:ok, found_city_with_water_in_ring(context)}
      end

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

      when_ "the player orders the worker to build a road across an unreachable route", context do
        # Unit.build_road_to/4's territory check runs BEFORE its pathfinding
        # one, so the target needs to be in-territory yet unreachable: the
        # water tile found_city_with_water_in_ring/1 planted in this city's
        # ring is in-territory (founding_territory/2 includes the whole ring
        # unconditionally) but has no land route a worker can walk (a plain
        # out-of-range id like -1 would instead hit the earlier :invalid_tile
        # guard, never reaching pathfinding at all).
        unreachable_tile =
          Enum.find(
            context.city.territory,
            &(Fixtures.tile_class(context.world, &1) in [:coastal_water, :deep_ocean])
          )

        render_hook(context.play_live, "arm_road_mode", %{"unit_id" => to_string(context.worker.id)})

        render_hook(context.play_live, "build_road_to", %{
          "unit_id" => to_string(context.worker.id),
          "to_tile" => to_string(unreachable_tile)
        })

        {:ok, context}
      end

      then_ "no road route is queued", context do
        assert has_element?(context.play_live, "[data-test='unit-order']", "No orders queued")
        {:ok, context}
      end

      then_ "the player is told the destination is unreachable", context do
        assert has_element?(context.play_live, "[data-test='road-error']", "unreachable")
        {:ok, context}
      end
    end
  end
end
