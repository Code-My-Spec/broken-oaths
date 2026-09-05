defmodule BrokenOathsSpex.Story955.Criterion2856Spex do
  @moduledoc """
  Story 955 — Library
  Criterion 2856 — a Library's upkeep is deducted from its owner's
  gold at the turn boundary, alongside unit upkeep: proven here with a
  Scout (1 gold/turn, story 952) also in play, so the net gold/turn
  readout (`progress-gold-per-turn`, already income minus maintenance)
  is shown dropping by BOTH sources together in one settlement, not
  just the Library in isolation (criterion 2853's own narrower angle).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a Library's upkeep is deducted from its owner's gold at the turn boundary" do
    scenario "net gold/turn drops by the combined Library and Scout upkeep" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city_with_writing)

      given_ "the player reads their net gold/turn before building anything", context do
        [before_gold] =
          Regex.run(
            ~r/data-test="progress-gold-per-turn"[^>]*>\s*([+-]?\d+)/,
            render(context.play_live),
            capture: :all_but_first
          )

        {:ok, Map.put(context, :gold_per_turn_before, String.to_integer(before_gold))}
      end

      given_ "the player queues and completes a Library", context do
        context.play_live
        |> element("[data-test='production-option-library']")
        |> render_click()

        advance_until_building_complete(context.world, context.user, context.city.id, :library)

        {:ok, context}
      end

      when_ "the player also queues and completes a Scout", context do
        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")
        render_hook(play_live, "select_city", %{"city_id" => to_string(context.city.id)})

        play_live
        |> element("[data-test='production-option-scout']")
        |> render_click()

        Enum.reduce_while(1..200, :ok, fn _, :ok ->
          units = Fixtures.player_units(context.world, context.user)

          if Enum.any?(units, &(&1.type == :scout)) do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok, Map.put(context, :play_live, play_live)}
      end

      then_ "net gold/turn is now 2 lower — the Library's 1 gold plus the Scout's 1 gold", context do
        {:ok, play_live, html} = live(context.conn, "/play/#{context.world.id}")

        [after_gold] =
          Regex.run(~r/data-test="progress-gold-per-turn"[^>]*>\s*([+-]?\d+)/, html,
            capture: :all_but_first
          )

        assert String.to_integer(after_gold) == context.gold_per_turn_before - 2
        {:ok, Map.put(context, :play_live, play_live)}
      end
    end
  end
end
