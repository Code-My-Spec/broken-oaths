defmodule BrokenOathsSpex.Story876.Criterion7438Spex do
  @moduledoc """
  Story 876 — Fog of War and Exploration
  Criterion 7438 — fog and weather are separate layers with distinct styling.

  Fog truth surfaces (board doctrine): the fog-filtered board pushes —
  "game:visibility" (visible/explored tile ids), "game:window" (tile
  geometry, fog-filtered), "game:units" (visible units only). The
  canvas paint is never asserted.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "fog cloud and weather cloud read as different things" do
    scenario "fog and weather arrive as separate, differently-styled layers" do
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

      when_ "the board loads", context do
        assert_push_event(context.play_live, "game:visibility", %{visible: _})
        assert_push_event(context.play_live, "globe3d:airspace", %{levels: _})
        {:ok, context}
      end

      then_ "the stage declares distinct fog and weather layers", context do
        assert has_element?(context.play_live, "[data-test='fog-layer']")
        assert has_element?(context.play_live, "[data-test='weather-layer']")
        {:ok, context}
      end
    end
  end
end
