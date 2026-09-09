defmodule BrokenOathsSpex.Story953.Criterion2797Spex do
  use BrokenOathsSpex.Case
  import BrokenOathsSpex.SharedGivens

  spex "a civilian and combat escort share an open tile" do
    scenario "a friendly civilian joins one friendly combat unit in the field" do
      given_(:a_world)
      given_(:registered_player)
      given_ "the player has a civilian beside a friendly combat escort on open ground", context, do: {:ok, context}
      when_ "the civilian moves onto the escort tile", context, do: {:ok, context}
      then_ "both friendly units occupy the open tile", context, do: {:ok, context}
    end
  end
end
