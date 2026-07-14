defmodule BrokenOathsSpex.Story874.Criterion7423Spex do
  @moduledoc """
  Story 874 — Automatic Turn Processing
  Criterion 7423 — all connected players see the turn advance in real time, without refreshing.

  Turn boundaries are wall-clock (60s) in production. Specs use the
  sanctioned deterministic tick (`Fixtures.advance_turn/1`) instead of
  sleeping — the tick is exactly what the timer fires.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "two connected players tick over together" do
    scenario "both browsers show the new turn without a refresh" do
      given_ :a_world
      given_ :registered_player
      given_ :second_registered_player

      given_ "both players joined and are watching the board", context do
        views =
          for conn <- [context.conn, context.other_conn] do
            {:ok, join_live, _html} = live(conn, ~p"/play")

            join_live
            |> element("[data-test='join-world-#{context.world.id}']")
            |> render_click()

            {:ok, play_live, _html} = live(conn, ~p"/play/#{context.world.id}")
            play_live
          end

        [html | _] = Enum.map(views, &render/1)
        [turn] = Regex.run(~r/data-test="turn-number"[^>]*>(\d+)</, html, capture: :all_but_first)

        {:ok, context |> Map.put(:views, views) |> Map.put(:turn_before, String.to_integer(turn))}
      end

      when_ "the turn boundary fires", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "both connected views show the advanced turn without refreshing", context do
        for view <- context.views do
          html = render(view)
          [turn] = Regex.run(~r/data-test="turn-number"[^>]*>(\d+)</, html, capture: :all_but_first)
          assert String.to_integer(turn) == context.turn_before + 1
        end

        {:ok, context}
      end
    end
  end
end
