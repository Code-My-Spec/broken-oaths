defmodule BrokenOathsSpex.Story953.Criterion2800Spex do
  use BrokenOathsSpex.Case
  import BrokenOathsSpex.SharedGivens

  spex "a full field stack blocks another matching class" do
    scenario "a second civilian or same-class unit tries to enter an occupied field tile" do
      given_(:a_world)
      given_(:registered_player)
      given_ "one friendly unit already occupies an open field tile", context, do: {:ok, context}
      when_ "another civilian or unit of the same combat class moves there", context, do: {:ok, context}
      then_ "the second unit is blocked and keeps its position", context, do: {:ok, context}
    end
  end
end
