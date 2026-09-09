defmodule BrokenOathsSpex.Story953.Criterion2810Spex do
  use BrokenOathsSpex.Case
  import BrokenOathsSpex.SharedGivens

  spex "a land unit cannot enter water" do
    scenario "a land unit targets an adjacent coastal-water tile" do
      given_(:a_world)
      given_(:registered_player)
      given_ "the player has a land unit beside coastal water", context, do: {:ok, context}
      when_ "the player orders the land unit onto water", context, do: {:ok, context}
      then_ "the order is rejected as impassable", context, do: {:ok, context}
    end
  end
end
