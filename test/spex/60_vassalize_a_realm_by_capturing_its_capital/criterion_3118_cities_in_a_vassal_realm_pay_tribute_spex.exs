defmodule BrokenOathsSpex.Story1000.Criterion3118Spex do
  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "cities in a vassal realm pay tribute" do
    scenario "a vassal city's income is reported as tribute to its lord" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "I have just subjugated the rival's last free city", context do
        {:ok, a_freshly_subjugated_vassal(context)}
      end

      when_ "the realm's next turn resolves", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "my vassals list shows tribute received from that realm's city", context do
        assert has_element?(
                 context.play_live,
                 "[data-test='vassal-row-#{context.other_user.id}'] [data-test='tribute-received']"
               )

        {:ok, context}
      end
    end
  end
end
