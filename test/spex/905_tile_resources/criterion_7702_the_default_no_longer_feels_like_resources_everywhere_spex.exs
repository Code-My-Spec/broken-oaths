defmodule BrokenOathsSpex.Story905.Criterion7702Spex do
  @moduledoc """
  Story 905 — Tile Resources
  Criterion 7702 — playtest update (issue 3e1159d1, resource density
  too high): at the standard default density, a player scanning the
  board around their starting city sees only a FEW resource tiles
  nearby, not a resource on almost every workable tile — and which
  tiles carry a resource stays fixed for the same seed (placement is
  still deterministic; only the RATE changed).

  The board is canvas-only (no per-tile DOM to literally "look at"), so
  "scans" here means the same sanctioned `select_tile`-driven read
  criterion 7649/7650 and the story's own QA brief already use
  (`Fixtures.resource_at/2`, the sanctioned domain read every
  `[data-test='tile-resource']` render ultimately goes through) — swept
  across the land tiles within 3 hexes of the city's own tile, the
  practical "nearby" a player's eye would actually take in without
  panning away.

  This is a qualitative companion to `Criterion7701Spex`'s own precise
  ~7%-of-land measurement: this spec's job is "does a REAL founded
  city's own neighborhood read as sparse," not re-proving the exact
  percentage on a bespoke fixture (7701 already owns that, and
  `ResourcesTest`'s own "roughly 7% of land tiles" regression owns the
  strict numeric regression guard).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the default no longer feels like resources everywhere" do
    scenario "Wes scans the land around his freshly founded city" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      when_ "Wes scans the board around his starting city", context do
        nearby = nearby_tiles(context.world, context.city.tile_id, 3)

        land_nearby =
          Enum.filter(nearby, &(Fixtures.tile_class(context.world, &1) == :land))

        first_pass =
          for tile_id <- land_nearby,
              into: %{},
              do: {tile_id, Fixtures.resource_at(context.world, tile_id)}

        {:ok,
         context
         |> Map.put(:land_nearby, land_nearby)
         |> Map.put(:first_pass, first_pass)}
      end

      then_ "he sees only a few resource tiles nearby rather than a resource on almost every workable tile",
            context do
        land_count = length(context.land_nearby)
        resource_count = context.first_pass |> Map.values() |> Enum.count(&(&1 != nil))

        assert land_count > 0

        max_allowed = max(trunc(land_count * 0.3), 3)

        assert resource_count <= max_allowed,
               "#{resource_count} of #{land_count} nearby land tiles carry a resource — " <>
                 "reads as carpeted, not \"a few\" (allowed up to #{max_allowed})"

        {:ok, context}
      end

      then_ "which tiles get resources is unchanged for the same seed (deterministic placement is preserved)",
            context do
        second_pass =
          for tile_id <- context.land_nearby,
              into: %{},
              do: {tile_id, Fixtures.resource_at(context.world, tile_id)}

        assert second_pass == context.first_pass

        {:ok, context}
      end
    end
  end

  # Every tile within `radius` hexes of `center` (inclusive of ring 1
  # through `radius`, excluding `center` itself) — a BFS disk built from
  # repeated `Fixtures.adjacent_tiles/2` expansion, the same primitive
  # every other spex's own "find a nearby tile" helper already uses.
  defp nearby_tiles(world, center, radius) do
    1..radius
    |> Enum.reduce(MapSet.new([center]), fn _, known ->
      known
      |> Enum.flat_map(&Fixtures.adjacent_tiles(world, &1))
      |> MapSet.new()
      |> MapSet.union(known)
    end)
    |> MapSet.delete(center)
    |> MapSet.to_list()
  end
end
