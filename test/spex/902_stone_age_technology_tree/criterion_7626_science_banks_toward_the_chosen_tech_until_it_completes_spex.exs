defmodule BrokenOathsSpex.Story902.Criterion7626Spex do
  @moduledoc """
  Story 902 — Stone Age Technology Tree
  Criterion 7626 — science banks toward the chosen tech until it
  completes: every turn's science income accumulates against
  `current_research` (`BrokenOaths.Technology.Research.accrue/2`), and the
  tech only flips into `completed_techs` once its full cost is banked
  (`Research.complete/1`) — partial progress stays visibly partial in
  the meantime, never jumping straight to done.

  See `Criterion7625Spex`'s moduledoc for the assumed `TechPanel`
  surface contract this spec (and its siblings) drives.

  Turn math note: science income is population-based
  (`Research.science_per_turn/1`, `2 * size`), and this scenario's
  `a_founded_city` already grows on its own (`Game.Yields.grow/3`,
  story 880's canonical 20/30/40 thresholds — see
  `.code_my_spec/knowledge/stone_age_yields.md`) — a founded city is
  NOT static at size 1 the way a naive "50 cost / 2 per turn = 25
  turns" estimate would assume. For this scenario's deterministic
  world (`given_(:a_world)`'s fixed seed), banked science after N
  turns of continuous Animal Husbandry research is: 2, 4, 6, 8, 12, 16,
  20, 24, 30, 36, 42, 48, 56 for turns 1-13 — the Stone Age size cap
  (4) is reached by turn 12, and the 50-cost tech completes on turn 13
  (banking 56, past cost) rather than turn 25. 11 turns (42, still
  under cost) and 13 turns (56, past cost) are this scenario's own
  checkpoints, chosen empirically against that exact curve.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "science banks toward the chosen tech until it completes" do
    scenario "Animal Husbandry (50 science) stays 'banked, not done' until the 13th turn" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player selects Animal Husbandry as current research", context do
        render_hook(context.play_live, "toggle_tech_panel", %{})
        render_hook(context.play_live, "select_research", %{"tech" => "animal_husbandry"})
        {:ok, context}
      end

      when_ "eleven turns pass — 42 of the needed 50 science (the city has already grown)",
            context do
        for _ <- 1..11, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "progress reads 42/50, and Animal Husbandry is not yet completed", context do
        assert has_element?(context.play_live, "[data-test='research-progress']", "42/50")
        refute has_element?(context.play_live, "[data-test='tech-completed-animal_husbandry']")
        {:ok, context}
      end

      when_ "two more turns pass, banking past the 50 science cost", context do
        for _ <- 1..2, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "Animal Husbandry is now completed", context do
        assert has_element?(context.play_live, "[data-test='tech-completed-animal_husbandry']")
        {:ok, context}
      end
    end
  end
end
