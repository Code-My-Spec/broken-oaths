defmodule BrokenOathsSpex.Story948.Criterion2722Spex do
  @moduledoc """
  Story 948 — Workers chop woods and rainforest
  Criterion 2722 — chopping a woods tile drops its movement cost (2 ->
  1, the same difficult-terrain discount a completed Road gives) and
  removes the woods yield modifier — observed through the terrain
  struct itself (`feature: :woods -> feature: nil`, the single fact
  both the movement-cost table and the yield table key off) and through
  an ordinary (non-Scout) unit's real movement cost entering the tile
  after the chop.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Chopping woods drops the tile's movement cost and removes the woods yield modifier" do
    scenario "the tile loses its woods feature and costs an ordinary unit only 1 movement afterward" do
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

        adjacent_land =
          context.world
          |> Fixtures.adjacent_tiles(woods_tile)
          |> Enum.find(&(Fixtures.tile_class(context.world, &1) == :land and &1 != woods_tile))

        assert adjacent_land, "expected an adjacent land tile to stage a second unit on"

        render_hook(context.play_live, "queue_production", %{
          "city_id" => city.id,
          "item" => "warrior"
        })

        Enum.reduce_while(1..40, :ok, fn _, :ok ->
          if Enum.any?(Fixtures.player_units(context.world, context.user), &(&1.type == :warrior)) do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        :ok = Fixtures.relocate_unit(context.world, warrior.id, adjacent_land)

        {:ok,
         context
         |> Map.put(:worker, worker)
         |> Map.put(:warrior, warrior)
         |> Map.put(:woods_tile, woods_tile)}
      end

      when_ "the worker chops the woods tile", context do
        render_hook(context.play_live, "chop", %{"unit_id" => context.worker.id})
        {:ok, context}
      end

      then_ "the tile's feature is gone — the same fact both movement cost and yield read", context do
        terrain = Fixtures.tile_terrain(context.world, context.woods_tile)
        refute terrain.feature in [:woods, :rainforest]
        {:ok, context}
      end

      then_ "an ordinary unit now enters the cleared tile for only 1 movement, not 2", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.warrior.id,
          "to_tile" => context.woods_tile
        })

        [warrior_after] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        assert warrior_after.tile_id == context.woods_tile
        assert warrior_after.movement == context.warrior.movement - 1

        {:ok, context}
      end
    end
  end
end
