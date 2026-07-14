defmodule BrokenOathsSpex.Story875.Criterion7442Spex do
  @moduledoc """
  Story 875 — Queue Movement Orders
  Criterion 7442 — a queued order renders the pathway from the unit to
  its destination, and the rendered route stays current: re-selecting
  the unit mid-march shows only the steps still ahead, and arrival
  clears it.

  Truth surface is the "game:path" push (board doctrine — canvas paint
  is never asserted). Construction is route-agnostic: the target is
  found by BFS level over the same passable graph the server paths on,
  so only path LENGTHS and the destination are asserted, never a
  specific route.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a queued order's remaining path renders and shrinks as the unit walks" do
    scenario "queue, march a boundary, re-select, arrive" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player joined the world and is on the board", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :play_live, play_live)}
      end

      given_ "a land target exactly four steps from the settler", context do
        units = Fixtures.player_units(context.world, context.user)
        [settler | _] = for u <- units, u.type == :settler, do: u
        occupied = MapSet.new(for u <- units, do: u.tile_id)
        land? = fn tile -> Fixtures.tile_class(context.world, tile) == :land end

        # BFS levels over unoccupied land — the server's own path metric.
        grow = fn frontier, seen ->
          next =
            frontier
            |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
            |> Enum.uniq()
            |> Enum.reject(&(MapSet.member?(seen, &1) or MapSet.member?(occupied, &1)))
            |> Enum.filter(land?)

          {next, MapSet.union(seen, MapSet.new(next))}
        end

        seen = MapSet.new([settler.tile_id])
        {l1, seen} = grow.([settler.tile_id], seen)
        {l2, seen} = grow.(l1, seen)
        {l3, seen} = grow.(l2, seen)
        {l4, _seen} = grow.(l3, seen)
        [target | _] = l4

        {:ok, context |> Map.put(:settler, settler) |> Map.put(:target, target)}
      end

      when_ "the player queues the move", context do
        # Deliberately no prior select_unit: selection pushes an empty
        # game:path that would stale-match the arrival assertion below.
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.settler.id,
          "to_tile" => context.target
        })

        {:ok, context}
      end

      then_ "the pushed path runs from the unit to the destination", context do
        # The settler burst its 2 movement immediately — the rendered
        # route is the remaining 2 steps, ending at the destination.
        assert_push_event(context.play_live, "game:path", %{
          unit_id: unit_id,
          tiles: [_step | _] = tiles
        })

        assert unit_id == context.settler.id
        assert length(tiles) == 2
        assert List.last(tiles) == context.target
        {:ok, context}
      end

      then_ "re-selecting the unit re-renders the remaining route", context do
        render_hook(context.play_live, "select_unit", %{"unit_id" => context.settler.id})

        assert_push_event(context.play_live, "game:path", %{tiles: tiles})
        assert length(tiles) == 2
        assert List.last(tiles) == context.target
        {:ok, context}
      end

      then_ "arrival clears the rendered path", context do
        Fixtures.advance_turn(context.world)

        render_hook(context.play_live, "select_unit", %{"unit_id" => context.settler.id})
        assert_push_event(context.play_live, "game:path", %{tiles: tiles})
        assert tiles == []

        [settler_now] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.settler.id,
              do: u

        assert settler_now.tile_id == context.target
        assert settler_now.order == nil
        {:ok, context}
      end
    end
  end
end
