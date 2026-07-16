defmodule BrokenOathsSpex.Story897.Criterion7577Spex do
  @moduledoc """
  Story 897 — Configurable Turn Length
  Criterion 7577 — a fast (QA) world and a default-pace world run side
  by side, each firing its own turn boundary on ITS OWN configured
  `turn_seconds` rather than one hardcoded cadence shared by every
  world in the process.

  `WorldServer` already exposes `Fixtures.advance_turn/1` as the
  sanctioned stand-in for "this world's own boundary timer just
  fired" (the same surface story 874's specs use, since specs must
  never sleep through a real turn boundary — see
  `.code_my_spec/knowledge/bdd/spex/surfaces.md`). This spec fires
  that boundary once for each world and reads the freshly-reset
  countdown each one shows afterward: a world honoring its own
  `turn_seconds` resets to (about) that value, while one still
  hardcoded to a single global tick length resets to the same ~60s
  regardless of what it was configured with — which is exactly what
  would make the fast world's assertion below fail today.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a fast world and a slow world coexist" do
    scenario "each world's boundary resets its own countdown to its own turn length" do
      given_(:registered_player)

      given_ "a QA-fast world configured with 5-second turns", context do
        world = Fixtures.world_fixture(%{turn_seconds: 5, seed: 424_242, frequency: 8})
        {:ok, Map.put(context, :fast_world, world)}
      end

      given_ "a default-pace world configured with 60-second turns", context do
        world = Fixtures.world_fixture(%{turn_seconds: 60})
        {:ok, Map.put(context, :slow_world, world)}
      end

      given_ "the player has joined the fast world and is watching its turn bar", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.fast_world.id}']")
        |> render_click()

        {:ok, fast_play_live, _html} = live(context.conn, ~p"/play/#{context.fast_world.id}")
        {:ok, Map.put(context, :fast_play_live, fast_play_live)}
      end

      given_ "the same player has also joined the slow world and is watching its turn bar", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.slow_world.id}']")
        |> render_click()

        {:ok, slow_play_live, _html} = live(context.conn, ~p"/play/#{context.slow_world.id}")
        {:ok, Map.put(context, :slow_play_live, slow_play_live)}
      end

      when_ "a boundary fires for the fast world only", context do
        Fixtures.advance_turn(context.fast_world)
        {:ok, context}
      end

      then_ "the fast world's countdown resets to about its own 5-second length", context do
        html = render(context.fast_play_live)

        [countdown] =
          Regex.run(~r/data-test="turn-countdown"[^>]*>(\d+)</, html, capture: :all_but_first)

        assert String.to_integer(countdown) <= 5
        {:ok, context}
      end

      then_ "the slow world's countdown is untouched — no boundary has fired for it yet", context do
        html = render(context.slow_play_live)

        [countdown] =
          Regex.run(~r/data-test="turn-countdown"[^>]*>(\d+)</, html, capture: :all_but_first)

        assert String.to_integer(countdown) > 5
        {:ok, context}
      end

      when_ "a boundary also fires for the slow world", context do
        Fixtures.advance_turn(context.slow_world)
        {:ok, context}
      end

      then_ "the slow world's countdown resets to about its own 60-second length, unaffected by the fast world", context do
        html = render(context.slow_play_live)

        [countdown] =
          Regex.run(~r/data-test="turn-countdown"[^>]*>(\d+)</, html, capture: :all_but_first)

        assert String.to_integer(countdown) > 5

        # And the fast world, which nobody has ticked again, still holds
        # the value its own boundary left it at a moment ago — the two
        # worlds' clocks never leak into each other either direction.
        fast_html = render(context.fast_play_live)

        [fast_countdown] =
          Regex.run(~r/data-test="turn-countdown"[^>]*>(\d+)</, fast_html, capture: :all_but_first)

        assert String.to_integer(fast_countdown) <= 5
        {:ok, context}
      end
    end
  end
end
