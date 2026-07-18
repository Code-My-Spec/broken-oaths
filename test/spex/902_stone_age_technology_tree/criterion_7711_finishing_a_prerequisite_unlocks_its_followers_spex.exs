defmodule BrokenOathsSpex.Story902.Criterion7711Spex do
  @moduledoc """
  Story 902 — Stone Age Technology Tree
  Criterion 7711 — finishing a prerequisite unlocks its followers: new
  for the expanded, prerequisite-gated Ancient-era tree (playtest issue
  133b4893). The moment a prerequisite tech completes,
  `BrokenOaths.Game.Research.tech_state/2` immediately flips every one
  of its dependents from `:locked` to `:available` — no separate
  unlock step, since the state is derived live from `completed_techs`
  (the same "one source of truth" the module's own moduledoc documents
  for `age/1`/`granary_enabled?/1`).

  This spec completes Pottery and confirms Writing/Irrigation (its two
  dependents) both flip to available, while Mining-gated techs (Bronze
  Working, Masonry, The Wheel) — an entirely separate branch of the
  tree — stay locked, since finishing Pottery says nothing about
  Mining.

  See `Criterion7625Spex`'s moduledoc for the assumed `TechPanel`
  surface contract this spec (and its siblings) drives.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "finishing a prerequisite unlocks its followers" do
    scenario "completing Pottery unlocks Writing and Irrigation, but not Mining-gated techs" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player opens the tech tree and researches Pottery to completion", context do
        render_hook(context.play_live, "toggle_tech_panel", %{})
        render_hook(context.play_live, "select_research", %{"tech" => "pottery"})

        for _ <- 1..25, do: Fixtures.advance_turn(context.world)

        assert has_element?(context.play_live, "[data-test='tech-completed-pottery']")
        {:ok, context}
      end

      when_ "the player views the tech tree", context do
        {:ok, context}
      end

      then_ "Writing and Irrigation are now available to research", context do
        refute has_element?(context.play_live, "[data-test='tech-locked-writing']")
        refute has_element?(context.play_live, "[data-test='tech-locked-irrigation']")

        assert has_element?(
                 context.play_live,
                 "[data-test='tech-writing'][data-disabled='false']"
               )

        assert has_element?(
                 context.play_live,
                 "[data-test='tech-irrigation'][data-disabled='false']"
               )

        {:ok, context}
      end

      then_ "Mining-gated techs like Bronze Working remain locked until Mining is also complete",
            context do
        assert has_element?(context.play_live, "[data-test='tech-locked-bronze_working']")
        assert has_element?(context.play_live, "[data-test='tech-locked-masonry']")
        assert has_element?(context.play_live, "[data-test='tech-locked-the_wheel']")
        {:ok, context}
      end
    end
  end
end
