defmodule BrokenOathsSpex.Story895.Criterion7576Spex do
  @moduledoc """
  Story 895 — City Defense and Garrison
  Criterion 7576 — civilians (Settler, Worker) shelter on a city tile
  for free: they neither count against the 3-military-unit cap
  (criteria 7563/7564) nor add to the city's defensive strength
  (criterion 7562's formula only credits garrison *defense*, and
  civilians have none).

  Setup duplicates criterion 7563's three-warrior garrison exactly —
  see that file's moduledoc for the military/civilian split. A Worker
  is produced and walked onto the already-full tile as the civilian
  under test (a Settler is unavailable for this purpose: founding
  consumes it immediately, criterion 7463).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "room in the walls for the meek" do
    scenario "a worker settles onto an already-full city tile without being refused or adding defense" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a city already garrisoned by three warriors, with a worker produced and free nearby",
             context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        [city] = Fixtures.player_cities(context.world, context.user)

        render_hook(play_live, "queue_production", %{
          "city_id" => to_string(city.id),
          "item" => "warrior"
        })

        render_hook(play_live, "queue_production", %{
          "city_id" => to_string(city.id),
          "item" => "warrior"
        })

        render_hook(play_live, "queue_production", %{
          "city_id" => to_string(city.id),
          "item" => "warrior"
        })

        render_hook(play_live, "queue_production", %{
          "city_id" => to_string(city.id),
          "item" => "worker"
        })

        for _ <- 1..50, do: Fixtures.advance_turn(context.world)

        [w1, w2, w3] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        [worker] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :worker, do: u

        for warrior_id <- [w1.id, w2.id, w3.id] do
          garrison!(context.world, play_live, context.user, warrior_id, city.tile_id)
        end

        render_hook(play_live, "select_city", %{"city_id" => to_string(city.id)})
        defense_before = city_defense(play_live)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:worker, worker)
         |> Map.put(:defense_before, defense_before)}
      end

      when_ "the worker is ordered onto the same, already three-military-deep city tile", context do
        unless context.worker.tile_id == context.city.tile_id do
          render_hook(context.play_live, "queue_move", %{
            "unit_id" => to_string(context.worker.id),
            "to_tile" => context.city.tile_id
          })

          Enum.reduce_while(1..10, :ok, fn _, :ok ->
            [w] =
              for u <- Fixtures.player_units(context.world, context.user),
                  u.id == context.worker.id,
                  do: u

            if w.tile_id == context.city.tile_id do
              {:halt, :ok}
            else
              Fixtures.advance_turn(context.world)
              {:cont, :ok}
            end
          end)
        end

        {:ok, context}
      end

      then_ "the worker settles onto the tile without being refused", context do
        refute has_element?(context.play_live, "[data-test='order-error']")

        [worker] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == context.worker.id, do: u

        assert worker.tile_id == context.city.tile_id
        {:ok, context}
      end

      then_ "the city's defensive strength is unchanged by the worker's presence", context do
        render_hook(context.play_live, "select_city", %{"city_id" => to_string(context.city.id)})
        assert city_defense(context.play_live) == context.defense_before
        {:ok, context}
      end
    end
  end

  defp garrison!(world, play_live, owner, unit_id, to_tile) do
    render_hook(play_live, "queue_move", %{"unit_id" => to_string(unit_id), "to_tile" => to_tile})

    Enum.reduce_while(1..10, :ok, fn _, :ok ->
      [u] = for uu <- Fixtures.player_units(world, owner), uu.id == unit_id, do: uu

      if u.tile_id == to_tile do
        {:halt, :ok}
      else
        Fixtures.advance_turn(world)
        {:cont, :ok}
      end
    end)
  end

  defp city_defense(play_live) do
    html = render(play_live)
    [_, defense] = Regex.run(~r/data-test="city-defense"[^>]*>(\d+)/, html)
    String.to_integer(defense)
  end
end
