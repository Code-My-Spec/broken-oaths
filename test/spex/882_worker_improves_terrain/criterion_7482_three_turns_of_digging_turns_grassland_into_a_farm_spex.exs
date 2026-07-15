defmodule BrokenOathsSpex.Story882.Criterion7482Spex do
  @moduledoc """
  Story 882 — Worker Improves Terrain
  Criterion 7482 — a Farm takes 3 turns on flat, featureless grassland
  or plains; Farm is not offered on hills or forested tiles.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "three turns of digging turns grassland into a farm" do
    scenario "farming flat land, then checking a forested tile refuses the option" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a worker standing on flat featureless grassland or plains", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)
        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "worker"})
        for _ <- 1..12, do: Fixtures.advance_turn(context.world)

        [worker] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :worker, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        flat_farmland =
          Fixtures.adjacent_tiles(context.world, city.tile_id)
          |> Enum.filter(land?)
          |> Enum.find(fn t ->
            terrain = Fixtures.tile_terrain(context.world, t)
            terrain.relief == :flat and terrain.feature == nil and terrain.base in [:grassland, :plains]
          end)

        forested_tile =
          Fixtures.adjacent_tiles(context.world, city.tile_id)
          |> Enum.filter(land?)
          |> Enum.find(fn t -> Fixtures.tile_terrain(context.world, t).feature == :woods end)

        render_hook(play_live, "queue_move", %{"unit_id" => worker.id, "to_tile" => flat_farmland})

        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [w] = for u <- Fixtures.player_units(context.world, context.user), u.id == worker.id, do: u

          if w.tile_id == flat_farmland do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:worker, worker)
         |> Map.put(:farmland_tile, flat_farmland)
         |> Map.put(:forested_tile, forested_tile)}
      end

      when_ "the player starts a Farm and three turn boundaries pass", context do
        render_hook(context.play_live, "select_unit", %{"unit_id" => context.worker.id})

        render_hook(context.play_live, "start_improvement", %{
          "unit_id" => context.worker.id,
          "kind" => "farm"
        })

        for _ <- 1..3, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the farm is complete on that tile", context do
        assert Fixtures.tile_improvement(context.world, context.farmland_tile) == :farm
        {:ok, context}
      end

      then_ "starting a Farm on a hills or forested tile is not offered", context do
        [worker] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == context.worker.id, do: u

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => worker.id,
          "to_tile" => context.forested_tile
        })

        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [w] = for u <- Fixtures.player_units(context.world, context.user), u.id == worker.id, do: u

          if w.tile_id == context.forested_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        render_hook(context.play_live, "select_unit", %{"unit_id" => worker.id})
        refute has_element?(context.play_live, "[data-test='build-farm']")
        {:ok, context}
      end
    end
  end
end
