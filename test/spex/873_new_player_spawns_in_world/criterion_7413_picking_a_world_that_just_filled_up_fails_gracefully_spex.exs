defmodule BrokenOathsSpex.Story873.Criterion7413Spex do
  @moduledoc """
  Story 873 — New Player Spawns in World
  Criterion 7413 — a stale picker entry cannot half-spawn a player into a full world.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "picking a world that just filled up fails gracefully" do
    scenario "the last region is taken between render and click" do
      given_ :a_world
      given_ :registered_player

      given_ "the player has the picker open showing the world as joinable", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")
        assert has_element?(join_live, "[data-test='join-world-#{context.world.id}']")
        {:ok, Map.put(context, :join_live, join_live)}
      end

      given_ "every spawnable region is claimed while they hesitate", context do
        for _region <- Fixtures.spawnable_regions(context.world) do
          user = Fixtures.user_fixture()

          conn =
            Phoenix.ConnTest.build_conn()
            |> BrokenOathsTest.ConnCase.log_in_user(user)

          {:ok, other_join, _html} = live(conn, ~p"/play")

          other_join
          |> element("[data-test='join-world-#{context.world.id}']")
          |> render_click()
        end

        {:ok, context}
      end

      when_ "the player clicks the stale join button", context do
        context.join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, context}
      end

      then_ "the join is refused with a clear message and no half-spawn", context do
        assert has_element?(context.join_live, "[data-test='join-error']")
        assert Fixtures.claimed_region(context.world, context.user) == nil
        {:ok, context}
      end
    end
  end
end
