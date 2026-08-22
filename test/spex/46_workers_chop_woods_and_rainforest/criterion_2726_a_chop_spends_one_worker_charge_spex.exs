defmodule BrokenOathsSpex.Story948.Criterion2726Spex do
  @moduledoc """
  Story 948 — Workers chop woods and rainforest
  Criterion 2726 — a chop spends exactly one of the worker's own build
  charges (`validate_chop_charges/1` reads `unit.charges`, and a
  successful chop decrements it by one, the same "build charge" pool
  Improvement builds/pillage-repair share).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "A chop spends one worker charge" do
    scenario "the worker's own charge count drops by exactly one after a chop" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "a worker stands on a woods tile in the city's own territory, Mining researched",
             context do
        [city] = Fixtures.player_cities(context.world, context.user)

        render_hook(context.play_live, "queue_production", %{
          "city_id" => city.id,
          "item" => "worker"
        })

        Enum.reduce_while(1..30, :ok, fn _, :ok ->
          if Enum.any?(Fixtures.player_units(context.world, context.user), &(&1.type == :worker)) do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [worker] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :worker, do: u

        render_hook(context.play_live, "toggle_tech_panel", %{})
        render_hook(context.play_live, "select_research", %{"tech" => "mining"})

        Enum.reduce_while(1..60, :ok, fn _, :ok ->
          if has_element?(context.play_live, "[data-test='tech-completed-mining']") do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        woods? = fn t ->
          Fixtures.tile_class(context.world, t) == :land and t in city.territory and
            Fixtures.tile_terrain(context.world, t).feature in [:woods, :rainforest]
        end

        woods_tile = Enum.find(city.territory, woods?)

        assert woods_tile,
               "expected a woods/rainforest tile inside the founded city's own territory"

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => worker.id,
          "to_tile" => woods_tile
        })

        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [w] = for u <- Fixtures.player_units(context.world, context.user), u.id == worker.id, do: u

          if w.tile_id == woods_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [worker_before] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == worker.id, do: u

        {:ok,
         context
         |> Map.put(:worker, worker)
         |> Map.put(:charges_before, Map.get(worker_before, :charges, 3))}
      end

      when_ "the worker chops the tile", context do
        render_hook(context.play_live, "chop", %{"unit_id" => context.worker.id})
        {:ok, context}
      end

      then_ "the worker's own charges dropped by exactly one", context do
        [worker_after] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.worker.id,
              do: u

        assert Map.get(worker_after, :charges, 3) == context.charges_before - 1
        {:ok, context}
      end
    end
  end
end
