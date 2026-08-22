defmodule BrokenOathsSpex.Story948.Criterion2729Spex do
  @moduledoc """
  Story 948 — Workers chop woods and rainforest
  Criterion 2729 — chopping a tile the city is currently WORKING
  reassigns its citizens by the next turn boundary: a chop doesn't drop
  the tile from the city's territory, but the terrain under a citizen's
  own worked assignment changed out from under them, so the panel's
  worked-tile listing for that exact tile should read differently
  (either the citizen has moved off it onto a different tile, or the
  row itself no longer reads as an active assignment) once a turn
  passes.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Chopping a tile the city is working reassigns its citizens next turn" do
    scenario "the worked-tile assignment on the chopped tile changes by the next turn" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player's city is founded with a choppable tile in its own ring (never the center — the center can never be manually worked, City.assign_worked_tile/5's own validate_assign/4 refuses it)",
             context do
        {:ok,
         found_city_with_enough_feature(context, 1, &(&1.feature in [:woods, :rainforest]))}
      end

      given_ "a worker stands ready, Mining is researched, and the city is WORKING a woods tile",
             context do
        city = context.city

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

        woods_tile =
          context.world
          |> Fixtures.adjacent_tiles(city.tile_id)
          |> Enum.find(&(Fixtures.tile_terrain(context.world, &1).feature in [:woods, :rainforest]))

        assert woods_tile,
               "expected a woods/rainforest tile inside the founded city's own ring (guaranteed by found_city_with_enough_feature/4)"

        # A size-1 city's ONE citizen slot is already spent: founding
        # auto-assigns a worked tile via `Yields.pick_worked_tile/2`
        # (`City.persist_found_city!/3`'s own doc — "a size-1 city
        # needs it from turn zero"). A bare add (`from_tile_id` absent)
        # would hit `validate_assign/4`'s `:size_exceeded` clause
        # (`length(worked_tiles) >= size`, 1 >= 1) — this must be a
        # SWAP off whatever's already auto-worked, which never trips
        # that clause.
        [city_before_assign] = Fixtures.player_cities(context.world, context.user)
        [auto_worked_tile | _] = city_before_assign.worked_tiles

        render_hook(context.play_live, "assign_worked_tile", %{
          "city_id" => city.id,
          "from_tile_id" => auto_worked_tile,
          "to_tile_id" => woods_tile
        })

        [city_working] = Fixtures.player_cities(context.world, context.user)

        assert woods_tile in city_working.worked_tiles,
               "expected the woods tile to be a real, driven worked-tile assignment before the chop"

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

        {:ok,
         context
         |> Map.put(:worker, worker)
         |> Map.put(:city_id, city.id)
         |> Map.put(:woods_tile, woods_tile)}
      end

      when_ "the worker chops the WORKED tile, then a turn boundary passes", context do
        render_hook(context.play_live, "chop", %{"unit_id" => context.worker.id})
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the chopped tile no longer sits in the city's worked-tile assignment", context do
        [city_after] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id == context.city_id,
            do: c

        refute context.woods_tile in city_after.worked_tiles,
               "expected the city to reassign its citizen off the chopped tile by the next turn"

        {:ok, context}
      end
    end
  end
end
