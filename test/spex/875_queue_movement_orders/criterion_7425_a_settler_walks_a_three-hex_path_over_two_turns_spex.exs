defmodule BrokenOathsSpex.Story875.Criterion7425Spex do
  @moduledoc """
  Story 875 — Queue Movement Orders
  Criterion 7425 — a queued multi-hex path renders and resolves across turns at the unit's movement rate.

  The globe board has no tile DOM; orders travel as LiveView events
  (render_hook) and results come back as pushed payloads and unit
  positions — per the board doctrine.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a settler walks a three-hex path over two turns" do
    scenario "the path renders, then resolves two hexes and one hex" do
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

      given_ "a passable multi-hex path target is known", context do
        land? = fn tile -> Fixtures.tile_class(context.world, tile) == :land end

        units = Fixtures.player_units(context.world, context.user)
        [unit | _] = for u <- units, u.type == :settler, do: u
        occupied = for u <- units, do: u.tile_id

        step = fn from, exclude ->
          context.world
          |> Fixtures.adjacent_tiles(from)
          |> Enum.reject(&(&1 in exclude or &1 in occupied))
          |> Enum.filter(land?)
          |> List.first()
        end

        t1 = step.(unit.tile_id, [])
        t2 = step.(t1, [unit.tile_id])
        t3 = step.(t2, [unit.tile_id, t1])

        {:ok, context |> Map.put(:unit, unit) |> Map.put(:path, [t1, t2, t3])}
      end

      when_ "the player queues the three-hex path", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.unit.id,
          "to_tile" => List.last(context.path)
        })

        {:ok, context}
      end

      then_ "the queued path is pushed to the board", context do
        assert_push_event(context.play_live, "game:path", %{unit_id: _, tiles: _})
        {:ok, context}
      end

      then_ "the settler advances two hexes at the first boundary and arrives at the second",
            context do
        [_t1, t2, t3] = context.path

        Fixtures.advance_turn(context.world)

        [unit] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.unit.id,
              do: u

        assert unit.tile_id == t2

        Fixtures.advance_turn(context.world)

        [unit] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.unit.id,
              do: u

        assert unit.tile_id == t3
        {:ok, context}
      end
    end
  end
end
