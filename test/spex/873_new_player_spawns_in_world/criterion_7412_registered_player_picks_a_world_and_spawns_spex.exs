defmodule BrokenOathsSpex.Story873.Criterion7412Spex do
  @moduledoc """
  Story 873 — New Player Spawns in World
  Criterion 7412 — picking a world with room spawns the player and lands them on the board.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "registered player picks a world and spawns" do
    scenario "the picker join leads to the board" do
      given_(:a_world)
      given_(:registered_player)

      when_ "the player picks the world from the picker", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, context}
      end

      then_ "they are spawned and taken to that world's board", context do
        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        assert has_element?(play_live, "[data-test='turn-number']")
        assert Fixtures.claimed_region(context.world, context.user) != nil
        {:ok, context}
      end
    end
  end
end
