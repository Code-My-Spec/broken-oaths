defmodule BrokenOathsSpex.Story874.Criterion7421Spex do
  @moduledoc """
  Story 874 — Automatic Turn Processing
  Criterion 7421 — a WorldServer restart preserves the turn count and queued orders exactly.

  Turn boundaries are wall-clock (60s) in production. Specs use the
  sanctioned deterministic tick (`Fixtures.advance_turn/1`) instead of
  sleeping — the tick is exactly what the timer fires.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a server restart never loses or double-runs a turn" do
    scenario "the world resumes exactly where it was" do
      given_ :a_world
      given_ :registered_player

      given_ "the player has joined the world", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, context}
      end

      given_ "the player has a queued move and knows the turn number", context do
        {:ok, play_live, html} = live(context.conn, ~p"/play/#{context.world.id}")
        [turn] = Regex.run(~r/data-test="turn-number"[^>]*>(\d+)</, html, capture: :all_but_first)

        [unit | _] = Fixtures.player_units(context.world, context.user)
        [target | _] = Fixtures.adjacent_tiles(context.world, unit.tile_id)

        render_hook(play_live, "queue_move", %{"unit_id" => unit.id, "to_tile" => target})

        context =
          context
          |> Map.put(:turn_before, String.to_integer(turn))
          |> Map.put(:unit_id, unit.id)
          |> Map.put(:target, target)

        {:ok, context}
      end

      when_ "the world's server process restarts", context do
        Fixtures.restart_world(context.world)
        {:ok, context}
      end

      then_ "the turn count is unchanged and the queued order survives, exactly once", context do
        {:ok, play_live, html} = live(context.conn, ~p"/play/#{context.world.id}")
        [turn] = Regex.run(~r/data-test="turn-number"[^>]*>(\d+)</, html, capture: :all_but_first)
        assert String.to_integer(turn) == context.turn_before

        Fixtures.advance_turn(context.world)

        [unit] = for u <- Fixtures.player_units(context.world, context.user), u.id == context.unit_id, do: u
        assert unit.tile_id == context.target

        # Anchor: the board still renders after the restart
        assert has_element?(play_live, "[data-test='turn-number']")
        {:ok, context}
      end
    end
  end
end
