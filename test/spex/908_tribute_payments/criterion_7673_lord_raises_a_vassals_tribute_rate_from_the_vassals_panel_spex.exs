defmodule BrokenOathsSpex.Story908.Criterion7673Spex do
  @moduledoc """
  Story 908 — Tribute Payments
  Criterion 7673 — the tribute rate is "a LORD-SET, PER-VASSAL,
  ADJUSTABLE LEVER (not a fixed 25%)... The lord sets and changes it
  from the Vassals panel; the vassal sees the rate and feels the
  pressure" (`.code_my_spec/knowledge/feudal_vassalage_design.md`,
  "Round-4 final foundation mechanics"). This is the rate-adjustment
  control itself, ahead of `criterion_7675`'s own "the new rate
  actually applies next turn."

  Builds on story 907's own Vassalage relationship — see
  `BrokenOathsSpex.Story907.Criterion7666Spex`'s own moduledoc for the
  shared `vassals-list`/`vassal-row`/`vassal-status` judgment calls,
  and `BrokenOathsSpex.Story907.Criterion7669Spex`'s own
  `vassal-tribute-rate` element (the default 25% this criterion raises
  away from).

  ## This criterion's own new judgment calls

  1. **The rate control**: a new `"set_tribute_rate"` event, `%{
     "vassal_user_id" => ..., "rate" => "50"}` — matching "a slider or
     input (0-100%)" (`.code_my_spec/stories/more_stories.md` §7.3).
     Driven through `attempt_event/3` since no `handle_event/3` clause
     exists for it yet.
  2. **The vassal's own view of the current rate**: a sibling
     `data-test="my-tribute-rate"` element on the vassal's own
     `GameLive.Play` (alongside `vassal-status`) — "the vassal sees the
     rate," the design doc's own words.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "the lord raises a vassal's tribute rate from the Vassals panel", fail_on_error_logs: false do
    scenario "raising a vassal's rate updates it on both the lord's and the vassal's own view" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my rival is already my vassal, at the default 25% rate", context do
        {:ok, a_freshly_subjugated_vassal(context)}
      end

      when_ "I raise their tribute rate to 50% from my Vassals panel", context do
        attempt_event(context.play_live, "set_tribute_rate", %{
          "vassal_user_id" => to_string(context.other_user.id),
          "rate" => "50"
        })

        # `attempt_event/3` traps the crash `"set_tribute_rate"` raises
        # today (no handler exists yet), but the crashed LiveView
        # PROCESS itself is gone afterward — a later `has_element?`
        # against the SAME `context.play_live` would raise `exit` (no
        # process), not a clean assertion failure. Re-mounting fresh,
        # the same idiom a real page reload would give the lord, keeps
        # the RED signal a normal assertion failure instead.
        {:ok, fresh_play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        {:ok, Map.put(context, :play_live, fresh_play_live)}
      end

      then_ "my own Vassals list now shows their rate as 50%", context do
        assert context.my_lord.tile_id == context.other_city.tile_id

        assert has_element?(
                 context.play_live,
                 "[data-test='vassal-row-#{context.other_user.id}'] [data-test='vassal-tribute-rate']",
                 "50%"
               )

        {:ok, context}
      end

      then_ "the vassal's own view now shows the new 50% rate too", context do
        assert has_element?(
                 context.other_play_live,
                 "[data-test='my-tribute-rate']",
                 "50%"
               )

        {:ok, context}
      end
    end
  end
end
