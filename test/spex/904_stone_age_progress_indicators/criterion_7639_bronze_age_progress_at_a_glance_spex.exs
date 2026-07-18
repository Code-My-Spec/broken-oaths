defmodule BrokenOathsSpex.Story904.Criterion7639Spex do
  @moduledoc """
  Story 904 — Stone Age Progress Indicators
  Criterion 7639 — Bronze Age progress at a glance: the progress panel
  shows the player's current age, their science income, and how close
  they are to Bronze Working. Source: stone_age.md §12.1 — "Progress
  panel shows: Current Age (Stone Age), Tech progress toward Bronze
  Working" and "Shows: Science per turn, Estimated turns to Bronze
  Working."

  RED-first: `BrokenOathsWeb.GameLive.ProgressPanel` does not exist
  yet (the task prompt's own source pointer, `lib/broken_oaths_web/
  game_live/progress_panel.ex`, couldn't be read). This spec drives
  `GameLive.Play` — the only place a `liveview_component` like this
  could mount, per every other side panel already living under
  `lib/broken_oaths_web/live/game_live/` (`KnownPlayersPanel`,
  `ChatPanel`, `CityPanel`, `UnitPanel`, `AlliancePanel`) — and
  asserts on the data-test contract this criterion assumes the panel
  will expose, documented below since no implementation exists yet to
  read it from.

  ## Assumed data-test contract

    * `[data-test='progress-panel']` — the panel's root container
    * `[data-test='progress-age']` — text includes "Stone Age" (the
      only age reachable in this MVP; story 903 owns the actual
      Bronze Age transition)
    * `[data-test='progress-science-per-turn']` — text includes the
      player's current science income, a plain integer
    * `[data-test='progress-bronze-working']` — text includes
      "`<banked>` / `<cost>`" for the Bronze Working tech specifically
      (`"0 / 100"` before any science has ever been banked toward it)
    * `[data-test='progress-turns-to-bronze']` — text includes a plain
      integer: the estimated number of turns to reach Bronze Working

  ## Turns-to-Bronze formula (judgment call)

  Story 902's `BrokenOaths.Game.Research` already tracks
  `banked_science` per tech INDEPENDENTLY of `current_research` (see
  that module's own moduledoc: "banked_science tracks progress for
  EVERY tech independently... switching current_research never
  discards progress on the tech switched away from"). There is no
  tech-selection UI surface yet — no `TechPanel`-style component
  exists anywhere under `game_live/`, so story 902's own selection UI
  is itself still pending — meaning a player in this spec has never
  selected ANY current research, and `banked_science[:bronze_working]`
  is necessarily 0.

  Rather than leave "estimated turns to Bronze Working" untestable
  until a tech-selection UI exists, this spec's assumed contract is a
  forward PROJECTION at the player's current science/turn rate:
  `ceil((bronze_working_cost - banked_toward_bronze_working) /
  science_per_turn)` — "how many turns from now, at this rate, could
  you finish Bronze Working" — computable and meaningful the instant a
  player has any science income at all, independent of whether Bronze
  Working happens to be the tech currently selected. With
  `banked_toward_bronze_working` at 0 (nothing has ever been
  researched), the numerator collapses to the tech's flat 100-science
  cost (story 902, stone_age.md §6.1: "Bronze Working (100 science)").

  ## Science constant

  "2 science per population per turn" is story 902's own rule
  (stone_age.md §6.1: "Cities generate science based on population: 2
  science per population per turn") — `BrokenOaths.Game.Research.
  science_per_turn/1` computes exactly `size * 2` per city. This spec
  hardcodes that same constant independently (it never calls
  `Research` itself, which sits outside the spec boundary) to derive
  its own expected value from a real city's `size`, read back via the
  sanctioned `Fixtures.player_cities/2`.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  # story 902, stone_age.md §6.1
  @science_per_pop 2
  @bronze_working_cost 100

  spex "Bronze Age progress at a glance" do
    scenario "founding a city gives the progress panel real age, science, and Bronze Working numbers to show" do
      given_(:a_world)
      given_(:registered_player)

      given_ "I have joined the world", context do
        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        {:ok, Map.put(context, :play_live, play_live)}
      end

      when_ "I found my first city", context do
        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(context.play_live, "found_city", %{"unit_id" => to_string(settler.id)})

        {:ok, context}
      end

      then_ "the progress panel shows my current age as Stone Age", context do
        assert has_element?(context.play_live, "[data-test='progress-age']", "Stone Age")
        {:ok, context}
      end

      then_ "the progress panel shows my science per turn", context do
        [city] = Fixtures.player_cities(context.world, context.user)
        expected = city.size * @science_per_pop

        assert has_element?(
                 context.play_live,
                 "[data-test='progress-science-per-turn']",
                 to_string(expected)
               )

        {:ok, context}
      end

      then_ "the progress panel shows tech progress toward Bronze Working", context do
        assert has_element?(
                 context.play_live,
                 "[data-test='progress-bronze-working']",
                 "0 / #{@bronze_working_cost}"
               )

        {:ok, context}
      end

      then_ "the progress panel shows my estimated turns to Bronze Working", context do
        [city] = Fixtures.player_cities(context.world, context.user)
        science_per_turn = city.size * @science_per_pop
        expected_turns = ceil_div(@bronze_working_cost, science_per_turn)

        assert has_element?(
                 context.play_live,
                 "[data-test='progress-turns-to-bronze']",
                 to_string(expected_turns)
               )

        {:ok, context}
      end
    end
  end

  # Integer ceiling division — avoids a Float round-trip for a plain
  # "how many whole turns" estimate.
  defp ceil_div(a, b), do: div(a + b - 1, b)
end
