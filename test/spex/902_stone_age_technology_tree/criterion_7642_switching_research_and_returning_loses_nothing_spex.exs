defmodule BrokenOathsSpex.Story902.Criterion7642Spex do
  @moduledoc """
  Story 902 — Stone Age Technology Tree
  Criterion 7642 — switching research and returning loses nothing:
  `BrokenOaths.Technology.Research` banks science per-tech
  (`banked_science: %{tech => amount}`), not against a single shared
  counter, so switching `current_research` away and back
  (`Research.set_research/2`) must never discard progress already
  banked toward the tech being left — resuming it later picks up
  exactly where it left off.

  See `Criterion7625Spex`'s moduledoc for the assumed `TechPanel`
  surface contract this spec (and its siblings) drives.

  Turn math note: see `Criterion7626Spex`'s moduledoc for why this
  scenario's `a_founded_city` doesn't bank a flat 2 science/turn — the
  city grows on its own (story 880's canonical thresholds), raising
  its science income as it does. For this scenario's deterministic
  world, 7 turns of continuous Animal Husbandry research banks exactly
  20 science (2, 4, 6, 8, 12, 16, 20) — this scenario's own empirically
  chosen checkpoint against that curve, landing on the same "20"
  banked figure this criterion's story text illustrates.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "switching research and returning loses nothing" do
    scenario "Animal Husbandry's banked science survives a detour through Pottery" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "the player banks 20 science toward Animal Husbandry", context do
        render_hook(context.play_live, "toggle_tech_panel", %{})
        render_hook(context.play_live, "select_research", %{"tech" => "animal_husbandry"})
        for _ <- 1..7, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      when_ "the player switches to Pottery and banks more science there", context do
        render_hook(context.play_live, "select_research", %{"tech" => "pottery"})
        for _ <- 1..5, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "switching back to Animal Husbandry shows its progress untouched at 20/50", context do
        render_hook(context.play_live, "select_research", %{"tech" => "animal_husbandry"})
        assert has_element?(context.play_live, "[data-test='research-progress']", "20/50")
        {:ok, context}
      end
    end
  end
end
