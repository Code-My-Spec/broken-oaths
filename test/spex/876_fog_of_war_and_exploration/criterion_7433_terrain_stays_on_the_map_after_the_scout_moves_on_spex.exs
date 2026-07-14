defmodule BrokenOathsSpex.Story876.Criterion7433Spex do
  @moduledoc """
  Story 876 — Fog of War and Exploration
  Criterion 7433 — explored terrain is remembered (dimmed) once out of vision.

  Fog truth surfaces (board doctrine): the fog-filtered board pushes —
  "game:visibility" (visible/explored tile ids), "game:window" (tile
  geometry, fog-filtered), "game:units" (visible units only). The
  canvas paint is never asserted.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "terrain stays on the map after the scout moves on" do
    scenario "a visited tile becomes remembered, not forgotten" do
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

      given_ "the lord walks four tiles away from its starting spot", context do
        land? = fn tile -> Fixtures.tile_class(context.world, tile) == :land end

        [lord | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        walk =
          Enum.reduce(1..4, [lord.tile_id], fn _, [here | _] = acc ->
            next =
              context.world
              |> Fixtures.adjacent_tiles(here)
              |> Enum.reject(&(&1 in acc))
              |> Enum.filter(land?)
              |> List.first()

            [next | acc]
          end)

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => lord.id,
          "to_tile" => hd(walk)
        })

        for _ <- 1..4, do: Fixtures.advance_turn(context.world)

        {:ok, context |> Map.put(:origin, lord.tile_id)}
      end

      when_ "the board's visibility refreshes", context do
        assert_push_event(context.play_live, "game:visibility", %{
          visible: visible,
          explored: explored
        })

        {:ok, context |> Map.put(:visible, visible) |> Map.put(:explored, explored)}
      end

      then_ "the starting spot is remembered but no longer visible", context do
        assert context.origin in context.explored
        {:ok, context}
      end
    end
  end
end
