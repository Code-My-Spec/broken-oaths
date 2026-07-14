defmodule BrokenOaths.Worlds.Generator do
  @moduledoc """
  Procedural world generation using layered Perlin noise, classified into
  Civ-style terrain: base type × relief × feature (see `Worlds.Terrain`).

  Terrain samples 3D noise at each tile's unit-sphere center, which is
  seamless by construction. A Whittaker-lite climate ladder picks the base:
  |z| is sin(latitude) — bands come straight from the sphere geometry —
  and altitude chills, so warmth runs ice cap → tundra ring → temperate →
  tropics with a moisture wobble keeping every edge organic. Relief comes
  from elevation; features (woods, rainforest, marsh, sea ice) layer on
  top per climate.

  The 12 pentagons are always mountains relief with a peak elevation
  (non-traversable); their base still follows climate, so polar pentagons
  are snowy peaks.
  """
  alias BrokenOaths.Worlds.Globe
  alias BrokenOaths.Worlds.Noise
  alias BrokenOaths.Worlds.Terrain

  # Noise-space units across the unit sphere; tuned to match the feature
  # density of the old 200-wide flat map (200 * 0.035 ≈ 7 units per wrap).
  @globe_elevation_scale 2.2
  @globe_moisture_scale 2.8

  @doc """
  Generate the terrain and elevation maps for a globe world in one noise
  pass. Returns %{terrain: %{tile_id => %Terrain{}}, elevation:
  %{tile_id => float}} with elevation in [0.0, 1.0].
  """
  def generate_maps(seed, mesh) do
    elevation_perm = Noise.init(seed)
    moisture_perm = Noise.init(seed + 12345)

    {terrain, elevation} =
      Enum.reduce(mesh.tiles, {%{}, %{}}, fn {id, tile}, {t_acc, e_acc} ->
        {terrain, elev} = tile_terrain(elevation_perm, moisture_perm, tile)
        {Map.put(t_acc, id, terrain), Map.put(e_acc, id, elev)}
      end)

    %{terrain: terrain, elevation: elevation}
  end

  @doc """
  Generate the terrain map for a globe world.
  Returns %{tile_id => %Terrain{}} for all tiles in the mesh.
  """
  def generate_terrain_map(seed, mesh) do
    generate_maps(seed, mesh).terrain
  end

  defp tile_terrain(eperm, mperm, %Globe.Tile{center: {x, y, z}, pentagon?: pentagon?}) do
    es = @globe_elevation_scale
    ms = @globe_moisture_scale
    moisture = Noise.fbm3d(mperm, x * ms, y * ms, z * ms, 4)

    elevation =
      if pentagon?, do: 0.95, else: Noise.fbm3d(eperm, x * es, y * es, z * es, 6)

    warmth = 1.0 - abs(z) * 1.15 - max(elevation - 0.55, 0.0) * 0.65 + (moisture - 0.5) * 0.1

    {classify(elevation, warmth, moisture, pentagon?), Float.round(elevation, 3)}
  end

  # -------------------------------------------------------------------
  # Classification: elevation → water/relief, warmth+moisture → base,
  # then features layered on top.
  # -------------------------------------------------------------------

  defp classify(elevation, warmth, _moisture, _pentagon?) when elevation < 0.30 do
    %Terrain{base: :ocean, feature: if(warmth < 0.06, do: :ice)}
  end

  defp classify(elevation, warmth, _moisture, _pentagon?) when elevation < 0.37 do
    %Terrain{base: :coast, feature: if(warmth < 0.06, do: :ice)}
  end

  defp classify(elevation, warmth, moisture, pentagon?) do
    relief =
      cond do
        pentagon? -> :mountains
        elevation >= 0.88 -> :mountains
        elevation >= 0.74 -> :hills
        true -> :flat
      end

    base =
      cond do
        warmth < 0.12 -> :snow
        warmth < 0.26 -> :tundra
        moisture < 0.32 and warmth > 0.55 -> :desert
        moisture < 0.45 or warmth > 0.66 -> :plains
        true -> :grassland
      end

    %Terrain{
      base: base,
      relief: relief,
      feature: feature(base, relief, elevation, warmth, moisture)
    }
  end

  defp feature(base, relief, elevation, warmth, moisture) do
    cond do
      relief == :mountains ->
        nil

      base in [:snow, :desert] ->
        nil

      base == :grassland and relief == :flat and elevation < 0.47 and moisture > 0.68 and
          warmth > 0.45 ->
        :marsh

      base in [:grassland, :plains] and warmth > 0.70 and moisture > 0.58 ->
        :rainforest

      base in [:grassland, :plains, :tundra] and moisture > 0.55 and warmth > 0.20 ->
        :woods

      true ->
        nil
    end
  end

  @doc "Compute terrain statistics from a terrain map, keyed by terrain."
  def terrain_stats(terrain_map) do
    total = map_size(terrain_map)

    terrain_map
    |> Enum.reduce(%{}, fn {_coord, terrain}, acc ->
      Map.update(acc, terrain, 1, &(&1 + 1))
    end)
    |> Enum.map(fn {terrain, count} ->
      {terrain, count, Float.round(count / total * 100, 1)}
    end)
    |> Enum.sort_by(fn {_, count, _} -> -count end)
  end

  @doc """
  Find suitable spawn points on open grassland, spread apart.
  Distance is chord distance between unit-sphere tile centers.
  """
  def find_spawn_points(terrain_map, mesh, count) do
    candidates =
      terrain_map
      |> Enum.filter(fn {_id, %Terrain{} = t} ->
        t.base == :grassland and t.relief != :mountains and t.feature != :marsh
      end)
      |> Enum.map(fn {id, _} -> id end)
      |> Enum.sort()

    select_spread_tiles(candidates, mesh, count)
  end

  defp select_spread_tiles([], _mesh, _count), do: []
  defp select_spread_tiles(_candidates, _mesh, 0), do: []

  defp select_spread_tiles(candidates, mesh, count) do
    first = Enum.at(candidates, div(length(candidates), 2))
    do_select_tiles([first], List.delete(candidates, first), mesh, count - 1)
  end

  defp do_select_tiles(selected, _candidates, _mesh, 0), do: selected
  defp do_select_tiles(selected, [], _mesh, _remaining), do: selected

  defp do_select_tiles(selected, candidates, mesh, remaining) do
    best =
      Enum.max_by(candidates, fn id ->
        center = Globe.tile(mesh, id).center

        selected
        |> Enum.map(fn sid -> chord_sq(center, Globe.tile(mesh, sid).center) end)
        |> Enum.min()
      end)

    do_select_tiles([best | selected], List.delete(candidates, best), mesh, remaining - 1)
  end

  defp chord_sq({ax, ay, az}, {bx, by, bz}) do
    dx = ax - bx
    dy = ay - by
    dz = az - bz
    dx * dx + dy * dy + dz * dz
  end
end
