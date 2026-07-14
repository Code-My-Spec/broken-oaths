defmodule BrokenOathsSpex.Story877.Criterion7408Spex do
  @moduledoc """
  Story 877 — Region Placement with Room to Expand
  Criterion 7408 — spawnable regions all meet the habitability floor; a joiner is always placed in one of them.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "undersized island regions are never offered for spawning" do
    scenario "a new player is placed in a full-sized region" do
      given_(:a_world)
      given_(:registered_player)

      when_ "the player joins the world", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, context}
      end

      then_ "their claimed region is one of the spawnable regions", context do
        claimed = Fixtures.claimed_region(context.world, context.user)
        spawnable = Fixtures.spawnable_regions(context.world)

        assert claimed != nil
        assert claimed in spawnable
        {:ok, context}
      end

      then_ "every spawnable region meets the expansion size floor", context do
        %{regions: regions} = Fixtures.region_partition(context.world)

        for region_id <- Fixtures.spawnable_regions(context.world) do
          assert length(Map.fetch!(regions, region_id)) >= 175
        end

        {:ok, context}
      end
    end
  end
end
