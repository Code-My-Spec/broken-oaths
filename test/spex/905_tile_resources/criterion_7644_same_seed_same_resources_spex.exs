defmodule BrokenOathsSpex.Story905.Criterion7644Spex do
  @moduledoc """
  Story 905 — Tile Resources
  Criterion 7644 — resource placement is a pure function of the world
  seed — recomputing it always yields the identical resource map.

  Mirrors story 877 criterion 7404's own "the region partition is
  deterministic" spec exactly (`Fixtures.region_partition/1` there,
  `Fixtures.resource_at/2` here) — both prove a worldgen layer is
  seed-derived with zero live RNG (`.code_my_spec/knowledge/
  civ6_resources.md` §3: "Placement is a pure function of (seed,
  tile)").

  Two worlds can never share a `seed` (unique DB constraint), so
  determinism here is proven the same way story 874's restart spec
  proves turn-processing determinism: read the SAME world's resource
  layout twice and require byte-for-byte agreement, rather than
  standing up a second world.

  `Fixtures.resource_at/2` is the sanctioned bridge to the not-yet-built
  `BrokenOaths.Worlds.Resources.at/2` (assumed contract: `(world,
  tile_id) -> nil | :cattle | :sheep | :wheat | :stone`) — this spec is
  RED until that module exists.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "resource placement is deterministic" do
    scenario "same seed always produces the same resource map" do
      given_(:a_world)

      given_ "the world's resource layout has been computed once", context do
        {:ok, Map.put(context, :first_resource_map, resource_map(context.world))}
      end

      when_ "the resource layout is computed again", context do
        {:ok, Map.put(context, :second_resource_map, resource_map(context.world))}
      end

      then_ "both computations produce an identical, non-trivial resource map", context do
        assert context.second_resource_map == context.first_resource_map

        # Anchor: the map is real, not trivially all-nil.
        assert context.second_resource_map |> Map.values() |> Enum.any?(&(&1 != nil))
        {:ok, context}
      end
    end
  end

  defp resource_map(world) do
    for tile_id <- 0..(Fixtures.tile_count(world) - 1), into: %{} do
      {tile_id, Fixtures.resource_at(world, tile_id)}
    end
  end
end
