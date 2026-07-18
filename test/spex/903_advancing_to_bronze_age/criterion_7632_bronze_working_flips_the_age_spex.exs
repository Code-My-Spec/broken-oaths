defmodule BrokenOathsSpex.Story903.Criterion7632Spex do
  @moduledoc """
  Story 903 — Advancing to Bronze Age
  Criterion 7632 — completing Bronze Working research advances the
  player to the Bronze Age. Source: stone_age.md §6.2 — "Completing
  Bronze Working research advances player to Bronze Age" and "Player
  notified: 'You have entered the Bronze Age! New units and buildings
  unlocked.'"

  Component under test: `BrokenOathsWeb.GameLive.AgePanel` (couldn't be
  read — `.code_my_spec/spec/broken_oaths_web/game_live/age_panel.spec.md`
  confirms it's a `liveview_component` that "Shows the player's current
  age and Bronze Age status, and surfaces the ... notification when
  Bronze Working completes," but no implementation exists yet).

  ## What this criterion needs, wired

  Story 902's `TechPanel` (selecting Bronze Working) already exists —
  see the "Research-selection surface" section below. The backend this
  criterion rides on ALSO already exists and IS wired to fire an event
  on completion: `BrokenOaths.Game.Research.age/1` derives the age
  purely from `completed_techs` (no separate flag), and
  `BrokenOaths.Game.Turn.tick/1` already fires `{:tech_completed,
  user_id, tech}` the instant a tech's cost banks in full (`Turn.
  tick/1`'s own moduledoc, lines 194-199; `WorldServer` broadcasts
  every tick event world-wide). What's still missing is `GameLive.Play`
  listening for `{:tech_completed, ...}` and forwarding it to
  `AgePanel` — story 903's own build target.

  ## Assumed data-test / push-event contract for `AgePanel`

    * `[data-test='age-panel']` — the panel's root container (mirrors
      the always-visible `player-gold` badge already in `GameLive.
      Play`'s top bar — current age is exactly that kind of persistent
      status, not a selection-triggered side panel).
    * `[data-test='age-status']` — text includes "Stone Age" or
      "Bronze Age".
    * `"game:age"` push event, `%{message: string}` — the one-shot
      Bronze Age notification, mirroring the EXACT shape and dispatch
      convention `"game:discovery"`/`"game:alert"`/`"game:lineage"`
      already establish in `GameLive.Play` (player-scoped `handle_info`
      clause pushing a single `message` string, picked up client-side
      by the shared `showToast` helper into the existing
      `[data-test='game-toast']` element).

  ## Research-selection surface

  Story 902's `TechPanel`/`GameLive.Play` own the real event contract:
  `"toggle_tech_panel"` opens the panel, `"select_research"` with
  `%{"tech" => "bronze_working"}` raises the `bronze-working-warning`
  confirm rather than committing immediately, and
  `"bronze_working_confirm"` is what actually calls
  `Game.set_research(world, user, :bronze_working)` — see
  `BrokenOathsWeb.GameLive.TechPanel`'s moduledoc for the full flow.
  This is the SAME contract `BrokenOathsSpex.SharedGivens`'s
  `:player_reached_bronze_age` given now drives, and the same one story
  902's own specs (`criterion_7630`) exercise directly.

  This scenario deliberately does NOT use the shared
  `:player_reached_bronze_age` given: the age flip is the very thing
  under test here, so `given_` only selects (and confirms) the research
  (0 science banked — not yet complete) and `when_` is what lets the
  turns pass that actually cross the completion threshold.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Bronze Working flips the age", fail_on_error_logs: false do
    scenario "completing Bronze Working advances the player to the Bronze Age" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "I have selected Bronze Working as my current research", context do
        render_hook(context.play_live, "toggle_tech_panel", %{})
        render_hook(context.play_live, "select_research", %{"tech" => "bronze_working"})
        render_hook(context.play_live, "bronze_working_confirm", %{})

        {:ok, Map.put(context, :research_select_result, :ok)}
      end

      when_ "enough turns pass for Bronze Working's 100-science cost to bank in full", context do
        # A lone size-1 city earns 2 science/turn (`Research.
        # science_per_turn/1`); 50 turns already covers the 100 cost
        # even with zero growth, and growth (independent of research)
        # only ever raises the rate further. 60 is a safe overshoot —
        # see `SharedGivens.player_reached_bronze_age`'s own doc for the
        # identical math.
        for _ <- 1..60, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "I am notified: \"You have entered the Bronze Age! New units and buildings unlocked.\"",
            context do
        assert context.research_select_result == :ok,
               "selecting/confirming Bronze Working as research failed"

        assert_push_event(context.play_live, "game:age", %{message: msg}, 500)
        assert msg == "You have entered the Bronze Age! New units and buildings unlocked."
        {:ok, context}
      end

      then_ "my AgePanel shows Bronze Age status", context do
        assert has_element?(context.play_live, "[data-test='age-panel']")
        assert has_element?(context.play_live, "[data-test='age-status']", "Bronze Age")
        {:ok, context}
      end
    end
  end
end
