defmodule BrokenOathsSpex.Story877.Criterion7411Spex do
  @moduledoc """
  Story 877 — Region Placement with Room to Expand
  Criterion 7411 — a claimed region is sized for roughly seven Civ-scale cities (~250 hexes).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a claimed region has room for about seven cities" do
    scenario "the claimed region's size is roughly 250 hexes" do
      given_ :a_world
      given_ :registered_player

      when_ "the player joins the world", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, context}
      end

      then_ "their region holds roughly 250 claimable hexes", context do
        claimed = Fixtures.claimed_region(context.world, context.user)
        %{regions: regions} = Fixtures.region_partition(context.world)
        size = length(Map.fetch!(regions, claimed))

        assert size >= 175
        assert size <= 325
        {:ok, context}
      end
    end
  end
end
