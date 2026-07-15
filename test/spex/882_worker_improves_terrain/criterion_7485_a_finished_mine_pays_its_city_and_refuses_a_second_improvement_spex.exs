defmodule BrokenOathsSpex.Story882.Criterion7485Spex do
  @moduledoc """
  Story 882 — Worker Improves Terrain
  Criterion 7485 — a completed mine adds +2 production to whichever
  city works its tile, and a tile already holding an improvement
  refuses a second one.

  Uses the same bespoke seed-33 world as criterion 7484 for its hills
  tile (the default fixture seed has none — verified by scanning every
  tile of its 642-tile globe).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a finished mine pays its city and refuses a second improvement" do
    scenario "a completed mine's yield and a refused second dig" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a completed mine on a hills tile worked by a city", context do
        world = Fixtures.world_fixture(%{seed: 33})
        land? = fn t -> Fixtures.tile_class(world, t) == :land end

        hills_tile =
          Enum.find(0..(Fixtures.tile_count(world) - 1), fn t ->
            land?.(t) and Fixtures.tile_terrain(world, t).relief == :hills
          end)

        founding_tile = Fixtures.adjacent_tiles(world, hills_tile) |> Enum.find(land?)

        {:ok, join_live, _html} = live(context.conn, ~p"/play")
        join_live |> element("[data-test='join-world-#{world.id}']") |> render_click()
        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{world.id}")

        [settler | _] = for u <- Fixtures.player_units(world, context.user), u.type == :settler, do: u

        render_hook(play_live, "queue_move", %{"unit_id" => settler.id, "to_tile" => founding_tile})

        Enum.reduce_while(1..30, :ok, fn _, :ok ->
          [s] = for u <- Fixtures.player_units(world, context.user), u.id == settler.id, do: u
          if s.tile_id == founding_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(world)
            {:cont, :ok}
          end
        end)

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(world, context.user)
        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "worker"})
        for _ <- 1..12, do: Fixtures.advance_turn(world)

        [worker] = for u <- Fixtures.player_units(world, context.user), u.type == :worker, do: u

        render_hook(play_live, "queue_move", %{"unit_id" => worker.id, "to_tile" => hills_tile})

        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [w] = for u <- Fixtures.player_units(world, context.user), u.id == worker.id, do: u
          if w.tile_id == hills_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(world)
            {:cont, :ok}
          end
        end)

        # Work the tile UNIMPROVED first, to isolate the mine's own
        # contribution from the hills tile's raw terrain yield.
        [worked | _] = city.worked_tiles

        render_hook(play_live, "assign_worked_tile", %{
          "city_id" => city.id,
          "from_tile_id" => worked,
          "to_tile_id" => hills_tile
        })

        [before] = for cc <- Fixtures.player_cities(world, context.user), cc.id == city.id, do: cc
        [before_item | _] = before.queue
        Fixtures.advance_turn(world)
        [after_raw] = for cc <- Fixtures.player_cities(world, context.user), cc.id == city.id, do: cc
        [after_raw_item | _] = after_raw.queue
        raw_delta = after_raw_item.banked - before_item.banked

        render_hook(play_live, "select_unit", %{"unit_id" => worker.id})
        render_hook(play_live, "start_improvement", %{"unit_id" => worker.id, "kind" => "mine"})
        for _ <- 1..5, do: Fixtures.advance_turn(world)

        {:ok,
         context
         |> Map.put(:world_hw, world)
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:worker, worker)
         |> Map.put(:hills_tile, hills_tile)
         |> Map.put(:raw_delta, raw_delta)}
      end

      when_ "the next boundary's yields accrue", context do
        [before] =
          for cc <- Fixtures.player_cities(context.world_hw, context.user),
              cc.id == context.city.id,
              do: cc

        [before_item | _] = before.queue
        Fixtures.advance_turn(context.world_hw)

        [afterward] =
          for cc <- Fixtures.player_cities(context.world_hw, context.user),
              cc.id == context.city.id,
              do: cc

        [after_item | _] = afterward.queue
        mined_delta = after_item.banked - before_item.banked

        {:ok, Map.put(context, :mined_delta, mined_delta)}
      end

      then_ "the city's production income includes the mine's +2", context do
        assert context.mined_delta - context.raw_delta == 2
        {:ok, context}
      end

      then_ "a worker attempting a new improvement on that tile is refused", context do
        assert Fixtures.tile_improvement(context.world_hw, context.hills_tile) == :mine

        render_hook(context.play_live, "start_improvement", %{
          "unit_id" => context.worker.id,
          "kind" => "mine"
        })

        assert has_element?(context.play_live, "[data-test='improvement-error']")
        {:ok, context}
      end
    end
  end
end
