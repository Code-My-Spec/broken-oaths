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

  Turn math note: Animal Husbandry costs 80 science
  (`Research.@catalog`'s `animal_husbandry` entry), not 50 — an older
  catalog value this spec's assertions had drifted from. Science
  income is population-based (`Research.science_per_turn/1`, `2 *
  size`), and this scenario's `a_founded_city` already grows on its
  own (`Game.Yields.grow/3`, story 880's canonical 20/30/40 thresholds
  — see `.code_my_spec/knowledge/stone_age_yields.md`) — a founded
  city is NOT static at size 1 the way a naive "80 cost / 2 per turn =
  40 turns" estimate would assume. A turn's science accrues at the
  city's size BEFORE any growth that same turn applies (growth is
  resolved after production/science accrual in the tick pipeline), so
  the turn a city grows still banks at the OLD (lower) size — the new
  size only counts starting the FOLLOWING turn. For this scenario's
  deterministic world (`given_(:a_world)`'s fixed seed), banked science
  after N turns of continuous Animal Husbandry research is: 2, 4, 6, 8,
  12, 16, 20, 24, 28, 34, 40, 46, 52, 60, 68, 76, 84+ for turns 1-17 —
  the Stone Age size cap (4) is reached by turn 13, and the 80-cost
  tech completes on turn 17 (banking 84, past cost). 11 turns (40,
  still under cost) and 17 turns (84, past cost) are this scenario's
  own checkpoints, chosen empirically against that exact curve.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "science banks toward the chosen tech until it completes" do
    scenario "Animal Husbandry (80 science) stays 'banked, not done' until the 17th turn" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player selects Animal Husbandry as current research", context do
        render_hook(context.play_live, "toggle_tech_panel", %{})
        render_hook(context.play_live, "select_research", %{"tech" => "animal_husbandry"})
        {:ok, context}
      end

      when_ "eleven turns pass — 40 of the needed 80 science (the city has already grown)",
            context do
        for _ <- 1..11, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "progress reads 40/80, and Animal Husbandry is not yet completed", context do
        assert has_element?(context.play_live, "[data-test='research-progress']", "40/80")
        refute has_element?(context.play_live, "[data-test='tech-completed-animal_husbandry']")
        {:ok, context}
      end

      when_ "six more turns pass, banking past the 80 science cost", context do
        for _ <- 1..6, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "Animal Husbandry is now completed", context do
        assert has_element?(context.play_live, "[data-test='tech-completed-animal_husbandry']")
        {:ok, context}
      end
    end
  end
end
