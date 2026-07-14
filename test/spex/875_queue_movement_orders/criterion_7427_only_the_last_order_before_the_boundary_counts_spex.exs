defmodule BrokenOathsSpex.Story875.Criterion7427Spex do
  @moduledoc """
  Story 875 — Queue Movement Orders
  Criterion 7427 — orders are freely replaceable until the boundary; only the final one executes.

  The globe board has no tile DOM; orders travel as LiveView events
  (render_hook) and results come back as pushed payloads and unit
  positions — per the board doctrine.
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

      given_ "two different adjacent land targets are known", context do
        land? = fn tile -> Fixtures.tile_class(context.world, tile) == :land end

        [unit | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        [first, second | _] =
          context.world
          |> Fixtures.adjacent_tiles(unit.tile_id)
          |> Enum.filter(land?)

        {:ok,
         context |> Map.put(:unit, unit) |> Map.put(:first, first) |> Map.put(:second, second)}
      end

      when_ "the player queues one target, then replaces it with another", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.unit.id,
          "to_tile" => context.first
        })

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.unit.id,
          "to_tile" => context.second
        })

        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the unit moved to the replacement target, never the first", context do
        [unit] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.unit.id,
              do: u

        assert unit.tile_id == context.second
        {:ok, context}
      end
    end
  end
end
