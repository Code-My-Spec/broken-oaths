defmodule BrokenOathsSpex.Story905.Criterion7701Spex do
  @moduledoc """
  Story 905 — Tile Resources
  Criterion 7701 — playtest update (issue 3e1159d1, resource density
  too high): at the standard (default) density, resources occupy about
  7% of land tiles — roughly one resource per 12 to 15 land tiles — and
  the large majority of land tiles carry none at all.

  The gherkin's own illustrative fixture is "a world... with 210 land
  tiles" — a specific seed generating EXACTLY 210 is not guaranteed to
  exist (land tile count is an emergent property of the deterministic
  generator, not a tunable parameter), so this spec uses a bespoke
  seed/frequency pair (seed 1537, frequency 5) chosen for landing very
  close to that figure (216 land tiles, verified by direct count below
  — the same "count it for real, don't assume" discipline
  `Criterion7484Spex`'s own bespoke-seed rationale uses for its hills
  tile). The acceptance band is expressed as a fraction of the WORLD'S
  OWN actual land count (1/15 to 1/12, i.e. ~6.7%-8.3%) rather than a
  hardcoded tile count, so the assertion states the same "roughly 7%,
  one per 12-15" rule the criterion names regardless of exactly how
  many land tiles this particular seed happens to produce.
  """

  use BrokenOathsSpex.Case

  alias BrokenOathsSpex.Fixtures

  spex "a standard world is sparsely sprinkled, not carpeted" do
    scenario "resource placement runs at the standard default density" do
      given_ "a world generated at the standard default density with ~210 land tiles", context do
        world = Fixtures.world_fixture(%{seed: 1537, frequency: 5, resource_density: :standard})

        land =
          for tile_id <- 0..(Fixtures.tile_count(world) - 1),
              Fixtures.tile_class(world, tile_id) == :land,
              do: tile_id

        {:ok, context |> Map.put(:world, world) |> Map.put(:land, land)}
      end

      when_ "resource placement runs", context do
        resource_tiles =
          Enum.filter(context.land, &(Fixtures.resource_at(context.world, &1) != nil))

        {:ok, Map.put(context, :resource_tiles, resource_tiles)}
      end

      then_ "about one land tile in 12 to 15 carries a resource (roughly 7%)", context do
        land_count = length(context.land)
        resource_count = length(context.resource_tiles)

        # 1/15 to 1/12 of this world's own land count, rounded outward
        # so the band never excludes a legitimately-rounded edge case.
        lower = div(land_count, 15)
        upper = div(land_count + 11, 12)

        assert resource_count >= lower and resource_count <= upper,
               "#{resource_count} resource tiles out of #{land_count} land tiles " <>
                 "(expected #{lower}-#{upper}, ~7%)"

        {:ok, context}
      end

      then_ "the large majority of land tiles carry no resource at all", context do
        land_count = length(context.land)
        resource_count = length(context.resource_tiles)

        assert resource_count < land_count / 4

        {:ok, context}
      end
    end
  end
end
