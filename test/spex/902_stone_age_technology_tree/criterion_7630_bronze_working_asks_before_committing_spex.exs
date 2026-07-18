defmodule BrokenOathsSpex.Story902.Criterion7630Spex do
  @moduledoc """
  Story 902 — Stone Age Technology Tree
  Criterion 7630 — Bronze Working asks before committing: selecting it
  as current research must first surface the warning "This will advance
  you to Bronze Age. Continue?" (the story's own acceptance criteria
  text) and only actually select it once the player confirms —
  cancelling leaves nothing selected.

  EXPANDED per playtest issue 133b4893: Bronze Working now requires
  Mining as a prerequisite (`Research.prereqs/1`), so both scenarios
  research Mining to completion first — clicking `tech-bronze_working`
  before Mining is done is a silent no-op (it's `:locked`, see
  `Criterion7710Spex`), not a path to this warning at all.

  See `Criterion7625Spex`'s moduledoc for the assumed `TechPanel`
  surface contract this spec (and its siblings) drives, including the
  `bronze-working-warning` / `bronze-working-confirm` /
  `bronze-working-cancel` two-step confirm flow.

  Structure note: the "confirms" and "cancels" facts are independently
  verifiable claims, so each gets its own `spex`/`scenario` pair rather
  than two `scenario` blocks sharing one `spex` — same reasoning
  `BrokenOathsSpex.Story894.Criterion7559Spex`'s moduledoc documents.
  `SexySpex.DSL.spex/2` compiles to exactly one `ExUnit` `test`, and
  `scenario/1` only resets the step context inside that same test — it
  does not start a new one, and therefore does not start a fresh DB
  sandbox transaction either. Two `scenario`s sharing one `spex` would
  both call `given_(:a_world)`'s fixed `seed: 424_242` world fixture
  inside the SAME transaction, and the second call would collide with
  the first's still-uncommitted-but-visible row on the `worlds_seed_
  index` unique constraint. Two `spex` blocks each get their own test
  (and sandbox transaction), avoiding that collision entirely.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Bronze Working asks first, and confirming commits it" do
    scenario "picking Bronze Working warns first, and confirming commits it" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player has already researched Mining, Bronze Working's prerequisite",
             context do
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

        assert has_element?(context.play_live, "[data-test='tech-completed-mining']")
        {:ok, context}
      end

      when_ "the player picks Bronze Working", context do
        render_hook(context.play_live, "select_research", %{"tech" => "bronze_working"})
        {:ok, context}
      end

      then_ "a warning appears, and nothing is committed yet", context do
        assert has_element?(
                 context.play_live,
                 "[data-test='bronze-working-warning']",
                 "This will advance you to Bronze Age. Continue?"
               )

        refute has_element?(context.play_live, "[data-test='research-progress']")
        {:ok, context}
      end

      when_ "the player confirms", context do
        render_hook(context.play_live, "bronze_working_confirm", %{})
        {:ok, context}
      end

      then_ "Bronze Working becomes the current research", context do
        assert has_element?(
                 context.play_live,
                 "[data-test='research-progress']",
                 "Bronze Working"
               )

        {:ok, context}
      end
    end
  end

  spex "cancelling the Bronze Working warning leaves nothing selected" do
    scenario "cancelling the warning leaves nothing selected" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player has already researched Mining, Bronze Working's prerequisite",
             context do
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

        assert has_element?(context.play_live, "[data-test='tech-completed-mining']")
        {:ok, context}
      end

      when_ "the player picks Bronze Working, then cancels the warning", context do
        render_hook(context.play_live, "select_research", %{"tech" => "bronze_working"})
        render_hook(context.play_live, "bronze_working_cancel", %{})
        {:ok, context}
      end

      then_ "the warning is gone and no research is selected", context do
        refute has_element?(context.play_live, "[data-test='bronze-working-warning']")
        refute has_element?(context.play_live, "[data-test='research-progress']")
        {:ok, context}
      end
    end
  end
end
