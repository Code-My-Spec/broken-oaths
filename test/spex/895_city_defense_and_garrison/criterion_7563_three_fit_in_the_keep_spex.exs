defmodule BrokenOathsSpex.Story895.Criterion7563Spex do
  @moduledoc """
  Story 895 — City Defense and Garrison
  Criterion 7563 — up to three friendly military units may stand
  together on a city's own tile. This is the game's only stacking
  exception: everywhere else, `occupied_by_own?`
  (`lib/broken_oaths/game/world_server.ex`) refuses a player's own
  second unit onto a tile it already occupies.

  "Military" here means combat-capable unit types — `:lord` and
  `:warrior` — as opposed to the civilian `:settler`/`:worker` (see
  criterion 7576, "room in the walls for the meek", for the civilian
  side of this same cap).

  Three ordinary Warriors are produced and walked onto the city tile
  one at a time — each `queue_move` is a real order through
  `GameLive.Play`, not a fixture trick, so this also exercises
  whatever queue-time occupancy check ships alongside the city-tile
  exception.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "three fit in the keep" do
    scenario "three separately produced warriors all garrison on the same city tile" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a founded city and three warriors produced one after another", context do
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

        for _ <- 1..24, do: Fixtures.advance_turn(context.world)

        [w1, w2, w3] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:warrior_ids, [w1.id, w2.id, w3.id])}
      end

      when_ "each warrior is ordered onto the city's own tile in turn", context do
        for warrior_id <- context.warrior_ids do
          garrison!(context.world, context.play_live, context.user, warrior_id, context.city.tile_id)
        end

        {:ok, context}
      end

      then_ "all three warriors stand garrisoned on the city tile", context do
        garrisoned =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id in context.warrior_ids,
              u.tile_id == context.city.tile_id,
              do: u.id

        assert Enum.sort(garrisoned) == Enum.sort(context.warrior_ids)
        {:ok, context}
      end
    end
  end

  # Walks a single unit onto `to_tile`, advancing turn boundaries until
  # it arrives (or giving up after a generous bound, so a genuine
  # refusal shows up as a failed assertion downstream rather than an
  # infinite loop here).
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
end
