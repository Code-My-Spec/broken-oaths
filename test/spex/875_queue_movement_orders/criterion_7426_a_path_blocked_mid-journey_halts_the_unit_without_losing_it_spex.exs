defmodule BrokenOathsSpex.Story875.Criterion7426Spex do
  @moduledoc """
  Story 875 — Queue Movement Orders
  Criterion 7426 — a unit whose next step becomes occupied halts in
  place, keeps its interrupted path, and is never lost.

  Model note (PM decision 2026-07-14): movement is immediate; the
  boundary recharges. "Blocked mid-journey" = the walker exhausted its
  points partway, a blocker took its NEXT tile, and the recharge
  attempt hits the occupied step. The construction is confirmed against
  the server's own pushed path so route ambiguity can't fake it.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a path blocked mid-journey halts the unit without losing it" do
    scenario "a blocker moves in and the walker stops short" do
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

      given_ "the settler rests with no movement and a controlled next step", context do
        land? = fn tile -> Fixtures.tile_class(context.world, tile) == :land end
        units = Fixtures.player_units(context.world, context.user)
        [settler | _] = for u <- units, u.type == :settler, do: u
        [lord | _] = for u <- units, u.type == :lord, do: u
        occupied = MapSet.new(for u <- units, do: u.tile_id)

        # Burn the settler's movement on a two-hex walk so it rests with
        # zero points; later queues just replace its pending path.
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
        {l2, _} = grow.(l1, seen)
        [burn | _] = l2

        render_hook(context.play_live, "queue_move", %{"unit_id" => settler.id, "to_tile" => burn})
        assert_push_event(context.play_live, "game:path", %{tiles: _})

        [settler_now] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == settler.id, do: u

        assert settler_now.movement == 0

        # Find (next_step, dest) DETERMINISTICALLY: next_step adjacent to
        # both the resting settler and the lord; dest one hex beyond,
        # not adjacent to the settler, and — crucially — next_step is the
        # ONLY unoccupied land tile adjacent to both settler and dest,
        # so the server's shortest path can only be [next_step, dest].
        settler_adj = Fixtures.adjacent_tiles(context.world, settler_now.tile_id)
        lord_adj = Fixtures.adjacent_tiles(context.world, lord.tile_id)

        passable = fn tile ->
          land?.(tile) and tile != lord.tile_id and tile != settler_now.tile_id
        end

        {n3, dest} =
          Enum.find_value(settler_adj, fn n3 ->
            with true <- n3 in lord_adj,
                 true <- passable.(n3),
                 dest when not is_nil(dest) <-
                   context.world
                   |> Fixtures.adjacent_tiles(n3)
                   |> Enum.filter(passable)
                   |> Enum.reject(&(&1 in settler_adj))
                   |> Enum.find(fn dest ->
                     common =
                       context.world
                       |> Fixtures.adjacent_tiles(dest)
                       |> Enum.filter(&(&1 in settler_adj))
                       |> Enum.filter(passable)

                     common == [n3]
                   end) do
              {n3, dest}
            else
              _ -> nil
            end
          end) ||
            raise "no blockable construction exists for this seed — pick a different fixture seed"

        render_hook(context.play_live, "queue_move", %{"unit_id" => settler.id, "to_tile" => dest})

        # The lord claims the settler's pending next step immediately.
        render_hook(context.play_live, "queue_move", %{"unit_id" => lord.id, "to_tile" => n3})

        context =
          context
          |> Map.put(:settler, settler)
          |> Map.put(:lord, lord)
          |> Map.put(:resting_tile, settler_now.tile_id)
          |> Map.put(:next_step, n3)

        {:ok, context}
      end

      when_ "the boundary recharges and the settler tries its next step", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the settler halted without being lost, its path interrupted", context do
        units = Fixtures.player_units(context.world, context.user)
        [settler] = for u <- units, u.id == context.settler.id, do: u
        [lord] = for u <- units, u.id == context.lord.id, do: u

        assert lord.tile_id == context.next_step
        assert settler.tile_id == context.resting_tile
        refute lord.tile_id == settler.tile_id

        render_hook(context.play_live, "select_unit", %{"unit_id" => context.settler.id})
        assert has_element?(context.play_live, "[data-test='order-interrupted']")
        {:ok, context}
      end
    end
  end
end
