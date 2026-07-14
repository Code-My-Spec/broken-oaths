defmodule BrokenOathsSpex.Story873.Criterion7416Spex do
  @moduledoc """
  Story 873 — New Player Spawns in World
  Criterion 7416 — multiple concurrent memberships, each independently resumable.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "playing in two worlds at once" do
    scenario "joining a second world keeps both resumable" do
      given_ :a_world
      given_ :registered_player

      given_ "a second world exists", context do
        {:ok, Map.put(context, :second_world, Fixtures.world_fixture(%{seed: 515_151}))}
      end

      given_ "the player already plays in the first world", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, context}
      end

      when_ "they join the second world from the picker", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.second_world.id}']")
        |> render_click()

        {:ok, context}
      end

      then_ "both memberships exist and both boards open", context do
        assert Fixtures.claimed_region(context.world, context.user) != nil
        assert Fixtures.claimed_region(context.second_world, context.user) != nil

        {:ok, play1, _} = live(context.conn, ~p"/play/#{context.world.id}")
        {:ok, play2, _} = live(context.conn, ~p"/play/#{context.second_world.id}")
        assert has_element?(play1, "[data-test='turn-number']")
        assert has_element?(play2, "[data-test='turn-number']")
        {:ok, context}
      end
    end
  end
end
