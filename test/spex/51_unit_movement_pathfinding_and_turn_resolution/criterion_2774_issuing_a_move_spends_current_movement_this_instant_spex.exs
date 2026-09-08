defmodule BrokenOathsSpex.Story953.Criterion2774Spex do
  @moduledoc """
  Story 953 — Unit movement, pathfinding and turn resolution
  Criterion 2774 — issuing a move spends current movement immediately:
  `Units.Unit.queue_move/4` resolves via `Turn.move_now/2` the instant
  it's issued, rather than waiting for the next turn boundary.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a player issues a unit movement order" do
    scenario "the unit moves immediately and its remaining movement is reduced before the next turn" do
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

      given_ "I control a unit and know an adjacent passable tile", context do
        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        to_tile = adjacent_land_tile(context.world, lord.tile_id)

        {:ok, context |> Map.put(:lord, lord) |> Map.put(:to_tile, to_tile)}
      end

      when_ "I order the unit to move to that adjacent tile", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.lord.id,
          "to_tile" => context.to_tile
        })

        {:ok, context}
      end

      then_ "the unit is already at its new tile with less movement remaining, before any turn advances",
            context do
        assert_push_event(context.play_live, "game:path", %{tiles: _})

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == context.lord.id,
            do: u

        assert lord.tile_id == context.to_tile
        assert lord.movement < context.lord.movement
        {:ok, context}
      end
    end
  end
end
