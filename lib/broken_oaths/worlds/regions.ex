defmodule BrokenOaths.Worlds.Regions do
  @moduledoc """
  Deterministic partition of a world's globe into player regions.

  Every land, mountain, and coastal-water tile belongs to exactly one
  region; deep ocean belongs to none. Regions are contiguous (built by
  flood-filling connected components of claimable tiles) and sized around
  ~250 tiles — enough land for roughly seven Civ-scale cities.

  Within each connected landmass, seed tiles are spread by furthest-point
  sampling (chord distance between tile centers, first pick seeded from
  `world.seed`) and then grown in lockstep, one BFS ring at a time, until
  the landmass is exhausted. A landmass too small to need more than one
  seed becomes a single (possibly undersized) region — this is how small
  islands end up as their own, likely unspawnable, region.

  Partition and classification are pure functions of `world.seed` and
  `world.frequency`, so both are cached in `:persistent_term` the same
  way `Globe` caches the mesh.
  """

  alias BrokenOaths.Worlds.Generator
  alias BrokenOaths.Worlds.Globe
  alias BrokenOaths.Worlds.Terrain
  alias BrokenOaths.Worlds.World

  @habitability_floor 175
  @target_region_size 250

  # Bump whenever the cached shapes change: persistent_term survives code
  # reloads, so stale-shaped entries would otherwise leak into new code.
  @cache_version 1

  @type region_id :: non_neg_integer()
  @type tile_id :: non_neg_integer()
  @type tile_class :: :land | :mountain | :coastal_water | :deep_ocean

  @doc """
  Partition the world's globe into regions.

  Returns `%{regions: %{region_id => [tile_id]}, deep_ocean: [tile_id]}`.
  Deterministic from `world.seed` and `world.frequency`; cached.
  """
  @spec partition(World.t()) :: %{regions: %{region_id => [tile_id]}, deep_ocean: [tile_id]}
  def partition(world) do
    cached(partition_key(world), fn -> build_partition(world) end)
  end

  @doc "Region ids whose tile count meets the habitability floor (>= 175 tiles)."
  @spec spawnable(World.t()) :: [region_id]
  def spawnable(world) do
    world
    |> partition()
    |> Map.fetch!(:regions)
    |> Enum.filter(fn {_id, tiles} -> length(tiles) >= @habitability_floor end)
    |> Enum.map(fn {id, _tiles} -> id end)
    |> Enum.sort()
  end

  @doc "Classify a single tile: :land | :mountain | :coastal_water | :deep_ocean."
  @spec tile_class(World.t(), tile_id) :: tile_class
  def tile_class(world, tile_id) do
    world
    |> classes()
    |> Map.fetch!(tile_id)
  end

  @doc "Mesh-adjacent tiles for a given tile id."
  @spec adjacent_tiles(World.t(), tile_id) :: [tile_id]
  def adjacent_tiles(world, tile_id) do
    world.frequency
    |> Globe.get()
    |> Globe.tile(tile_id)
    |> Map.fetch!(:neighbors)
  end

  # -------------------------------------------------------------------
  # Caching
  # -------------------------------------------------------------------

  defp partition_key(world), do: {__MODULE__, :partition, @cache_version, world.seed, world.frequency}
  defp classes_key(world), do: {__MODULE__, :classes, @cache_version, world.seed, world.frequency}

  defp cached(key, build) do
    case :persistent_term.get(key, nil) do
      nil ->
        value = build.()
        :persistent_term.put(key, value)
        value

      value ->
        value
    end
  end

  defp classes(world) do
    cached(classes_key(world), fn ->
      mesh = Globe.get(world.frequency)
      terrain = Generator.generate_maps(world.seed, mesh).terrain
      classify_tiles(mesh, terrain)
    end)
  end

  # -------------------------------------------------------------------
  # Tile classification
  # -------------------------------------------------------------------

  defp classify_tiles(mesh, terrain) do
    Map.new(mesh.tiles, fn {id, tile} ->
      {id, classify_tile(tile, terrain)}
    end)
  end

  defp classify_tile(tile, terrain) do
    this = Map.fetch!(terrain, tile.id)

    cond do
      Terrain.water?(this) -> water_class(tile, terrain)
      this.relief == :mountains -> :mountain
      true -> :land
    end
  end

  defp water_class(tile, terrain) do
    if Enum.any?(tile.neighbors, fn n -> not Terrain.water?(Map.fetch!(terrain, n)) end) do
      :coastal_water
    else
      :deep_ocean
    end
  end

  # -------------------------------------------------------------------
  # Partition building
  # -------------------------------------------------------------------

  defp build_partition(world) do
    mesh = Globe.get(world.frequency)
    classes = classes(world)

    claimable =
      classes
      |> Enum.filter(fn {_id, class} -> class in [:land, :mountain, :coastal_water] end)
      |> Enum.map(fn {id, _class} -> id end)
      |> MapSet.new()

    deep_ocean =
      classes
      |> Enum.filter(fn {_id, class} -> class == :deep_ocean end)
      |> Enum.map(fn {id, _class} -> id end)
      |> Enum.sort()

    regions =
      claimable
      |> connected_components(mesh)
      |> Enum.map(&Enum.sort/1)
      |> Enum.sort_by(&hd/1)
      |> build_regions(mesh, world.seed)

    %{regions: regions, deep_ocean: deep_ocean}
  end

  defp build_regions(components, mesh, seed) do
    {region_maps, _next_id} =
      components
      |> Enum.with_index()
      |> Enum.map_reduce(0, fn {landmass, landmass_index}, next_id ->
        landmass_region_map(landmass, landmass_index, mesh, seed, next_id)
      end)

    Enum.reduce(region_maps, %{}, &Map.merge/2)
  end

  defp landmass_region_map(landmass, landmass_index, mesh, seed, next_id) do
    k = max(1, round(length(landmass) / @target_region_size))
    landmass_set = MapSet.new(landmass)
    seeds = spread_seeds(landmass, k, mesh, seed, landmass_index)
    grown = grow_regions(seeds, landmass_set, mesh)

    region_map =
      next_id
      |> Range.new(next_id + k - 1)
      |> Enum.with_index()
      |> Map.new(fn {global_id, local_id} ->
        {global_id, grown |> Map.get(local_id, []) |> Enum.sort()}
      end)

    {region_map, next_id + k}
  end

  # -------------------------------------------------------------------
  # Connected components (islands) of the claimable tile graph
  # -------------------------------------------------------------------

  defp connected_components(claimable, mesh) do
    claimable
    |> Enum.reduce({MapSet.new(), []}, fn id, {visited, components} ->
      if MapSet.member?(visited, id) do
        {visited, components}
      else
        component = flood_component(id, claimable, mesh)
        {MapSet.union(visited, component), [MapSet.to_list(component) | components]}
      end
    end)
    |> elem(1)
  end

  defp flood_component(start, claimable, mesh) do
    grow_component([start], claimable, mesh, MapSet.new([start]))
  end

  defp grow_component([], _claimable, _mesh, visited), do: visited

  defp grow_component([id | rest], claimable, mesh, visited) do
    {visited, discovered} =
      mesh
      |> Globe.tile(id)
      |> Map.fetch!(:neighbors)
      |> Enum.reduce({visited, []}, fn n, {v, acc} ->
        if MapSet.member?(claimable, n) and not MapSet.member?(v, n) do
          {MapSet.put(v, n), [n | acc]}
        else
          {v, acc}
        end
      end)

    grow_component(discovered ++ rest, claimable, mesh, visited)
  end

  # -------------------------------------------------------------------
  # Seed spread: furthest-point sampling over chord distance
  # -------------------------------------------------------------------

  defp spread_seeds(landmass, k, mesh, seed, landmass_index) do
    sorted = Enum.sort(landmass)
    centers = Map.new(sorted, fn id -> {id, Globe.tile(mesh, id).center} end)

    rand_state = :rand.seed_s(:exsss, {seed, landmass_index, 0})
    {first_index, _rand_state} = :rand.uniform_s(length(sorted), rand_state)
    first = Enum.at(sorted, first_index - 1)

    min_dist =
      sorted
      |> List.delete(first)
      |> Map.new(fn id -> {id, chord_sq(Map.fetch!(centers, id), Map.fetch!(centers, first))} end)

    pick_seeds([first], min_dist, centers, k - 1)
  end

  defp pick_seeds(selected, _min_dist, _centers, 0), do: Enum.reverse(selected)
  defp pick_seeds(selected, min_dist, _centers, _remaining) when map_size(min_dist) == 0,
    do: Enum.reverse(selected)

  defp pick_seeds(selected, min_dist, centers, remaining) do
    {next, _distance} = Enum.max_by(min_dist, fn {id, d} -> {d, -id} end)
    next_center = Map.fetch!(centers, next)

    min_dist =
      min_dist
      |> Map.delete(next)
      |> Map.new(fn {id, d} -> {id, min(d, chord_sq(Map.fetch!(centers, id), next_center))} end)

    pick_seeds([next | selected], min_dist, centers, remaining - 1)
  end

  defp chord_sq({ax, ay, az}, {bx, by, bz}) do
    dx = ax - bx
    dy = ay - by
    dz = az - bz
    dx * dx + dy * dy + dz * dz
  end

  # -------------------------------------------------------------------
  # Lockstep multi-source BFS growth
  # -------------------------------------------------------------------

  defp grow_regions(seeds, landmass_set, mesh) do
    indexed = Enum.with_index(seeds)
    claimed = Map.new(indexed, fn {tile, region} -> {tile, region} end)
    frontiers = Map.new(indexed, fn {tile, region} -> {region, [tile]} end)

    frontiers
    |> grow_until_exhausted(claimed, landmass_set, mesh)
    |> Enum.group_by(fn {_tile, region} -> region end, fn {tile, _region} -> tile end)
  end

  defp grow_until_exhausted(frontiers, claimed, landmass_set, mesh) do
    region_ids = frontiers |> Map.keys() |> Enum.sort()

    {next_frontiers, next_claimed, grew?} =
      Enum.reduce(region_ids, {%{}, claimed, false}, fn region_id, {nf, cl, grew?} ->
        expansion =
          frontiers
          |> Map.get(region_id, [])
          |> Enum.flat_map(fn tile -> Globe.tile(mesh, tile).neighbors end)
          |> Enum.uniq()
          |> Enum.filter(fn n -> MapSet.member?(landmass_set, n) and not Map.has_key?(cl, n) end)

        claimed = Enum.reduce(expansion, cl, fn n, acc -> Map.put(acc, n, region_id) end)
        {Map.put(nf, region_id, expansion), claimed, grew? or expansion != []}
      end)

    if grew? do
      grow_until_exhausted(next_frontiers, next_claimed, landmass_set, mesh)
    else
      next_claimed
    end
  end
end
