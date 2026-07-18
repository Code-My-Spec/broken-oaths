defmodule BrokenOathsSpex.Story903.Criterion7635Spex do
  @moduledoc """
  Story 903 — Advancing to Bronze Age
  Criterion 7635 — reaching the Bronze Age raises the city size cap
  from 4 to 6. Source: stone_age.md §6.2 — "Cities can now grow to size
  6 (up from size 4)." The Stone Age cap itself (size 4) is story 880's
  own rule (§2.3: "Maximum city size in Stone Age: 4 (Bronze Age
  unlocks larger cities)"), already exercised by
  `BrokenOathsSpex.Story880.Criterion7477Spex` ("a size-4 city stops
  growing until the age turns" — that spec's own title names story 903
  as the thing that lifts it).

  Reaching the Bronze Age rides on story 902's `TechPanel` — see
  `BrokenOathsSpex.SharedGivens`'s `:player_reached_bronze_age`
  moduledoc for the real `"select_research"` / `"bronze_working_
  confirm"` event flow this given drives.

  Growth math mirrors criterion 7477's own reasoning: food thresholds
  rise with size (20 for size 2, 30 for size 3, ...), so a city with
  abundant food income needs several growth cycles to climb from 1 to
  6 — this spec waits generously (up to 500 turns, above criterion
  7477's own 300-turn bound for reaching just size 4) rather than
  reading banked food directly (no sanctioned read for it; `size`
  itself, via `Fixtures.player_cities/2`, is the only sanctioned
  growth signal).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "cities grow past the Stone Age cap once the Bronze Age is reached" do
    scenario "a Bronze Age city with abundant food grows all the way to size 6" do
      given_(:a_world)
      given_(:registered_player)
      given_(:player_reached_bronze_age)

      when_ "many turn boundaries pass with abundant food income", context do
        Enum.reduce_while(1..500, :ok, fn _, :ok ->
          [city] =
            for c <- Fixtures.player_cities(context.world, context.user),
                c.id == context.city.id,
                do: c

          if city.size >= 6 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok, context}
      end

      then_ "the city has grown past the old Stone Age cap of 4, all the way to size 6",
            context do
        assert context.research_select_result == :ok,
               "selecting/confirming Bronze Working as research failed, so the Bronze Age can never be reached and the size-6 cap never applies"

        [city] =
          for c <- Fixtures.player_cities(context.world, context.user),
              c.id == context.city.id,
              do: c

        assert city.size == 6
        {:ok, context}
      end
    end
  end
end
