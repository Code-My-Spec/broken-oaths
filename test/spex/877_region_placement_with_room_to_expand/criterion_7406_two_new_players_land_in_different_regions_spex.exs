defmodule BrokenOathsSpex.Story877.Criterion7406Spex do
  @moduledoc """
  Story 877 — Region Placement with Room to Expand
  Criterion 7406 — sequential joiners each claim their own region.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "two new players land in different regions" do
    scenario "sequential joiners claim distinct regions" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the first player has joined the world", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, context}
      end

      when_ "the second player joins the same world", context do
        {:ok, join_live, _html} = live(context.other_conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, context}
      end

      then_ "each player's claimed region is different", context do
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
