defmodule BrokenOathsSpex.Story953.Criterion2788Spex do
  @moduledoc """
  Story 953 — Unit movement, pathfinding and turn resolution
  Criterion 2788 — `Units.Unit.bfs_path/5` steers away from a
  currently-occupied intermediate tile in favor of an equally-cheap
  free route, but happily plans a path all the way to an occupied
  destination — only the dynamic, tick-time collision check (not
  pathfinding) ever refuses a step onto an occupied tile.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a unit paths around an occupied hex but may still target an occupied destination" do
    scenario "two routes lead to the same destination; the blocked one is avoided, the busy destination is not refused" do
      given_(:a_world)
      given_(:registered_player)

      given_ "I have joined the world and opened the game board", context do
        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")
        {:ok, Map.put(context, :play_live, play_live)}
      end

      given_ "a blocked route hex, an open route hex, and an occupied destination two hexes away are known",
             context do
        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        ring1 = context.world |> Fixtures.adjacent_tiles(lord.tile_id) |> Enum.filter(land?)

        candidates =
          for m1 <- ring1,
              m2 <- ring1,
              m1 != m2,
              d <- Fixtures.adjacent_tiles(context.world, m1),
              d in Fixtures.adjacent_tiles(context.world, m2),
              d != lord.tile_id,
              d not in ring1,
              land?.(d),
              do: {m1, m2, d}

        {blocked_hex, open_hex, destination} =
          List.first(candidates) ||
            raise "no two-route construction exists near the lord for this seed"

        blocker = Fixtures.spawn_barbarian(context.world, blocked_hex)
        occupant = Fixtures.spawn_barbarian(context.world, destination)

        {:ok,
         context
         |> Map.put(:lord, lord)
         |> Map.put(:blocked_hex, blocked_hex)
         |> Map.put(:open_hex, open_hex)
         |> Map.put(:destination, destination)
         |> Map.put(:blocker, blocker)
         |> Map.put(:occupant, occupant)}
      end

      when_ "I order the mover onto the occupied destination", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.lord.id,
          "to_tile" => context.destination
        })

        {:ok, context}
      end

      then_ "the order is accepted and the mover routes through the open hex, never the blocked one",
            context do
        refute has_element?(context.play_live, "[data-test='order-error']")
        assert_push_event(context.play_live, "game:path", %{tiles: _})

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == context.lord.id,
            do: u

        refute lord.tile_id == context.blocked_hex
        assert lord.tile_id == context.open_hex
        assert lord.order.path == [context.destination]
        {:ok, context}
      end
    end
  end
end
