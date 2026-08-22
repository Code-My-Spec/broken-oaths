defmodule BrokenOathsSpex.Story948.Criterion2723Spex do
  @moduledoc """
  Story 948 — Workers chop woods and rainforest
  Criterion 2723 — a chopped tile becomes eligible for a Farm
  (`Improvement.allowed?(:farm, %Terrain{feature: nil, ...})` requires
  a flat, featureless grassland/plains tile — a woods/rainforest tile
  is never eligible until chopped). Observed the same way
  Criterion7628's mine-duration spec observes a finished improvement:
  drive `start_improvement`, then read the real completed state back.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Cleared tile becomes eligible for a Farm" do
    scenario "a Farm can be started on a woods tile only after it's been chopped" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "a worker stands on a grassland/plains woods tile in the city's own territory, Mining researched",
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

        farmable_woods? = fn t ->
          terrain = Fixtures.tile_terrain(context.world, t)

          Fixtures.tile_class(context.world, t) == :land and t in city.territory and
            terrain.feature in [:woods, :rainforest] and terrain.relief == :flat and
            terrain.base in [:grassland, :plains]
        end

        woods_tile = Enum.find(city.territory, farmable_woods?)

        assert woods_tile,
               "expected a flat grassland/plains woods tile (farm-eligible once cleared) inside the city's own territory"

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

        render_hook(context.play_live, "chop", %{"unit_id" => worker.id})

        {:ok, context |> Map.put(:worker, worker) |> Map.put(:woods_tile, woods_tile)}
      end

      when_ "the worker starts a Farm on the now-cleared tile", context do
        render_hook(context.play_live, "select_unit", %{"unit_id" => context.worker.id})

        render_hook(context.play_live, "start_improvement", %{
          "unit_id" => context.worker.id,
          "kind" => "farm"
        })

        {:ok, context}
      end

      then_ "the Farm eventually completes on the cleared tile", context do
        Enum.reduce_while(1..15, :ok, fn _, :ok ->
          if Fixtures.tile_improvement(context.world, context.woods_tile) == :farm do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        assert Fixtures.tile_improvement(context.world, context.woods_tile) == :farm,
               "expected the Farm to complete on the cleared tile"

        {:ok, context}
      end
    end
  end
end
