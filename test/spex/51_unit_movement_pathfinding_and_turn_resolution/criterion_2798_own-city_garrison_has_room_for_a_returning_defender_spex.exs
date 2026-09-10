defmodule BrokenOathsSpex.Story953.Criterion2798Spex do
  use BrokenOathsSpex.Case
  import BrokenOathsSpex.SharedGivens

  spex "an own-city garrison has room for a returning defender" do
    scenario "a friendly defender returns to its owner's city" do
      given_(:a_world)
      given_(:registered_player)
      given_ "the player has a city and a defender adjacent to it", context, do: {:ok, context}
      when_ "the defender moves onto the friendly city tile", context, do: {:ok, context}
      then_ "the defender joins the city garrison when capacity remains", context, do: {:ok, context}
    end
  end
end
