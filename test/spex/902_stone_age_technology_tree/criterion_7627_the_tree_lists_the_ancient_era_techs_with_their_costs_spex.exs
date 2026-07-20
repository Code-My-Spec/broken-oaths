defmodule BrokenOathsSpex.Story902.Criterion7627Spex do
  @moduledoc """
  Story 902 — Stone Age Technology Tree
  Criterion 7627 — the tree lists the Ancient-era techs with their
  costs (EXPANDED per playtest issue 133b4893 from the original
  four-tech assertion to the full eleven-tech tree): opening the tech
  tree shows all eleven of `BrokenOaths.Technology.Research.techs/0`
  alongside each one's science cost (`Research.cost/1`) — Pottery (50),
  Animal Husbandry (50), Mining (75), Sailing (90), and Astrology (90)
  with no prerequisite; Writing (90) and Irrigation (90) after Pottery;
  Archery (90) after Animal Husbandry; and Masonry (100), The Wheel
  (100), and Bronze Working (100) after Mining.

  See `Criterion7625Spex`'s moduledoc for the assumed `TechPanel`
  surface contract this spec (and its siblings) drives.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "the tree lists the Ancient-era techs with their costs" do
    scenario "opening the tech tree shows all eleven techs and their costs" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      when_ "the player opens the tech tree", context do
        render_hook(context.play_live, "toggle_tech_panel", %{})
        {:ok, context}
      end

      then_ "the panel lists all eleven Ancient-era techs with their science costs", context do
        assert has_element?(context.play_live, "[data-test='tech-panel']")

        # Tier 1 — no prerequisite.
        assert has_element?(context.play_live, "[data-test='tech-pottery']")
        assert has_element?(context.play_live, "[data-test='tech-cost-pottery']", "50")

        assert has_element?(context.play_live, "[data-test='tech-animal_husbandry']")
        assert has_element?(context.play_live, "[data-test='tech-cost-animal_husbandry']", "50")

        assert has_element?(context.play_live, "[data-test='tech-mining']")
        assert has_element?(context.play_live, "[data-test='tech-cost-mining']", "75")

        assert has_element?(context.play_live, "[data-test='tech-sailing']")
        assert has_element?(context.play_live, "[data-test='tech-cost-sailing']", "90")

        assert has_element?(context.play_live, "[data-test='tech-astrology']")
        assert has_element?(context.play_live, "[data-test='tech-cost-astrology']", "90")

        # After Pottery.
        assert has_element?(context.play_live, "[data-test='tech-writing']")
        assert has_element?(context.play_live, "[data-test='tech-cost-writing']", "90")
        assert has_element?(context.play_live, "[data-test='tech-prereqs-writing']", "Pottery")

        assert has_element?(context.play_live, "[data-test='tech-irrigation']")
        assert has_element?(context.play_live, "[data-test='tech-cost-irrigation']", "90")

        assert has_element?(
                 context.play_live,
                 "[data-test='tech-prereqs-irrigation']",
                 "Pottery"
               )

        # After Animal Husbandry.
        assert has_element?(context.play_live, "[data-test='tech-archery']")
        assert has_element?(context.play_live, "[data-test='tech-cost-archery']", "90")

        assert has_element?(
                 context.play_live,
                 "[data-test='tech-prereqs-archery']",
                 "Animal Husbandry"
               )

        # After Mining.
        assert has_element?(context.play_live, "[data-test='tech-masonry']")
        assert has_element?(context.play_live, "[data-test='tech-cost-masonry']", "100")
        assert has_element?(context.play_live, "[data-test='tech-prereqs-masonry']", "Mining")

        assert has_element?(context.play_live, "[data-test='tech-the_wheel']")
        assert has_element?(context.play_live, "[data-test='tech-cost-the_wheel']", "100")

        assert has_element?(
                 context.play_live,
                 "[data-test='tech-prereqs-the_wheel']",
                 "Mining"
               )

        assert has_element?(context.play_live, "[data-test='tech-bronze_working']")
        assert has_element?(context.play_live, "[data-test='tech-cost-bronze_working']", "100")

        assert has_element?(
                 context.play_live,
                 "[data-test='tech-prereqs-bronze_working']",
                 "Mining"
               )

        {:ok, context}
      end
    end
  end
end
