defmodule BrokenOathsSpex.Story877.Criterion7409Spex do
  @moduledoc """
  Story 877 — Region Placement with Room to Expand
  Criterion 7409 — once every spawnable region is claimed, the world stops accepting joiners.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a full world turns new players away" do
    scenario "joining a full world is refused" do
      given_(:a_world)
      given_(:registered_player)

      given_ "every spawnable region is already claimed", context do
        for _region <- Fixtures.spawnable_regions(context.world) do
          user = Fixtures.user_fixture()

          conn =
            Phoenix.ConnTest.build_conn()
            |> BrokenOathsTest.ConnCase.log_in_user(user)

          {:ok, join_live, _html} = live(conn, ~p"/play")

          join_live
          |> element("[data-test='join-world-#{context.world.id}']")
          |> render_click()
        end

        {:ok, context}
      end

      when_ "a new player looks at the world picker", context do
        {:ok, join_live, html} = live(context.conn, ~p"/play")
        {:ok, context |> Map.put(:join_live, join_live) |> Map.put(:picker_html, html)}
      end

      then_ "the world is shown as full and cannot be joined", context do
        assert has_element?(context.join_live, "[data-test='world-full-#{context.world.id}']")
        refute has_element?(context.join_live, "[data-test='join-world-#{context.world.id}']")
        {:ok, context}
      end

      then_ "the player holds no membership in the full world", context do
        assert Fixtures.claimed_region(context.world, context.user) == nil
        {:ok, context}
      end
    end
  end
end
