defmodule BrokenOathsSpex.Story874.Criterion7422Spex do
  @moduledoc """
  Story 874 — Automatic Turn Processing
  Criterion 7422 — orders execute immediately with available movement;
  the turn boundary recharges movement and continues remaining paths.
  (Model changed by PM 2026-07-14: real-time movement, boundary = recharge.)
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "orders execute immediately and the boundary recharges movement" do
    scenario "a move happens now; a long path continues after recharge" do
      given_ :a_world
      given_ :registered_player

      given_ "the player joined the world and is on the board", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :play_live, play_live)}
      end

      given_ "a four-hex passable walk is known", context do
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
        t4 = step.(t3, [unit.tile_id, t1, t2])

        {:ok, context |> Map.put(:unit, unit) |> Map.put(:walk, [t1, t2, t3, t4])}
      end

      when_ "the player queues the four-hex path", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.unit.id,
          "to_tile" => List.last(context.walk)
        })

        {:ok, context}
      end

      then_ "the unit has already moved its full movement — before any boundary", context do
        [_t1, t2 | _] = context.walk
        [unit] = for u <- Fixtures.player_units(context.world, context.user), u.id == context.unit.id, do: u
        assert unit.tile_id == t2
        assert unit.movement == 0
        {:ok, context}
      end

      then_ "the boundary recharges movement and the path continues", context do
        [_t1, _t2, _t3, t4] = context.walk
        Fixtures.advance_turn(context.world)
        [unit] = for u <- Fixtures.player_units(context.world, context.user), u.id == context.unit.id, do: u
        assert unit.tile_id == t4
        assert unit.movement == 0
        {:ok, context}
      end
    end
  end
end
