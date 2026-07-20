defmodule BrokenOathsSpex.Story902.Criterion7629Spex do
  @moduledoc """
  Story 902 — Stone Age Technology Tree
  Criterion 7629 — Pottery unlocks the granary: completing Pottery
  grants its unlock, "Enables the Granary building (+2 food storage)"
  (`BrokenOaths.Technology.Research.unlock_description(:pottery)`,
  read back via `Research.granary_enabled?/1`).

  The Granary BUILDING itself has no production-catalog entry yet
  (`BrokenOaths.Cities.Production.catalog/0` is `settler`/`worker`/
  `warrior` only) and no story has been imported for it — exactly the
  same "unlock flips a flag, the consuming feature ships separately"
  status `Research`'s own moduledoc documents for Animal Husbandry's
  Pasture (deferred to story 905). This spec drives what IS observable
  at the `TechPanel` surface right now: Pottery completing, and its
  granary unlock confirmed in the panel.

  See `Criterion7625Spex`'s moduledoc for the assumed `TechPanel`
  surface contract this spec (and its siblings) drives.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Pottery unlocks the granary" do
    scenario "completing Pottery confirms the granary unlock in the tech panel" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player selects Pottery as current research", context do
        render_hook(context.play_live, "toggle_tech_panel", %{})
        render_hook(context.play_live, "select_research", %{"tech" => "pottery"})
        {:ok, context}
      end

      when_ "twenty-five turns pass — the full 50 science cost at 2/turn", context do
        for _ <- 1..25, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "Pottery is completed and its granary unlock is shown", context do
        assert has_element?(context.play_live, "[data-test='tech-completed-pottery']")
        assert has_element?(context.play_live, "[data-test='tech-unlock-pottery']", "Granary")
        {:ok, context}
      end
    end
  end
end
