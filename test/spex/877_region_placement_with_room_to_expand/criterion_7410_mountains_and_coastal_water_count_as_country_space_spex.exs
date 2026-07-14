defmodule BrokenOathsSpex.Story877.Criterion7410Spex do
  @moduledoc """
  Story 877 — Region Placement with Room to Expand
  Criterion 7410 — regions are made of land, mountains, and coast-adjacent water; open ocean stays outside.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "mountains and coastal water count as country space" do
    scenario "region contents are land, mountains, and coastal water only" do
      given_(:a_world)

      when_ "the region partition is computed", context do
        {:ok, Map.put(context, :partition, Fixtures.region_partition(context.world))}
      end

      then_ "every region tile is land, mountain, or coastal water", context do
        %{regions: regions} = context.partition

        classes =
          for {_id, tiles} <- regions, tile <- tiles do
            class = Fixtures.tile_class(context.world, tile)
            assert class in [:land, :mountain, :coastal_water]
            class
          end

        # Anchor: mountains and coastal water genuinely occur inside regions
        assert :mountain in classes
        assert :coastal_water in classes
        {:ok, context}
      end

      then_ "everything outside the regions is deep ocean", context do
        %{deep_ocean: deep_ocean} = context.partition

        for tile <- deep_ocean do
          assert Fixtures.tile_class(context.world, tile) == :deep_ocean
        end

        {:ok, context}
      end
    end
  end
end
