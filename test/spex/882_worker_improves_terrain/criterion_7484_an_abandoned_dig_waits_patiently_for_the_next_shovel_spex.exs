defmodule BrokenOathsSpex.Story882.Criterion7484Spex do
  @moduledoc """
  Story 882 — Worker Improves Terrain
  Criterion 7484 — build progress sticks to the tile; an interrupted
  build resumes where it left off when any of the owner's workers
  returns.

  Needs a hills tile (Mine, 5 turns) — the project's default fixture
  seed (424242) generates none anywhere on its 642-tile globe
  (verified by scanning every tile), so this spec uses a bespoke
  world (seed 33) known to contain one, the same way criterion 7490
  does for its forested-hills fact.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "an abandoned dig waits patiently for the next shovel" do
    scenario "a second worker resumes an interrupted mine" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a worker two turns into a five-turn mine", context do
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

        [worker1] = for u <- Fixtures.player_units(world, context.user), u.type == :worker, do: u

        render_hook(play_live, "queue_move", %{"unit_id" => worker1.id, "to_tile" => hills_tile})

        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [w] = for u <- Fixtures.player_units(world, context.user), u.id == worker1.id, do: u
          if w.tile_id == hills_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(world)
            {:cont, :ok}
          end
        end)

        render_hook(play_live, "select_unit", %{"unit_id" => worker1.id})
        render_hook(play_live, "start_improvement", %{"unit_id" => worker1.id, "kind" => "mine"})
        for _ <- 1..2, do: Fixtures.advance_turn(world)

        {:ok,
         context
         |> Map.put(:world_hw, world)
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:worker1, worker1)
         |> Map.put(:hills_tile, hills_tile)}
      end

      when_ "the worker walks away and later a different worker of the same player returns and resumes", context do
        away =
          Fixtures.adjacent_tiles(context.world_hw, context.hills_tile)
          |> Enum.find(&(Fixtures.tile_class(context.world_hw, &1) == :land))

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.worker1.id,
          "to_tile" => away
        })

        Fixtures.advance_turn(context.world_hw)

        render_hook(context.play_live, "queue_production", %{
          "city_id" => context.city.id,
          "item" => "worker"
        })

        for _ <- 1..12, do: Fixtures.advance_turn(context.world_hw)

        [worker2] =
          for u <- Fixtures.player_units(context.world_hw, context.user),
              u.type == :worker,
              u.id != context.worker1.id,
              do: u

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => worker2.id,
          "to_tile" => context.hills_tile
        })

        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [w] =
            for u <- Fixtures.player_units(context.world_hw, context.user), u.id == worker2.id, do: u

          if w.tile_id == context.hills_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world_hw)
            {:cont, :ok}
          end
        end)

        render_hook(context.play_live, "select_unit", %{"unit_id" => worker2.id})
        render_hook(context.play_live, "start_improvement", %{"unit_id" => worker2.id, "kind" => "mine"})

        {:ok, Map.put(context, :worker2, worker2)}
      end

      then_ "the mine is not yet complete right after resuming", context do
        refute Fixtures.tile_improvement(context.world_hw, context.hills_tile) == :mine
        {:ok, context}
      end

      then_ "the mine completes after three more boundaries, with no progress lost", context do
        for _ <- 1..3, do: Fixtures.advance_turn(context.world_hw)
        assert Fixtures.tile_improvement(context.world_hw, context.hills_tile) == :mine
        {:ok, context}
      end
    end
  end
end
