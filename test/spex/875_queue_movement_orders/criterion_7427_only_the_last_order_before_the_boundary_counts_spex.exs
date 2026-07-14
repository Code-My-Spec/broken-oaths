defmodule BrokenOathsSpex.Story875.Criterion7427Spex do
  @moduledoc """
  Story 875 — Queue Movement Orders
  Criterion 7427 — orders are freely replaceable; only the latest
  remaining path executes.

  Model note (PM decision 2026-07-14): orders execute immediately with
  available movement, so replaceability is observed on a unit whose
  points are already spent — its queued orders wait for the recharge,
  and only the final replacement runs.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "only the last order before the boundary counts" do
    scenario "re-targeting replaces the earlier order" do
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

      given_ "the lord has spent all its movement this turn", context do
        land? = fn tile -> Fixtures.tile_class(context.world, tile) == :land end
        units = Fixtures.player_units(context.world, context.user)
        [unit | _] = for u <- units, u.type == :lord, do: u
        occupied = for u <- units, do: u.tile_id

        step = fn from, exclude ->
          context.world
          |> Fixtures.adjacent_tiles(from)
          |> Enum.reject(&(&1 in exclude or &1 in occupied))
          |> Enum.filter(land?)
          |> List.first()
        end

        # Burn the lord's movement with an immediate two-hex walk
        b1 = step.(unit.tile_id, [])
        b2 = step.(b1, [unit.tile_id])
        render_hook(context.play_live, "queue_move", %{"unit_id" => unit.id, "to_tile" => b2})

        [unit] = for u <- Fixtures.player_units(context.world, context.user), u.id == unit.id, do: u
        assert unit.movement == 0

        # Two different one-hop targets from its resting spot
        [first, second | _] =
          context.world
          |> Fixtures.adjacent_tiles(unit.tile_id)
          |> Enum.reject(&(&1 in occupied))
          |> Enum.filter(land?)

        {:ok, context |> Map.put(:unit, unit) |> Map.put(:first, first) |> Map.put(:second, second)}
      end

      when_ "the player queues one target, then replaces it before the boundary", context do
        render_hook(context.play_live, "queue_move", %{"unit_id" => context.unit.id, "to_tile" => context.first})
        render_hook(context.play_live, "queue_move", %{"unit_id" => context.unit.id, "to_tile" => context.second})

        # No movement left — neither order can execute yet
        [unit] = for u <- Fixtures.player_units(context.world, context.user), u.id == context.unit.id, do: u
        assert unit.tile_id == context.unit.tile_id

        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "after the recharge the unit followed the replacement target, never the first", context do
        [unit] = for u <- Fixtures.player_units(context.world, context.user), u.id == context.unit.id, do: u
        assert unit.tile_id == context.second
        {:ok, context}
      end
    end
  end
end
