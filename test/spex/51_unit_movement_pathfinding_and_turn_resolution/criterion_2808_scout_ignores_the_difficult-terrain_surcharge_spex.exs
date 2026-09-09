defmodule BrokenOathsSpex.Story953.Criterion2808Spex do
  use BrokenOathsSpex.Case
  import BrokenOathsSpex.SharedGivens

  spex "a scout ignores difficult terrain's surcharge" do
    scenario "a scout enters an unroaded difficult land tile" do
      given_(:a_world)
      given_(:registered_player)
      given_ "the player has a scout adjacent to difficult terrain", context, do: {:ok, context}
      when_ "the scout moves into that terrain", context, do: {:ok, context}
      then_ "the step costs one movement rather than two", context, do: {:ok, context}
    end
  end
end
