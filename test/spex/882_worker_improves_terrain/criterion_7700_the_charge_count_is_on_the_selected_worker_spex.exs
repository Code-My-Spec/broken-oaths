defmodule BrokenOathsSpex.Story882.Criterion7700Spex do
  @moduledoc """
  Story 882 — Worker Improves Terrain
  Criterion 7700 — playtest update (issue 1caa87e9, worker build
  charges): a selected worker shows how many build charges it has
  remaining, via `[data-test='unit-charges']` on `GameLive.UnitPanel`.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the charge count is on the selected worker" do
    scenario "a worker that has completed one Farm and has 2 charges left" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a worker that has completed one Farm and has 2 charges left", context do
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

        [tile] = farmland_tiles(context.world, [city.tile_id | occupied], 1)

        worker = Fixtures.spawn_unit(context.world, player.id, :worker, tile)
        assert worker.charges == 3

        render_hook(play_live, "select_unit", %{"unit_id" => worker.id})
        render_hook(play_live, "start_improvement", %{"unit_id" => worker.id, "kind" => "farm"})
        for _ <- 1..3, do: Fixtures.advance_turn(context.world)

        assert Fixtures.tile_improvement(context.world, tile) == :farm

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:worker, worker)}
      end

      when_ "the player selects that worker", context do
        render_hook(context.play_live, "select_unit", %{"unit_id" => context.worker.id})
        {:ok, context}
      end

      then_ "the worker panel shows \"2 charges\" remaining", context do
        assert has_element?(context.play_live, "[data-test='unit-charges']", "2 charges")
        {:ok, context}
      end
    end
  end

  # `count` distinct flat, featureless grassland/plains tiles — legal
  # Farm ground — excluding whatever's already occupied.
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
