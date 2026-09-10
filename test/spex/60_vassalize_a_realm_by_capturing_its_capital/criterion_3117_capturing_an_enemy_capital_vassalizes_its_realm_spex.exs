defmodule BrokenOathsSpex.Story1000.Criterion3117Spex do
  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "capturing an enemy capital vassalizes its realm" do
    scenario "capturing a realm's last free city makes its ruler my vassal" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      when_ "I capture the rival realm's capital, their last free city", context do
        {:ok, a_freshly_subjugated_vassal(context)}
      end

      then_ "the captured realm appears in my Vassals list", context do
        assert has_element?(
                 context.play_live,
                 "[data-test='vassal-row-#{context.other_user.id}']"
               )

        {:ok, context}
      end

      then_ "the defeated ruler sees that they are sworn to me", context do
        assert has_element?(context.other_play_live, "[data-test='vassal-status']")
        {:ok, context}
      end
    end
  end
end
