defmodule BrokenOathsSpex.Story955.Criterion2853Spex do
  @moduledoc """
  Story 955 — Library
  Criterion 2853 — the Library catalog entry states its own
  maintenance cost: `BrokenOaths.Cities.Buildings` declares 1 gold/turn
  for `:library` (the building-convention guardrail — 0 is allowed,
  but an omission is not). There is no UI surface that displays a
  building's declared upkeep value directly, so this is proven through
  its only player-observable consequence: the net gold/turn readout
  (`progress-gold-per-turn`, already income minus maintenance) drops by
  EXACTLY 1 once a Library completes, isolating the Library's own
  declared contribution regardless of the city's own base income.
  Distinct from criterion 2856, which proves the general mechanism
  (deduction happens, nets alongside unit upkeep) rather than pinning
  the exact declared number.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "the Library catalog entry states its own maintenance cost" do
    scenario "net gold/turn drops by exactly 1 once a Library completes" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city_with_writing)

      given_ "the player reads their net gold/turn before building a Library", context do
        [before_gold] =
          Regex.run(
            ~r/data-test="progress-gold-per-turn"[^>]*>\s*([+-]?\d+)/,
            render(context.play_live),
            capture: :all_but_first
          )

        {:ok, Map.put(context, :gold_per_turn_before, String.to_integer(before_gold))}
      end

      when_ "the player queues and completes a Library", context do
        context.play_live
        |> element("[data-test='production-option-library']")
        |> render_click()

        advance_until_building_complete(context.world, context.user, context.city.id, :library)

        {:ok, context}
      end

      then_ "net gold/turn is now exactly 1 lower, the Library's own declared maintenance", context do
        {:ok, play_live, html} = live(context.conn, "/play/#{context.world.id}")

        [after_gold] =
          Regex.run(~r/data-test="progress-gold-per-turn"[^>]*>\s*([+-]?\d+)/, html,
            capture: :all_but_first
          )

        assert String.to_integer(after_gold) == context.gold_per_turn_before - 1
        {:ok, Map.put(context, :play_live, play_live)}
      end
    end
  end
end
