defmodule BrokenOathsSpex.Story902.Criterion7627Spex do
  @moduledoc """
  Story 902 — Stone Age Technology Tree
  Criterion 7627 — the tree lists the four Stone Age techs with costs:
  opening the tech tree shows all of `BrokenOaths.Game.Research.techs/0`
  (Animal Husbandry, Pottery, Mining, Bronze Working) alongside each
  one's science cost (`Research.cost/1` — 50 / 50 / 75 / 100).

  See `Criterion7625Spex`'s moduledoc for the assumed `TechPanel`
  surface contract this spec (and its siblings) drives.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "the tree lists the four Stone Age techs with costs" do
    scenario "opening the tech tree shows all four techs and their costs" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      when_ "the player opens the tech tree", context do
        render_hook(context.play_live, "toggle_tech_panel", %{})
        {:ok, context}
      end

      then_ "the panel lists all four Stone Age techs with their science costs", context do
        assert has_element?(context.play_live, "[data-test='tech-panel']")

        assert has_element?(context.play_live, "[data-test='tech-animal_husbandry']")
        assert has_element?(context.play_live, "[data-test='tech-cost-animal_husbandry']", "50")

        assert has_element?(context.play_live, "[data-test='tech-pottery']")
        assert has_element?(context.play_live, "[data-test='tech-cost-pottery']", "50")

        assert has_element?(context.play_live, "[data-test='tech-mining']")
        assert has_element?(context.play_live, "[data-test='tech-cost-mining']", "75")

        assert has_element?(context.play_live, "[data-test='tech-bronze_working']")
        assert has_element?(context.play_live, "[data-test='tech-cost-bronze_working']", "100")

        {:ok, context}
      end
    end
  end
end
