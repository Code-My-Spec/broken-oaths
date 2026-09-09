defmodule BrokenOathsSpex.Story950.Criterion2745Spex do
  @moduledoc """
  Story 950 — Build road to a destination
  Criterion 2745 — a worker builds a multi-tile road one segment at a time,
  with each segment taking the ordinary road build time.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a worker lays road segment by segment over time" do
    scenario "a worker executes a build-road-to order over a multi-tile route" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player has researched The Wheel and selected a worker for a road-to order", context do
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

      when_ "the player issues the build-road-to order and turns progress", context do
        render_hook(context.play_live, "arm_road_mode", %{"unit_id" => to_string(context.worker.id)})

        # The road-to target must exclude every unit's own current tile —
        # not just the worker's — since the player's lord starts standing
        # at/near the founded city too. RoadBuilder's step-collision check
        # treats ANY occupant (even the player's own lord) as blocking and
        # cancels the whole order outright on its first tick, so a target
        # that happened to coincide with the lord's tile would silently
        # drop the order before this scenario ever got to observe it.
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

        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the worker is building one road segment on its route", context do
        assert has_element?(context.play_live, "[data-test='unit-order']", "Building road to tile")
        {:ok, context}
      end

      then_ "the next segment waits for the current segment's normal build time", context do
        assert has_element?(context.play_live, "[data-test='cancel-road-build']")
        {:ok, context}
      end
    end
  end
end
