defmodule BrokenOathsSpex.Story903.Criterion7636Spex do
  @moduledoc """
  Story 903 — Advancing to Bronze Age
  Criterion 7636 — a player who has NOT researched Bronze Working still
  caps at city size 4, even with abundant food and unlimited turns.
  This is 903's own regression guard: the size-6 cap this story
  introduces (criterion 7635) must be conditional on
  `BrokenOaths.Technology.Research.age/1` returning `:bronze_age`, not a flat
  raise that would also lift the cap for Stone Age players. Source:
  stone_age.md §2.3 ("Maximum city size in Stone Age: 4") read
  alongside §6.2 ("Cities can now grow to size 6 (up from size 4)")
  under the SAME MVP success criterion #6 ("Bronze Age units are
  noticeably stronger... " implies Stone Age ones, including the
  city cap, are not).

  Unlike every other criterion in this story, this one needs no Bronze
  Age at all — the player never touches research and stays Stone Age
  by construction. This scenario mirrors
  `BrokenOathsSpex.Story880.Criterion7477Spex`'s own proven setup
  almost exactly (that spec already covers "a size-4 city stops growing
  until the age turns"); it is written independently here as story
  903's own acceptance criterion rather than assumed covered by 880's
  test, per the instruction to write one spec per criterion actually on
  the story.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a Stone Age city still caps at 4" do
    scenario "abundant food income never grows a Stone Age city past size 4" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "my city has grown to the Stone Age cap of size 4", context do
        Enum.reduce_while(1..300, :ok, fn _, :ok ->
          [city] =
            for c <- Fixtures.player_cities(context.world, context.user),
                c.id == context.city.id,
                do: c

          if city.size >= 4 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok, context}
      end

      when_ "many more turn boundaries pass, still with abundant food income", context do
        for _ <- 1..40, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the city remains size 4 — it never crosses into the Bronze Age's size-6 cap",
            context do
        [city] =
          for c <- Fixtures.player_cities(context.world, context.user),
              c.id == context.city.id,
              do: c

        assert city.size == 4
        {:ok, context}
      end
    end
  end
end
