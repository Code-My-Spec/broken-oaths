defmodule BrokenOathsSpex.Story953.Criterion2803Spex do
  use BrokenOathsSpex.Case
  import BrokenOathsSpex.SharedGivens

  spex "moving clears fortify" do
    scenario "a fortified unit makes a successful move" do
      given_(:a_world)
      given_(:registered_player)
      given_ "the player has a fortified unit beside an open tile", context, do: {:ok, context}
      when_ "the unit moves to the open tile", context, do: {:ok, context}
      then_ "its fortify stance is cleared", context, do: {:ok, context}
    end
  end
end
