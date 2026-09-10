defmodule BrokenOathsSpex.Story953.Criterion2802Spex do
  use BrokenOathsSpex.Case
  import BrokenOathsSpex.SharedGivens

  spex "fortifying spends no movement" do
    scenario "a defend-capable unit fortifies before moving" do
      given_(:a_world)
      given_(:registered_player)
      given_ "the player has selected a defend-capable unit with movement remaining", context, do: {:ok, context}
      when_ "the player fortifies the unit", context, do: {:ok, context}
      then_ "the unit is fortified and retains all of its movement", context, do: {:ok, context}
    end
  end
end
