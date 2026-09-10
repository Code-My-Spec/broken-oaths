defmodule BrokenOathsSpex.Story950.Criterion2750Spex do
  @moduledoc """
  Story 950 — Build road to a destination
  Criterion 2750 — a worker cannot target a road destination outside its
  owner's borders.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "an out-of-border road target is rejected" do
    scenario "Wes targets a tile outside his territory" do
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

      when_ "they issue build-road-to targeting a tile outside their borders", context do
        render_hook(context.play_live, "arm_road_mode", %{"unit_id" => to_string(context.worker.id)})

        far1 = adjacent_land_tile(context.world, context.city.tile_id, [context.worker.tile_id])
        far2 = adjacent_land_tile(context.world, far1, [context.city.tile_id])
        far3 = adjacent_land_tile(context.world, far2, [far1])
        far4 = adjacent_land_tile(context.world, far3, [far2])
        target = adjacent_land_tile(context.world, far4, [far3])

        render_hook(context.play_live, "build_road_to", %{
          "unit_id" => to_string(context.worker.id),
          "to_tile" => to_string(target)
        })

        {:ok, context}
      end

      then_ "the road order is not accepted", context do
        assert has_element?(context.play_live, "[data-test='unit-order']", "No orders queued")
        {:ok, context}
      end

      then_ "the player is told that the destination must be inside their borders", context do
        assert has_element?(context.play_live, "[data-test='road-error']", "inside")
        {:ok, context}
      end
    end
  end
end
