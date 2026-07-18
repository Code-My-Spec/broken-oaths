defmodule BrokenOathsSpex.Story882.Criterion7709Spex do
  @moduledoc """
  Story 882 — Worker Improves Terrain
  Criterion 7709 — playtest update (issue 1caa87e9, worker build
  charges): building a Road never consumes a build charge — Roads are
  charge-exempt, matching Civ 6 (Traders/automatic road-laying handle
  roads there, not Builders).

  Gets to "a worker with 2 build charges left" by completing one real
  Farm first (spending charge 3 -> 2, same completion path criterion
  7698 exercises), then relocates to a second tile
  (`Fixtures.relocate_unit/3`, the same sanctioned teleport used
  throughout this batch's own multi-site scenarios) and builds a Road
  there — the SUBJECT here is "does a Road spend a charge," not how
  the worker got to 2 in the first place.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "roads are free of charge" do
    scenario "a worker with 2 build charges completes a Road" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a worker with 2 build charges left", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)

        {:ok, player} = Fixtures.join_world(context.world, context.user)

        occupied =
          for u <- Fixtures.player_units(context.world, context.user), do: u.tile_id

        [farm_tile, road_tile] = farmland_tiles(context.world, [city.tile_id | occupied], 2)

        worker = Fixtures.spawn_unit(context.world, player.id, :worker, farm_tile)
        assert worker.charges == 3

        render_hook(play_live, "select_unit", %{"unit_id" => worker.id})
        render_hook(play_live, "start_improvement", %{"unit_id" => worker.id, "kind" => "farm"})
        for _ <- 1..3, do: Fixtures.advance_turn(context.world)

        assert Fixtures.tile_improvement(context.world, farm_tile) == :farm

        [worker_after_farm] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == worker.id, do: u

        assert worker_after_farm.charges == 2

        :ok = Fixtures.relocate_unit(context.world, worker.id, road_tile)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:worker, worker)
         |> Map.put(:road_tile, road_tile)}
      end

      when_ "it completes a Road on a land tile", context do
        render_hook(context.play_live, "select_unit", %{"unit_id" => context.worker.id})

        render_hook(context.play_live, "start_improvement", %{
          "unit_id" => context.worker.id,
          "kind" => "road"
        })

        for _ <- 1..2, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the worker still has 2 build charges and can still build a Farm or Mine", context do
        assert Fixtures.tile_improvement(context.world, context.road_tile) == :road

        worker =
          Enum.find(
            Fixtures.player_units(context.world, context.user),
            &(&1.id == context.worker.id)
          )

        refute is_nil(worker)
        assert worker.charges == 2

        render_hook(context.play_live, "select_unit", %{"unit_id" => context.worker.id})
        assert has_element?(context.play_live, "[data-test='build-farm']")

        {:ok, context}
      end
    end
  end

  # `count` distinct flat, featureless grassland/plains tiles — legal
  # Farm ground and (like any land tile) also legal Road ground —
  # excluding whatever's already occupied.
  defp farmland_tiles(world, exclude, count) do
    land? = fn t -> Fixtures.tile_class(world, t) == :land end

    farmland? = fn t ->
      terrain = Fixtures.tile_terrain(world, t)
      terrain.relief == :flat and terrain.feature == nil and terrain.base in [:grassland, :plains]
    end

    0..(Fixtures.tile_count(world) - 1)
    |> Enum.filter(&(land?.(&1) and farmland?.(&1) and &1 not in exclude))
    |> Enum.take(count)
  end
end
