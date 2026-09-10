defmodule BrokenOathsSpex.Story953.Criterion2807Spex do
  use BrokenOathsSpex.Case
  import BrokenOathsSpex.SharedGivens

  spex "a galley paths over coastal water" do
    scenario "a galley is ordered between adjacent coastal-water tiles" do
      given_(:a_world)
      given_(:registered_player)
      given_ "the player has a galley on coastal water with a coastal-water destination", context, do: {:ok, context}
      when_ "the player queues the water movement order", context, do: {:ok, context}
      then_ "the galley receives a valid path across coastal water", context, do: {:ok, context}
    end
  end
end
