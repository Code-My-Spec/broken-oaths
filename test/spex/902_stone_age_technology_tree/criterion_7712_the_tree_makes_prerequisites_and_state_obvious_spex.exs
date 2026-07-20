defmodule BrokenOathsSpex.Story902.Criterion7712Spex do
  @moduledoc """
  Story 902 — Stone Age Technology Tree
  Criterion 7712 — the tree makes prerequisites and state obvious: new
  for the expanded, prerequisite-gated Ancient-era tree (playtest issue
  133b4893, the complaint this whole batch resolves — "if there are
  technology prerequisites they aren't obvious"). Every tech row
  carries both its prerequisite link(s) (`[data-test='tech-prereqs-
  <tech>']`) and exactly one state marker
  (`BrokenOaths.Technology.Research.tech_state/2`): `:completed`, `:in_progress`,
  `:locked`, or (no marker) `:available`.

  This spec reaches a mixed-state tree — Mining completed, Bronze
  Working partway banked — and confirms every named tech reads its
  correct state simultaneously: Mining completed, Bronze Working
  in-progress, its Mining-gated siblings (Masonry, The Wheel) available
  (their own prerequisite link visibly pointing at Mining too), and
  techs from the OTHER branch (Writing, Irrigation, Archery — gated on
  Pottery/Animal Husbandry, neither researched) still locked.

  See `Criterion7625Spex`'s moduledoc for the assumed `TechPanel`
  surface contract this spec (and its siblings) drives.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the tree makes prerequisites and state obvious" do
    scenario "Mining completed and Bronze Working partway through shows every state at once" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player has completed Mining and is partway through Bronze Working", context do
        render_hook(context.play_live, "toggle_tech_panel", %{})
        render_hook(context.play_live, "select_research", %{"tech" => "mining"})

        Enum.reduce_while(1..60, :ok, fn _, :ok ->
          if has_element?(context.play_live, "[data-test='tech-completed-mining']") do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        render_hook(context.play_live, "select_research", %{"tech" => "bronze_working"})
        render_hook(context.play_live, "bronze_working_confirm", %{})

        for _ <- 1..2, do: Fixtures.advance_turn(context.world)

        {:ok, context}
      end

      when_ "the player views the tech tree", context do
        {:ok, context}
      end

      then_ "Mining shows completed, Bronze Working shows in-progress, and Masonry/The Wheel show available",
            context do
        assert has_element?(context.play_live, "[data-test='tech-completed-mining']")
        refute has_element?(context.play_live, "[data-test='tech-locked-mining']")

        assert has_element?(context.play_live, "[data-test='tech-in-progress-bronze_working']")
        refute has_element?(context.play_live, "[data-test='tech-completed-bronze_working']")
        refute has_element?(context.play_live, "[data-test='tech-locked-bronze_working']")

        assert has_element?(
                 context.play_live,
                 "[data-test='research-progress']",
                 "Bronze Working"
               )

        refute has_element?(context.play_live, "[data-test='tech-locked-masonry']")
        refute has_element?(context.play_live, "[data-test='tech-locked-the_wheel']")
        {:ok, context}
      end

      then_ "prerequisite links are drawn from Mining to Masonry, The Wheel, and Bronze Working",
            context do
        assert has_element?(context.play_live, "[data-test='tech-prereqs-masonry']", "Mining")
        assert has_element?(context.play_live, "[data-test='tech-prereqs-the_wheel']", "Mining")

        assert has_element?(
                 context.play_live,
                 "[data-test='tech-prereqs-bronze_working']",
                 "Mining"
               )

        {:ok, context}
      end

      then_ "techs whose prerequisites are unmet are shown dimmed/locked", context do
        assert has_element?(context.play_live, "[data-test='tech-locked-writing']")
        assert has_element?(context.play_live, "[data-test='tech-locked-irrigation']")
        assert has_element?(context.play_live, "[data-test='tech-locked-archery']")

        assert has_element?(
                 context.play_live,
                 "[data-test='tech-writing'][data-disabled='true']"
               )

        {:ok, context}
      end
    end
  end
end
