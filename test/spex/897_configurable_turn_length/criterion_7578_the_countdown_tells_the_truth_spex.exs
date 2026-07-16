defmodule BrokenOathsSpex.Story897.Criterion7578Spex do
  @moduledoc """
  Story 897 — Configurable Turn Length
  Criterion 7578 — the on-screen countdown always reflects the world's
  own `turn_seconds`, from the very first render, and every boundary
  mechanic (turn advance, resource ticks) fires on that same cadence —
  never a hardcoded global regardless of what a world was configured
  with.

  Two facets, two scenarios:

    1. A freshly-created fast world's countdown starts near its own
       5-second length, not the ~60s a hardcoded tick length would show.
    2. When that world's boundary fires (`Fixtures.advance_turn/1` —
       the sanctioned stand-in for "the timer fired", same surface
       story 874/879/880's specs use so nothing here sleeps through a
       real turn), a founded city's food/production banks right along
       with it, and the freshly-reset countdown is still anchored to
       the world's own 5-second length — proving one shared per-world
       cadence drives both facts, not two independently-scheduled
       clocks.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the countdown tells the truth" do
    scenario "a fresh QA-fast world's countdown starts near its own turn length" do
      given_(:registered_player)

      given_ "a QA-fast world configured with 5-second turns", context do
        world = Fixtures.world_fixture(%{turn_seconds: 5, seed: 424_243, frequency: 8})
        {:ok, Map.put(context, :world, world)}
      end

      given_ "the player has joined and is watching the turn bar", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, html} = live(context.conn, ~p"/play/#{context.world.id}")
        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:initial_html, html)}
      end

      then_ "the very first countdown shown is bounded by the world's own 5-second length, not ~60s", context do
        [countdown] =
          Regex.run(
            ~r/data-test="turn-countdown"[^>]*>(\d+)</,
            context.initial_html,
            capture: :all_but_first
          )

        assert String.to_integer(countdown) <= 5
        {:ok, context}
      end
    end

    scenario "food and production bank on the same cadence the countdown promises" do
      given_(:registered_player)

      given_ "a QA-fast world configured with 5-second turns", context do
        world = Fixtures.world_fixture(%{turn_seconds: 5, seed: 424_244, frequency: 8})
        {:ok, Map.put(context, :world, world)}
      end

      given_ "a freshly founded city on the player's settler tile", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        # String id on purpose: real phx-value-* params are strings.
        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        [city] = Fixtures.player_cities(context.world, context.user)

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:city, city)}
      end

      when_ "this world's own boundary fires once", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the city's food banked for that single boundary — a real accrual, not a stub", context do
        [city] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id == context.city.id, do: c

        # `food` starts at 0 for a freshly founded city and only moves
        # when a `Turn.tick` actually runs; a nonzero reading after
        # exactly one `advance_turn` call proves the resource tick and
        # the turn advance are the same event, not two clocks.
        assert city.food > 0
        {:ok, Map.put(context, :ticked_city, city)}
      end

      then_ "the countdown the boundary just reset is still bounded by the world's own 5-second length", context do
        html = render(context.play_live)

        [countdown] =
          Regex.run(~r/data-test="turn-countdown"[^>]*>(\d+)</, html, capture: :all_but_first)

        assert String.to_integer(countdown) <= 5
        {:ok, context}
      end
    end
  end
end
