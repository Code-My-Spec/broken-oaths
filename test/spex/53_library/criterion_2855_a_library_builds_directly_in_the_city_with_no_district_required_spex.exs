defmodule BrokenOathsSpex.Story955.Criterion2855Spex do
  @moduledoc """
  Story 955 — Library
  Criterion 2855 — a Library builds directly in the city with no
  district or Campus prerequisite: this project has no district layer
  at all, so the Library appears as a plain, immediately-queueable
  production option (like every other buildable) once Writing is
  researched — never rendered with a disabled reason the way a
  district-gated building in Civ 6 would carry.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "a Library builds directly in the city with no district required" do
    scenario "the Library option is plain and immediately queueable" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city_with_writing)

      when_ "the player views their city's production options", context do
        {:ok, context}
      end

      then_ "the Library is offered directly, not disabled by any further requirement", context do
        assert has_element?(
                 context.play_live,
                 "[data-test='production-option-library'][data-disabled='false']"
               )

        refute has_element?(context.play_live, "[data-test='production-disabled-reason-library']")

        {:ok, context}
      end
    end
  end
end
