defmodule BrokenOathsSpex.Story873.Criterion7418Spex do
  @moduledoc """
  Story 873 — New Player Spawns in World
  Criterion 7418 — a fresh spawn starts with exactly 50 gold, visible on the board.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "fresh spawn shows 50 gold" do
    scenario "the gold readout says 50" do
      given_ :a_world
      given_ :registered_player

      when_ "the player joins and the board loads", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :play_live, play_live)}
      end

      then_ "their gold reads exactly 50", context do
        assert has_element?(context.play_live, "[data-test='player-gold']", "50")
        {:ok, context}
      end
    end
  end
end
