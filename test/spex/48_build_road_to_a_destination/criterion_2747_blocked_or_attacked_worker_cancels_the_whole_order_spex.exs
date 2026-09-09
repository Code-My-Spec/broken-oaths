defmodule BrokenOathsSpex.Story950.Criterion2747Spex do
  @moduledoc """
  Story 950 — Build road to a destination
  Criterion 2747 — a blocked or damaged worker cancels its entire road-to
  order rather than rerouting automatically.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a blocked or attacked worker cancels the whole road order" do
    scenario "a worker partway through a build-road-to order is blocked" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player has researched The Wheel and issued a road-to order", context do
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

        render_hook(context.play_live, "arm_road_mode", %{"unit_id" => to_string(worker.id)})

        render_hook(context.play_live, "build_road_to", %{
          "unit_id" => to_string(worker.id),
          "to_tile" => to_string(context.city.tile_id)
        })

        {:ok, Map.put(context, :worker, worker)}
      end

      when_ "the worker's next road tile becomes blocked and a turn passes", context do
        :ok = Fixtures.force_relocate_unit(context.world, context.worker.id, context.city.tile_id)
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the entire road-to order is cancelled and the worker stops building", context do
        assert has_element?(context.play_live, "[data-test='unit-order']", "No orders queued")
        {:ok, context}
      end

      then_ "the route is not automatically rerouted and must be issued again", context do
        refute has_element?(context.play_live, "[data-test='cancel-road-build']")
        {:ok, context}
      end
    end
  end
end
