defmodule BrokenOathsSpex.Story877.Criterion7404Spex do
  @moduledoc """
  Story 877 — Region Placement with Room to Expand
  Criterion 7404 — the region partition is a pure function of the world seed — recomputing it always yields identical regions.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the region partition is deterministic" do
    scenario "same seed always produces the same region partition" do
      given_(:a_world)

      given_ "the world's region partition has been computed once", context do
        {:ok, Map.put(context, :first_partition, Fixtures.region_partition(context.world))}
      end

      when_ "the region partition is computed again", context do
        {:ok, Map.put(context, :second_partition, Fixtures.region_partition(context.world))}
      end

      then_ "both computations produce identical regions", context do
        assert context.second_partition == context.first_partition
        # Anchor: the partition is real, not trivially empty
        assert map_size(context.second_partition.regions) > 0
        {:ok, context}
      end
    end
  end
end
