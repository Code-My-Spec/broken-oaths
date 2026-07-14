defmodule BrokenOathsSpex.Story874.Criterion7420Spex do
  @moduledoc """
  Story 874 — Automatic Turn Processing
  Criterion 7420 — turns advance while no player is connected; a returning player sees the elapsed turns.

  Turn boundaries are wall-clock (60s) in production. Specs use the
  sanctioned deterministic tick (`Fixtures.advance_turn/1`) instead of
  sleeping — the tick is exactly what the timer fires.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the world lives while everyone sleeps" do
    scenario "ten turns pass with nobody connected" do
      given_ :a_world
      given_ :registered_player

      given_ "the player has joined the world", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, context}
      end

      given_ "the player knows the current turn and disconnects", context do
        {:ok, play_live, html} = live(context.conn, ~p"/play/#{context.world.id}")
        [turn] = Regex.run(~r/data-test="turn-number"[^>]*>(\d+)</, html, capture: :all_but_first)

        GenServer.stop(play_live.pid)
        {:ok, Map.put(context, :turn_before, String.to_integer(turn))}
      end

      when_ "ten turn boundaries fire while nobody is connected", context do
        for _ <- 1..10, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the returning player sees the world ten turns older", context do
        {:ok, _play_live, html} = live(context.conn, ~p"/play/#{context.world.id}")
        [turn] = Regex.run(~r/data-test="turn-number"[^>]*>(\d+)</, html, capture: :all_but_first)
        assert String.to_integer(turn) == context.turn_before + 10
        {:ok, context}
      end
    end
  end
end
