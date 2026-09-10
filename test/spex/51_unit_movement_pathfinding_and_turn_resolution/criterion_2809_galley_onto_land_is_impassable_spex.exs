defmodule BrokenOathsSpex.Story953.Criterion2809Spex do
  use BrokenOathsSpex.Case
  import BrokenOathsSpex.SharedGivens

  spex "a galley cannot enter land" do
    scenario "a galley targets an adjacent land tile" do
      given_(:a_world)
      given_(:registered_player)
      given_ "the player has a galley beside land", context, do: {:ok, context}
      when_ "the player orders the galley onto land", context, do: {:ok, context}
      then_ "the order is rejected as impassable", context, do: {:ok, context}
    end
  end
end
