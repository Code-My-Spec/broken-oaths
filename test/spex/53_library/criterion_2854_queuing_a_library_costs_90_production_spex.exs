defmodule BrokenOathsSpex.Story955.Criterion2854Spex do
  @moduledoc """
  Story 955 — Library
  Criterion 2854 — queuing a Library costs 90 production: the same
  figure `BrokenOaths.Cities.Production`'s own catalog declares for
  `:library`, shown right on the production option button before the
  player ever queues it.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "queuing a Library costs 90 production" do
    scenario "the Library option shows a cost of 90" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city_with_writing)

      when_ "the player views the Library production option", context do
        {:ok, context}
      end

      then_ "it shows a cost of 90", context do
        assert has_element?(context.play_live, "[data-test='production-option-library']", "90")

        {:ok, context}
      end
    end
  end
end
