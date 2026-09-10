defmodule BrokenOathsSpex.Story1000.Criterion3119Spex do
  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "tribute starts when the capital falls" do
    scenario "the first turn after the last free city falls pays tribute to the new lord" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      when_ "I capture the rival realm's last free city and the next turn resolves", context do
        context = a_freshly_subjugated_vassal(context)
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the lord sees the first tribute payment without waiting for a later vassalization step", context do
        assert has_element?(
                 context.play_live,
                 "[data-test='vassal-row-#{context.other_user.id}'] [data-test='tribute-received']"
               )

        {:ok, context}
      end
    end
  end
end
