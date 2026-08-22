defmodule BrokenOathsSpex.Story948.Criterion2725Spex do
  @moduledoc """
  Story 948 — Workers chop woods and rainforest
  Criterion 2725 — chop is ALLOWED on a feature inside the player's own
  borders: unlike Criterion2724 (outside territory, refused), a worker
  on a woods tile INSIDE its owner's own city territory can actually
  execute the chop — no `chop_error`, and the tile's feature is gone
  afterward.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Chop allowed on a feature inside the player's borders" do
    scenario "the chop succeeds with no error for a worker inside the city's own territory" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "a worker stands on a woods tile INSIDE the city's own territory, Mining researched",
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

        {:ok, context |> Map.put(:worker, worker) |> Map.put(:woods_tile, woods_tile)}
      end

      when_ "the worker chops the tile", context do
        render_hook(context.play_live, "chop", %{"unit_id" => context.worker.id})
        {:ok, context}
      end

      then_ "no chop error toast appears", context do
        refute has_element?(context.play_live, "[data-test='chop-error']")
        {:ok, context}
      end

      then_ "the tile's feature is gone, proving the chop actually executed", context do
        terrain = Fixtures.tile_terrain(context.world, context.woods_tile)
        refute terrain.feature in [:woods, :rainforest]
        {:ok, context}
      end
    end
  end
end
