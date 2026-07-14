defmodule BrokenOathsSpex.Story875.Criterion7425Spex do
  @moduledoc """
  Story 875 — Queue Movement Orders
  Criterion 7425 — a queued multi-hex path executes immediately with
  available movement and completes after the boundary recharge.

  Model note (PM decision 2026-07-14): movement is immediate; the turn
  boundary recharges points and continues remaining paths. Assertions
  are route-agnostic — the server picks among equally short paths.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a settler walks a three-hex path over two turns" do
    scenario "two hexes now, the third after the recharge" do
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

      given_ "a destination exactly three hexes away is known", context do
        land? = fn tile -> Fixtures.tile_class(context.world, tile) == :land end
        units = Fixtures.player_units(context.world, context.user)
        [unit | _] = for u <- units, u.type == :settler, do: u
        occupied = MapSet.new(for u <- units, do: u.tile_id)

        # BFS levels over unoccupied land — mirrors the server's own
        # pathfinding, so distance-3 here is distance-3 there.
        grow = fn frontier, seen ->
          next =
            frontier
            |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
            |> Enum.uniq()
            |> Enum.reject(&(MapSet.member?(seen, &1) or MapSet.member?(occupied, &1)))
            |> Enum.filter(land?)

          {next, MapSet.union(seen, MapSet.new(next))}
        end

        seen = MapSet.new([unit.tile_id])
        {l1, seen} = grow.([unit.tile_id], seen)
        {l2, seen} = grow.(l1, seen)
        {l3, _seen} = grow.(l2, seen)

        [target | _] = l3
        {:ok, context |> Map.put(:unit, unit) |> Map.put(:target, target)}
      end

      when_ "the player queues the three-hex path", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.unit.id,
          "to_tile" => context.target
        })

        {:ok, context}
      end

      then_ "the queued path is pushed to the board", context do
        assert_push_event(context.play_live, "game:path", %{unit_id: _, tiles: _})
        {:ok, context}
      end

      then_ "the settler advances two hexes immediately and arrives after one recharge", context do
        # Immediate movement: both points spent the moment the order
        # lands — the settler now stands one hex short of the target.
        [unit] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == context.unit.id, do: u

        refute unit.tile_id == context.unit.tile_id
        assert unit.movement == 0
        assert context.target in Fixtures.adjacent_tiles(context.world, unit.tile_id)

        # The boundary recharges movement and the path completes
        Fixtures.advance_turn(context.world)

        [unit] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == context.unit.id, do: u

        assert unit.tile_id == context.target
        assert unit.order == nil
        {:ok, context}
      end
    end
  end
end
