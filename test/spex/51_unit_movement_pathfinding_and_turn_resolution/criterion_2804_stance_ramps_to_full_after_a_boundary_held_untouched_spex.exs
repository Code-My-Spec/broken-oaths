defmodule BrokenOathsSpex.Story953.Criterion2804Spex do
  use BrokenOathsSpex.Case
  import BrokenOathsSpex.SharedGivens

  spex "fortify ramps after an untouched boundary" do
    scenario "a partially fortified defender holds its tile for a turn" do
      given_(:a_world)
      given_(:registered_player)
      given_ "the player has a unit at the partial fortify stance", context, do: {:ok, context}
      when_ "a turn boundary resolves without the unit acting", context, do: {:ok, context}
      then_ "the unit reaches its full fortify stance", context, do: {:ok, context}
    end
  end
end
