defmodule BrokenOathsSpex.Story953.Criterion2799Spex do
  use BrokenOathsSpex.Case
  import BrokenOathsSpex.SharedGivens

  spex "a broken enemy city permits a walk-in" do
    scenario "an attacker enters a broken enemy city despite its fallen garrison" do
      given_(:a_world)
      given_(:registered_player)
      given_ "an enemy city is broken and still contains its fallen garrison", context, do: {:ok, context}
      when_ "an enemy unit moves onto the broken city tile", context, do: {:ok, context}
      then_ "the movement is allowed rather than blocked by the garrison", context, do: {:ok, context}
    end
  end
end
