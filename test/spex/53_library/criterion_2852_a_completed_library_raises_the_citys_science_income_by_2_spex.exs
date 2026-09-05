defmodule BrokenOathsSpex.Story955.Criterion2852Spex do
  @moduledoc """
  Story 955 — Library
  Criterion 2852 — a completed Library raises the city's science
  income by 2: a flat, additive bonus
  (`BrokenOaths.Technology.Research.library_science_bonus/0`), visible
  in the tech panel's own science-per-turn readout.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "a completed Library raises the city's science income by 2" do
    scenario "science/turn rises by 2 once the Library completes" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city_with_writing)

      given_ "the player reads their science income before building a Library", context do
        html = render(context.play_live)

        [before_science] =
          Regex.run(~r/data-test="science-per-turn"[^>]*>\s*(\d+)/, html, capture: :all_but_first)

        {:ok, Map.put(context, :science_before, String.to_integer(before_science))}
      end

      when_ "the player queues and completes a Library", context do
        context.play_live
        |> element("[data-test='production-option-library']")
        |> render_click()

        advance_until_building_complete(context.world, context.user, context.city.id, :library)

        {:ok, context}
      end

      then_ "the city's science income is now 2 higher", context do
        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")
        render_hook(play_live, "toggle_tech_panel", %{})
        html = render(play_live)

        [after_science] =
          Regex.run(~r/data-test="science-per-turn"[^>]*>\s*(\d+)/, html, capture: :all_but_first)

        assert String.to_integer(after_science) == context.science_before + 2

        {:ok, context}
      end
    end
  end
end
