defmodule BrokenOathsSpex.Story877.Criterion7407Spex do
  @moduledoc """
  Story 877 — Region Placement with Room to Expand
  Criterion 7407 — a join race can never leave two players holding the same region.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "simultaneous joins never double-claim a region" do
    scenario "two players joining at the same moment get distinct regions" do
      given_ :a_world
      given_ :registered_player
      given_ :second_registered_player

      when_ "both players join at the same moment", context do
        [t1, t2] =
          for conn <- [context.conn, context.other_conn] do
            Task.async(fn ->
              {:ok, join_live, _html} = live(conn, ~p"/play")

              join_live
              |> element("[data-test='join-world-#{context.world.id}']")
              |> render_click()
            end)
          end

        Task.await(t1)
        Task.await(t2)
        {:ok, context}
      end

      then_ "exactly one player holds each claimed region — never both in the same one", context do
        first = Fixtures.claimed_region(context.world, context.user)
        second = Fixtures.claimed_region(context.world, context.other_user)

        assert first != nil
        assert second != nil
        assert first != second
        {:ok, context}
      end
    end
  end
end
