defmodule BrokenOathsSpex.Story903.Criterion7638Spex do
  @moduledoc """
  Story 903 — Advancing to Bronze Age
  Criterion 7638 — Bronze Age status is shown in the player profile.
  Source: stone_age.md §6.2 — "Bronze Age status shown in player
  profile."

  Judgment call: this game has no dedicated "profile" route — the
  closest thing is `AgePanel` itself, whose own design doc
  (`.code_my_spec/spec/broken_oaths_web/game_live/age_panel.spec.md`)
  already frames it as "Shows the player's current age and Bronze Age
  status" for story 903, i.e. exactly this criterion's language. See
  criterion 7632's moduledoc for the full assumed
  `[data-test='age-panel']` / `[data-test='age-status']` contract.

  What distinguishes this criterion from criterion 7632 (which tests
  the FLIP itself — the one-shot notification firing the moment Bronze
  Working completes) is PERSISTENCE: the profile must still read
  "Bronze Age" on a later, independent page load/reconnect, not merely
  while the original connection that witnessed the flip stays open.
  This spec reaches Bronze Age (attempted — see
  `BrokenOathsSpex.SharedGivens`'s `:player_reached_bronze_age`
  moduledoc for the still-missing `"set_research"` surface this rides
  on), then mounts a BRAND NEW `GameLive.Play` connection and asserts
  the status reads correctly on that fresh mount — proving the age is
  read from durable state (`Game.player_research/2`, ultimately
  `Research.age/1` over `completed_techs`) rather than held only in a
  stale socket assign from the moment of completion.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "profile reflects the age" do
    scenario "a fresh reconnect still shows Bronze Age status after the player has reached it" do
      given_(:a_world)
      given_(:registered_player)
      given_(:player_reached_bronze_age)

      when_ "I reload — a brand new connection to the game board", context do
        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")
        {:ok, Map.put(context, :reloaded_play_live, play_live)}
      end

      then_ "my profile (AgePanel) shows Bronze Age status", context do
        assert context.research_select_result == :ok,
               "selecting/confirming Bronze Working as research failed, so the Bronze Age was never actually reached"

        assert has_element?(context.reloaded_play_live, "[data-test='age-panel']")
        assert has_element?(context.reloaded_play_live, "[data-test='age-status']", "Bronze Age")
        {:ok, context}
      end
    end
  end
end
