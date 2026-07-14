defmodule BrokenOathsSpex.Story873.Criterion7414Spex do
  @moduledoc """
  Story 873 — New Player Spawns in World
  Criterion 7414 — joining is idempotent — re-entry shows existing state, never a second spawn.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "re-entering a joined world never re-spawns" do
    scenario "refresh and picker re-entry preserve the civilization" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player has joined and knows their units", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        units = Fixtures.player_units(context.world, context.user)
        {:ok, Map.put(context, :original_units, Enum.sort_by(units, & &1.id))}
      end

      when_ "they open the world again through the picker", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, _play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        {:ok, context}
      end

      then_ "they still own exactly the same units and one region", context do
        units = Enum.sort_by(Fixtures.player_units(context.world, context.user), & &1.id)
        assert units == context.original_units
        assert Fixtures.claimed_region(context.world, context.user) != nil
        {:ok, context}
      end
    end
  end
end
