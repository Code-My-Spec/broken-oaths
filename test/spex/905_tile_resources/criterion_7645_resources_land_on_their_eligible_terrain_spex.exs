defmodule BrokenOathsSpex.Story905.Criterion7645Spex do
  @moduledoc """
  Story 905 — Tile Resources
  Criterion 7645 — every placed resource sits only on terrain its own
  kind is allowed on: Cattle on flat, featureless grassland; Sheep and
  Stone on unforested hills (any base); Wheat on flat, featureless
  plains. Canonical placement table:
  `.code_my_spec/knowledge/civ6_resources.md` §2 ("Recommendation for
  905 — the four-resource MVP set").

  This is a UNIVERSAL claim over every instance actually placed on the
  world (`for every tile bearing resource X, X's own terrain rule
  holds`) — not a claim that every eligible tile gets a resource
  (that's density, criterion 7651) or that a given seed necessarily
  rolls all four kinds. The overall-placement anchor assertion in
  `then_` guards against the check being vacuously true because the
  not-yet-built generator placed nothing at all.

  Drives no LiveView surface — like story 877's region-partition specs,
  placement is seed-derived worldgen state with no gameplay action to
  trigger; `Fixtures.resource_at/2` (the sanctioned, read-only bridge
  to the not-yet-built `BrokenOaths.Worlds.Resources.at/2`) and the
  already-real `Fixtures.tile_terrain/2` are the whole surface.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "resources land on their eligible terrain" do
    scenario "every placed Cattle, Sheep, Wheat, and Stone tile matches its own terrain rule" do
      given_(:a_world)

      given_ "every tile's resource and terrain have been read", context do
        placements =
          for tile_id <- 0..(Fixtures.tile_count(context.world) - 1),
              resource = Fixtures.resource_at(context.world, tile_id),
              resource != nil do
            {tile_id, resource, Fixtures.tile_terrain(context.world, tile_id)}
          end

        {:ok, Map.put(context, :placements, placements)}
      end

      when_ "each placement is checked against its own resource's terrain rule", context do
        results = for {tile_id, resource, terrain} <- context.placements do
          {tile_id, resource, eligible?(resource, terrain)}
        end

        {:ok, Map.put(context, :results, results)}
      end

      then_ "at least one resource was actually placed on this world", context do
        assert context.placements != []
        {:ok, context}
      end

      then_ "every placed resource sat on terrain its own kind allows", context do
        violations = for {_tile_id, _resource, ok?} = entry <- context.results, ok? == false, do: entry
        assert violations == []
        {:ok, context}
      end
    end
  end

  defp eligible?(:cattle, %{base: :grassland, relief: :flat, feature: nil}), do: true
  defp eligible?(:cattle, _terrain), do: false

  defp eligible?(:wheat, %{base: :plains, relief: :flat, feature: nil}), do: true
  defp eligible?(:wheat, _terrain), do: false

  defp eligible?(:sheep, %{relief: :hills, feature: feature}), do: feature != :woods
  defp eligible?(:sheep, _terrain), do: false

  defp eligible?(:stone, %{relief: :hills, feature: feature}), do: feature != :woods
  defp eligible?(:stone, _terrain), do: false
end
