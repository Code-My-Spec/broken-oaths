defmodule BrokenOathsSpex.Story953.Criterion2806Spex do
  use BrokenOathsSpex.Case
  import BrokenOathsSpex.SharedGivens

  spex "fortify is rejected for a non-defend-capable unit" do
    scenario "a player attempts to fortify a unit without a defend action" do
      given_(:a_world)
      given_(:registered_player)
      given_ "the player controls a non-defend-capable unit", context, do: {:ok, context}
      when_ "the player requests fortify", context, do: {:ok, context}
      then_ "the game rejects the action and leaves the stance unchanged", context, do: {:ok, context}
    end
  end
end
