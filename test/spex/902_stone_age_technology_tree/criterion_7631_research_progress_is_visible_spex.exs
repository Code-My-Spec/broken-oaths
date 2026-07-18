defmodule BrokenOathsSpex.Story902.Criterion7631Spex do
  @moduledoc """
  Story 902 — Stone Age Technology Tree
  Criterion 7631 — research progress is visible: the story's own
  acceptance criteria says "Tech progress shown with progress bar" —
  mirroring the `city-production-progress` convention `GameLive.
  CityPanel` already ships for production (story 879).

  See `Criterion7625Spex`'s moduledoc for the assumed `TechPanel`
  surface contract this spec (and its siblings) drives.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "research progress is visible" do
    scenario "the current research shows banked/cost with a progress bar" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player selects Animal Husbandry as current research", context do
        render_hook(context.play_live, "toggle_tech_panel", %{})
        render_hook(context.play_live, "select_research", %{"tech" => "animal_husbandry"})
        {:ok, context}
      end

      when_ "three turns pass — 6 of the needed 50 science", context do
        for _ <- 1..3, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the panel shows 6/50 progress with a progress bar", context do
        assert has_element?(context.play_live, "[data-test='research-progress']", "6/50")
        assert has_element?(context.play_live, "[data-test='research-progress-bar']")
        {:ok, context}
      end
    end
  end
end
