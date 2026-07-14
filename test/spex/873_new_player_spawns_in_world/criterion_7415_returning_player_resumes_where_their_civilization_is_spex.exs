defmodule BrokenOathsSpex.Story873.Criterion7415Spex do
  @moduledoc """
  Story 873 — New Player Spawns in World
  Criterion 7415 — a returning player lands on their world with the camera on their civilization.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "returning player resumes where their civilization is" do
    scenario "the board opens centered on their units" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player joined the world earlier", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, context}
      end

      when_ "they come back and open the world", context do
        {:ok, play_live, html} = live(context.conn, ~p"/play/#{context.world.id}")
        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:html, html)}
      end

      then_ "the camera is centered on their spawn", context do
        [unit | _] = Fixtures.player_units(context.world, context.user)

        # The board mounts with camera params aimed at the player's units:
        # the stage carries the centered coordinates it was mounted with.
        assert [_, yaw] = Regex.run(~r/data-yaw="([-0-9.]+)"/, context.html)
        assert [_, pitch] = Regex.run(~r/data-pitch="([-0-9.]+)"/, context.html)
        assert is_binary(yaw) and is_binary(pitch)

        # And their units are in the visible window pushed to the board
        assert_push_event(context.play_live, "game:units", %{units: units})
        assert Enum.any?(units, &(&1.id == unit.id))
        {:ok, context}
      end
    end
  end
end
