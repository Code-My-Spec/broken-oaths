defmodule BrokenOathsSpex.Story875.Criterion7426Spex do
  @moduledoc """
  Story 875 — Queue Movement Orders
  Criterion 7426 — a unit whose next step becomes occupied halts in place, keeps its interrupted path, and is never lost.

  The globe board has no tile DOM; orders travel as LiveView events
  (render_hook) and results come back as pushed payloads and unit
  positions — per the board doctrine.
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

      given_ "the settler's queued path runs through a tile the lord will take", context do
        land? = fn tile -> Fixtures.tile_class(context.world, tile) == :land end
        units = Fixtures.player_units(context.world, context.user)
        [settler | _] = for u <- units, u.type == :settler, do: u
        [lord | _] = for u <- units, u.type == :lord, do: u

        # Find a (shared, beyond) pair where `shared` is adjacent to both
        # units and `beyond` forces the settler's shortest path THROUGH
        # `shared`: beyond is adjacent to shared but NOT to the settler
        # (else BFS legitimately shortcuts around the collision).
        settler_adjacent = Fixtures.adjacent_tiles(context.world, settler.tile_id)

        shared_candidates =
          context.world
          |> Fixtures.adjacent_tiles(settler.tile_id)
          |> Enum.filter(land?)
          |> Enum.filter(&(&1 in Fixtures.adjacent_tiles(context.world, lord.tile_id)))

        {shared, beyond} =
          shared_candidates
          |> Enum.flat_map(fn sh ->
            context.world
            |> Fixtures.adjacent_tiles(sh)
            |> Enum.reject(&(&1 in [settler.tile_id, lord.tile_id] or &1 in settler_adjacent))
            |> Enum.filter(land?)
            |> Enum.map(&{sh, &1})
          end)
          |> List.first() ||
            raise "no (shared, beyond) pair exists for this seed — pick a different fixture seed"

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => settler.id,
          "to_tile" => beyond
        })

        render_hook(context.play_live, "queue_move", %{"unit_id" => lord.id, "to_tile" => shared})

        {:ok,
         context |> Map.put(:settler, settler) |> Map.put(:lord, lord) |> Map.put(:shared, shared)}
      end

      when_ "the turn resolves with the lord occupying the shared tile", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the settler halted without being lost, its path interrupted", context do
        units = Fixtures.player_units(context.world, context.user)
        [settler] = for u <- units, u.id == context.settler.id, do: u
        [lord] = for u <- units, u.id == context.lord.id, do: u

        assert lord.tile_id == context.shared or settler.tile_id == context.shared
        refute lord.tile_id == settler.tile_id

        render_hook(context.play_live, "select_unit", %{"unit_id" => context.settler.id})
        assert has_element?(context.play_live, "[data-test='order-interrupted']")
        {:ok, context}
      end
    end
  end
end
