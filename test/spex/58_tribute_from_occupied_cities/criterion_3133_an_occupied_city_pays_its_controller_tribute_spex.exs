defmodule BrokenOathsSpex.Story998.Criterion3133Spex do
  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens
  alias BrokenOathsSpex.Fixtures

  spex "an occupied city pays its controller tribute" do
    scenario "the occupier receives tribute at the next turn boundary" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "I occupy the rival's city", context do
        {:ok, a_freshly_subjugated_vassal(context)}
      end

      when_ "tribute is collected at the turn boundary", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the occupied city reports tribute received by its controller", context do
        assert has_element?(context.play_live, "[data-test='vassal-row-#{context.other_user.id}'] [data-test='tribute-received']")
        {:ok, context}
      end
    end
  end
end
