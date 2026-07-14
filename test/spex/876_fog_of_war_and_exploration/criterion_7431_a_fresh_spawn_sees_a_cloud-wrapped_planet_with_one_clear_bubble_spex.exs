defmodule BrokenOathsSpex.Story876.Criterion7431Spex do
  @moduledoc """
  Story 876 — Fog of War and Exploration
  Criterion 7431 — a new player sees only their spawn bubble; the rest of the globe is fogged at every zoom.

  Fog truth surfaces (board doctrine): the fog-filtered board pushes —
  "game:visibility" (visible/explored tile ids), "game:window" (tile
  geometry, fog-filtered), "game:units" (visible units only). The
  canvas paint is never asserted.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a fresh spawn sees a cloud-wrapped planet with one clear bubble" do
    scenario "visibility covers the spawn bubble and little else" do
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

      when_ "the board loads for the first time", context do
        assert_push_event(context.play_live, "game:visibility", %{visible: visible, explored: explored})
        {:ok, context |> Map.put(:visible, visible) |> Map.put(:explored, explored)}
      end

      then_ "the spawn bubble is visible and includes the player's units", context do
        assert context.visible != []

        for unit <- Fixtures.player_units(context.world, context.user) do
          assert unit.tile_id in context.visible
        end

        {:ok, context}
      end

      then_ "almost all of the globe is still fogged", context do
        total = 10 * context.world.frequency * context.world.frequency + 2
        known = Enum.uniq(context.visible ++ context.explored)
        assert length(known) < div(total, 4)
        {:ok, context}
      end
    end
  end
end
