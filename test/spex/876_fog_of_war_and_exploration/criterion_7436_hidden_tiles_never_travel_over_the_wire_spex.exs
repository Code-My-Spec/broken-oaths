defmodule BrokenOathsSpex.Story876.Criterion7436Spex do
  @moduledoc """
  Story 876 — Fog of War and Exploration
  Criterion 7436 — fog is enforced server-side — hidden data is absent from every payload, not painted over.

  Fog truth surfaces (board doctrine): the fog-filtered board pushes —
  "game:visibility" (visible/explored tile ids), "game:window" (tile
  geometry, fog-filtered), "game:units" (visible units only). The
  canvas paint is never asserted.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "hidden tiles never travel over the wire" do
    scenario "every pushed payload is fog-filtered" do
      given_ :a_world
      given_ :registered_player
      given_ :second_registered_player

      given_ "both players joined the world", context do
        for conn <- [context.conn, context.other_conn] do
          {:ok, join_live, _html} = live(conn, ~p"/play")

          join_live
          |> element("[data-test='join-world-#{context.world.id}']")
          |> render_click()
        end

        {:ok, context}
      end

      when_ "the board loads with most of the world unexplored", context do
        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        assert_push_event(play_live, "game:visibility", %{visible: visible, explored: explored})
        assert_push_event(play_live, "game:window", %{tiles: tiles})
        assert_push_event(play_live, "game:units", %{units: units})

        context =
          context
          |> Map.put(:known, MapSet.new(visible ++ explored))
          |> Map.put(:tiles, tiles)
          |> Map.put(:units, units)

        {:ok, context}
      end

      then_ "the tile window contains only known tiles", context do
        for row <- context.tiles do
          [tile_id | _] = row
          assert MapSet.member?(context.known, tile_id)
        end

        # Anchor: the window is not empty
        assert context.tiles != []
        {:ok, context}
      end

      then_ "the other player's units are absent from the payload entirely", context do
        their_ids = for u <- Fixtures.player_units(context.world, context.other_user), do: u.id

        for unit <- context.units do
          refute unit.id in their_ids
        end

        # Anchor: own units ARE in the payload
        my_ids = for u <- Fixtures.player_units(context.world, context.user), do: u.id
        assert Enum.any?(context.units, &(&1.id in my_ids))
        {:ok, context}
      end
    end
  end
end
