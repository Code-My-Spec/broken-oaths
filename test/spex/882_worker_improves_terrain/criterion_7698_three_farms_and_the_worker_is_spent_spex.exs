defmodule BrokenOathsSpex.Story882.Criterion7698Spex do
  @moduledoc """
  Story 882 — Worker Improves Terrain
  Criterion 7698 — playtest update (issue 1caa87e9, worker build
  charges): a worker spends one build charge for each Farm or Mine it
  completes, and is expended (removed from the map) the moment it
  spends its last charge. Drives the real `"start_improvement"`/
  `"cancel_improvement"`-sibling `"select_unit"` events through
  `GameLive.Play` for every build; positioning the worker between the
  three build sites uses `Fixtures.relocate_unit/3` (the same
  documented, sanctioned teleport `Criterion7641Spex` and many
  combat-story specs already use) rather than a real march — this
  criterion's SUBJECT is the charge count, not pathing, which criteria
  7482/7483 already cover on their own.

  The worker itself is placed with `Fixtures.spawn_unit/4` rather than
  waited-out through real Worker production — again, the SUBJECT here
  is "a worker with 3 build charges," not "how a worker comes to
  exist" (criterion 7697 already covers the fresh-from-production
  case).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "three farms and the worker is spent" do
    scenario "a worker completes three Farms across three tiles and is expended on the third" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a worker with 3 build charges standing on flat farmland", context do
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

        [tile_a, tile_b, tile_c] =
          farmland_tiles(context.world, [city.tile_id | occupied], 3)

        worker = Fixtures.spawn_unit(context.world, player.id, :worker, tile_a)
        assert worker.charges == 3

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:worker, worker)
         |> Map.put(:tile_a, tile_a)
         |> Map.put(:tile_b, tile_b)
         |> Map.put(:tile_c, tile_c)}
      end

      when_ "it completes a Farm on the first tile", context do
        render_hook(context.play_live, "select_unit", %{"unit_id" => context.worker.id})

        render_hook(context.play_live, "start_improvement", %{
          "unit_id" => context.worker.id,
          "kind" => "farm"
        })

        for _ <- 1..3, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the first Farm completes and the charge count drops from 3 to 2", context do
        assert Fixtures.tile_improvement(context.world, context.tile_a) == :farm

        worker = fetch_worker(context.world, context.user, context.worker.id)
        assert worker.charges == 2

        {:ok, context}
      end

      when_ "it moves to a second tile and completes another Farm", context do
        :ok = Fixtures.relocate_unit(context.world, context.worker.id, context.tile_b)

        render_hook(context.play_live, "select_unit", %{"unit_id" => context.worker.id})

        render_hook(context.play_live, "start_improvement", %{
          "unit_id" => context.worker.id,
          "kind" => "farm"
        })

        for _ <- 1..3, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the second Farm completes and the charge count drops from 2 to 1", context do
        assert Fixtures.tile_improvement(context.world, context.tile_b) == :farm

        worker = fetch_worker(context.world, context.user, context.worker.id)
        assert worker.charges == 1

        {:ok, context}
      end

      when_ "it moves to a third tile and completes a third Farm", context do
        :ok = Fixtures.relocate_unit(context.world, context.worker.id, context.tile_c)

        render_hook(context.play_live, "select_unit", %{"unit_id" => context.worker.id})

        render_hook(context.play_live, "start_improvement", %{
          "unit_id" => context.worker.id,
          "kind" => "farm"
        })

        for _ <- 1..3, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the worker is expended and removed, and all three Farms remain", context do
        assert Fixtures.tile_improvement(context.world, context.tile_c) == :farm

        refute fetch_worker(context.world, context.user, context.worker.id)

        assert Fixtures.tile_improvement(context.world, context.tile_a) == :farm
        assert Fixtures.tile_improvement(context.world, context.tile_b) == :farm
        assert Fixtures.tile_improvement(context.world, context.tile_c) == :farm

        {:ok, context}
      end
    end
  end

  defp fetch_worker(world, user, worker_id) do
    Enum.find(Fixtures.player_units(world, user), &(&1.id == worker_id))
  end

  # `count` distinct flat, featureless grassland/plains tiles — legal
  # Farm ground, same terrain gate `Criterion7482Spex`'s own inline
  # check uses — excluding whatever's already occupied (the city
  # center, the player's Lord).
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
