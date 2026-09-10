defmodule BrokenOathsSpex.Story953.Criterion2801Spex do
  use BrokenOathsSpex.Case
  import BrokenOathsSpex.SharedGivens

  spex "a healthy garrisoned enemy city stays blocked" do
    scenario "an attacker attempts to enter an intact enemy city" do
      given_(:a_world)
      given_(:registered_player)
      given_ "an enemy city is healthy and has a garrison", context, do: {:ok, context}
      when_ "the attacker orders a move onto the city tile", context, do: {:ok, context}
      then_ "the attacker cannot walk into the city", context, do: {:ok, context}
    end
  end
end
