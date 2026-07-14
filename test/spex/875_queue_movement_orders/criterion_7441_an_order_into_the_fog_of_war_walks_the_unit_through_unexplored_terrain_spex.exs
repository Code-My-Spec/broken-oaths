defmodule BrokenOathsSpex.Story875.Criterion7441Spex do
  @moduledoc """
  Story 875 — Queue Movement Orders
  Criterion 7441 — an order into the fog of war is legal: the client
  sends the clicked sphere point (its fog-filtered window can't name a
  tile it has never seen), the server resolves the tile, and the unit
  travels through unexplored terrain until it arrives.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "an order into the fog of war walks the unit through unexplored terrain" do
    scenario "right-clicking the shroud queues a move and the unit gets there" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player joined the world and is on the board", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        assert_push_event(play_live, "game:visibility", %{visible: visible, explored: explored})

        context =
          context
          |> Map.put(:play_live, play_live)
          |> Map.put(:known, MapSet.new(visible ++ explored))

        {:ok, context}
      end

      given_ "a land tile the player has never explored", context do
        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        land? = fn tile -> Fixtures.tile_class(context.world, tile) == :land end

        # BFS outward from the settler over land only, so the target is
        # guaranteed land-reachable; stop at the first tile under fog.
        find_fog_tile = fn find_fog_tile, frontier, seen ->
          next =
            frontier
            |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
            |> Enum.uniq()
            |> Enum.reject(&MapSet.member?(seen, &1))
            |> Enum.filter(land?)

          case Enum.find(next, &(not MapSet.member?(context.known, &1))) do
            nil when next == [] ->
              raise "no fog land tile reachable from the settler — bad fixture seed"

            nil ->
              find_fog_tile.(find_fog_tile, next, MapSet.union(seen, MapSet.new(next)))

            fog_tile ->
              fog_tile
          end
        end

        target = find_fog_tile.(find_fog_tile, [settler.tile_id], MapSet.new([settler.tile_id]))

        refute MapSet.member?(context.known, target)

        {:ok, context |> Map.put(:settler, settler) |> Map.put(:target, target)}
      end

      when_ "the player right-clicks that spot under the shroud", context do
        {x, y, z} = Fixtures.tile_center(context.world, context.target)

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.settler.id,
          "to_point" => [x, y, z]
        })

        assert_push_event(context.play_live, "game:path", %{tiles: _})
        {:ok, context}
      end

      then_ "turn boundaries carry the unit through the fog to the target", context do
        settler_now = fn ->
          [u] =
            for u <- Fixtures.player_units(context.world, context.user),
                u.id == context.settler.id,
                do: u

          u
        end

        # The order executed immediately with the settler's remaining
        # movement; each boundary recharges and continues. Bounded walk —
        # the order record disappears on arrival.
        final =
          Enum.reduce_while(1..15, settler_now.(), fn _turn, unit ->
            if unit.order == nil do
              {:halt, unit}
            else
              Fixtures.advance_turn(context.world)
              {:cont, settler_now.()}
            end
          end)

        assert final.order == nil
        assert final.tile_id == context.target
        {:ok, context}
      end
    end
  end
end
