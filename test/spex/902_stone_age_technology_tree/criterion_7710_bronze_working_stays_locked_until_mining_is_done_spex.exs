defmodule BrokenOathsSpex.Story902.Criterion7710Spex do
  @moduledoc """
  Story 902 — Stone Age Technology Tree
  Criterion 7710 — Bronze Working stays locked until Mining is done:
  new for the expanded, prerequisite-gated Ancient-era tree (playtest
  issue 133b4893). A technology whose prerequisite hasn't been
  completed yet is `:locked` (`BrokenOaths.Technology.Research.tech_state/2`)
  and cannot be selected for research — attempting to `"select_research"`
  it is a silent no-op, and the tree itself names exactly which
  prerequisite it's waiting on
  (`[data-test='tech-prereqs-bronze_working']`).

  Distinguishes itself from `Criterion7630Spex` (which drives the REAL
  confirm flow once Bronze Working IS researchable): this spec drives
  the fresh-player case, BEFORE Mining is ever researched, and asserts
  the warning modal never even appears.

  See `Criterion7625Spex`'s moduledoc for the assumed `TechPanel`
  surface contract this spec (and its siblings) drives.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "Bronze Working stays locked until Mining is done" do
    scenario "a fresh player sees Bronze Working locked, and clicking it does nothing" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      when_ "the player opens the tech tree, having not yet researched Mining", context do
        render_hook(context.play_live, "toggle_tech_panel", %{})
        {:ok, context}
      end

      then_ "Bronze Working is shown locked, naming Mining as what it needs", context do
        assert has_element?(context.play_live, "[data-test='tech-locked-bronze_working']")

        assert has_element?(
                 context.play_live,
                 "[data-test='tech-prereqs-bronze_working']",
                 "Mining"
               )

        assert has_element?(
                 context.play_live,
                 "[data-test='tech-bronze_working'][data-disabled='true']"
               )

        {:ok, context}
      end

      when_ "the player tries to research Bronze Working anyway", context do
        render_hook(context.play_live, "select_research", %{"tech" => "bronze_working"})
        {:ok, context}
      end

      then_ "Bronze Working is not selected — no warning, no progress bar", context do
        refute has_element?(context.play_live, "[data-test='bronze-working-warning']")
        refute has_element?(context.play_live, "[data-test='research-progress']")
        assert has_element?(context.play_live, "[data-test='tech-locked-bronze_working']")
        {:ok, context}
      end
    end
  end
end
