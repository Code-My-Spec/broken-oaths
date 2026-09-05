defmodule BrokenOathsSpex.Story955.Criterion2850Spex do
  @moduledoc """
  Story 955 — Library
  Criterion 2850 — a city can queue a Library once Writing is
  researched: with Writing complete, the production menu offers a
  Library option, and choosing it enters the city's production queue.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "a city can queue a Library once Writing is researched" do
    scenario "queuing a Library succeeds once Writing is researched" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city_with_writing)

      when_ "the player queues a Library", context do
        context.play_live
        |> element("[data-test='production-option-library']")
        |> render_click()

        {:ok, context}
      end

      then_ "the Library enters the city's production queue", context do
        assert has_element?(
                 context.play_live,
                 "[data-test='city-production-current']",
                 "Library"
               )

        {:ok, context}
      end
    end
  end
end
