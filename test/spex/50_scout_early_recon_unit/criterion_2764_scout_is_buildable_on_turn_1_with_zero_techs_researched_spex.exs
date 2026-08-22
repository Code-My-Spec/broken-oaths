defmodule BrokenOathsSpex.Story952.Criterion2764Spex do
  @moduledoc """
  Story 952 — Scout — early recon unit
  Criterion 2764 — Scout is buildable on turn 1 with zero techs
  researched: unlike Bronze Spearman/Galley/Granary (each gated on a
  completed tech), Scout is `@always_available` in
  `BrokenOaths.Cities.Production` alongside Settler/Worker/Warrior — the
  build option must render immediately after founding, with no tech
  panel interaction and no completed tech anywhere.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "Scout is buildable on turn 1 with zero techs researched" do
    scenario "the build option renders on a freshly founded city with no tech completed" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      when_ "the player selects their freshly founded city", context do
        render_hook(context.play_live, "select_city", %{"city_id" => context.city.id})
        {:ok, context}
      end

      then_ "Build Scout is offered and no tech has been completed", context do
        assert has_element?(context.play_live, "[data-test='production-option-scout']")
        refute has_element?(context.play_live, "[data-test^='tech-completed-']")
        {:ok, context}
      end
    end
  end
end
