defmodule BrokenOathsSpex.Story902.Criterion7643Spex do
  @moduledoc """
  Story 902 — Stone Age Technology Tree
  Criterion 7643 — Animal Husbandry unlocks pastures on animal
  resources: completing Animal Husbandry grants its unlock, "Enables
  the Pasture improvement (+2 food on animal resources)"
  (`BrokenOaths.Technology.Research.unlock_description(:animal_husbandry)`,
  read back via `Research.pasture_enabled?/1`).

  Placing a Pasture on an actual animal-resource tile is out of scope
  here: no "animal resource" concept exists anywhere in terrain
  generation yet (`BrokenOaths.Worlds.Terrain` has no resource field),
  and `Research`'s own moduledoc explicitly defers the Pasture
  improvement itself to story 905 ("story 905 (Pasture/resources)
  should read `pasture_enabled?/1`"). This spec drives what IS
  observable at the `TechPanel` surface right now: Animal Husbandry
  completing, and its pasture unlock confirmed in the panel — the same
  "unlock flips a flag, the consuming feature ships separately" split
  `Criterion7629Spex` documents for Pottery/Granary.

  See `Criterion7625Spex`'s moduledoc for the assumed `TechPanel`
  surface contract this spec (and its siblings) drives.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Animal Husbandry unlocks pastures on animal resources" do
    scenario "completing Animal Husbandry confirms the pasture unlock in the tech panel" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player selects Animal Husbandry as current research", context do
        render_hook(context.play_live, "toggle_tech_panel", %{})
        render_hook(context.play_live, "select_research", %{"tech" => "animal_husbandry"})
        {:ok, context}
      end

      when_ "twenty-five turns pass — the full 50 science cost at 2/turn", context do
        for _ <- 1..25, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "Animal Husbandry is completed and its pasture unlock is shown", context do
        assert has_element?(context.play_live, "[data-test='tech-completed-animal_husbandry']")

        assert has_element?(
                 context.play_live,
                 "[data-test='tech-unlock-animal_husbandry']",
                 "Pasture"
               )

        {:ok, context}
      end
    end
  end
end
