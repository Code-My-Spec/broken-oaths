defmodule BrokenOathsSpex.Story953.Criterion2805Spex do
  use BrokenOathsSpex.Case
  import BrokenOathsSpex.SharedGivens

  spex "a blocked step preserves fortify" do
    scenario "a fortified unit's ordered step is occupied" do
      given_(:a_world)
      given_(:registered_player)
      given_ "the player has a fortified unit whose next tile is occupied", context, do: {:ok, context}
      when_ "the unit attempts its blocked step", context, do: {:ok, context}
      then_ "the unit remains fortified because it did not move", context, do: {:ok, context}
    end
  end
end
