defmodule BrokenOathsSpex.Story874.Criterion7419Spex do
  @moduledoc """
  Story 874 — Automatic Turn Processing
  Criterion 7419 — the turn number and countdown are visible, and the turn advances with no player action.

  Turn boundaries are wall-clock (60s) in production. Specs use the
  sanctioned deterministic tick (`Fixtures.advance_turn/1`) instead of
  sleeping — the tick is exactly what the timer fires.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the countdown runs down and the turn advances by itself" do
    scenario "the turn advances without anyone acting" do
      given_ :a_world
      given_ :registered_player

      given_ "the player has joined the world", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, context}
      end

      given_ "the player is watching the board with the turn bar visible", context do
        {:ok, play_live, html} = live(context.conn, ~p"/play/#{context.world.id}")

        assert has_element?(play_live, "[data-test='turn-number']")
        assert has_element?(play_live, "[data-test='turn-countdown']")

        [turn] = Regex.run(~r/data-test="turn-number"[^>]*>(\d+)</, html, capture: :all_but_first)
        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:turn_before, String.to_integer(turn))}
      end

      when_ "the turn boundary fires with no player action", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the displayed turn number has advanced by one", context do
        html = render(context.play_live)
        [turn] = Regex.run(~r/data-test="turn-number"[^>]*>(\d+)</, html, capture: :all_but_first)
        assert String.to_integer(turn) == context.turn_before + 1
        {:ok, context}
      end
    end
  end
end
