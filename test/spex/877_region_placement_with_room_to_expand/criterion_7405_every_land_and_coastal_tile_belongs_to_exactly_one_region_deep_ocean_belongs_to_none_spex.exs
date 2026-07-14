defmodule BrokenOathsSpex.Story877.Criterion7405Spex do
  @moduledoc """
  Story 877 — Region Placement with Room to Expand
  Criterion 7405 — regions tile the land and coastal water completely and disjointly; deep ocean is outside the partition.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the partition covers land and coast exactly once" do
    scenario "every land and coastal tile belongs to exactly one region; deep ocean belongs to none" do
      given_(:a_world)

      when_ "the region partition is computed", context do
        {:ok, Map.put(context, :partition, Fixtures.region_partition(context.world))}
      end

      then_ "region tiles plus deep-ocean tiles cover the globe exactly once", context do
        %{regions: regions, deep_ocean: deep_ocean} = context.partition
        region_tiles = regions |> Map.values() |> List.flatten()
        all = region_tiles ++ Enum.to_list(deep_ocean)

        total = 10 * context.world.frequency * context.world.frequency + 2
        assert length(all) == total
        assert length(Enum.uniq(all)) == total
        {:ok, context}
      end

      then_ "no region contains a deep-ocean tile", context do
        %{regions: regions} = context.partition

        for {_id, tiles} <- regions, tile <- tiles do
          assert Fixtures.tile_class(context.world, tile) != :deep_ocean
        end

        {:ok, context}
      end
    end
  end
end
