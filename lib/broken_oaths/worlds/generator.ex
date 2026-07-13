defmodule BrokenOaths.Worlds.Generator do
  @moduledoc """
  Procedural world generation using layered Perlin noise.
  Generates elevation and moisture maps to classify terrain types.

  Globe worlds sample 3D noise at each tile's unit-sphere center, which is
  seamless by construction. The 12 pentagons are forced to :mountains here
  (single source of truth), making them non-traversable.
  """
  alias BrokenOaths.Worlds.Globe
  alias BrokenOaths.Worlds.Noise

  @elevation_scale 0.035
  @moisture_scale 0.045

  # Noise-space units across the unit sphere; tuned to match the feature
  # density of the old 200-wide flat map (200 * 0.035 ≈ 7 units per wrap).
  @globe_elevation_scale 2.2
  @globe_moisture_scale 2.8

  @terrain_types [
    {0.30, :ocean},
    {0.35, :shallow_water},
    {0.40, :beach},
    {0.60, :grassland},
    {0.75, :plains},
    {0.85, :forest},
    {0.92, :hills},
    {1.01, :mountains}
  ]

  @doc """
  Generate the full terrain map for a world.
  Returns %{{q, r} => terrain_atom} for all hexes.
  """
  def generate_terrain_map(seed, width, height) do
    elevation_perm = Noise.init(seed)
    moisture_perm = Noise.init(seed + 12345)

    for q <- 0..(width - 1),
        r <- 0..(height - 1),
        into: %{} do
      elevation = Noise.fbm(elevation_perm, q * @elevation_scale, r * @elevation_scale, 6)
      moisture = Noise.fbm(moisture_perm, q * @moisture_scale, r * @moisture_scale, 4)
      terrain = classify_terrain(elevation, moisture)
      {{q, r}, terrain}
    end
  end

  @doc """
  Generate the terrain map for a globe world.
  Returns %{tile_id => terrain_atom} for all tiles in the mesh.
  The 12 pentagons are always :mountains (non-traversable).
  """
  def generate_terrain_map(seed, mesh) do
    elevation_perm = Noise.init(seed)
    moisture_perm = Noise.init(seed + 12345)

    Map.new(mesh.tiles, fn {id, tile} ->
      {id, tile_terrain(elevation_perm, moisture_perm, tile)}
    end)
  end

  defp tile_terrain(_eperm, _mperm, %Globe.Tile{pentagon?: true}), do: :mountains

  defp tile_terrain(eperm, mperm, %Globe.Tile{center: {x, y, z}}) do
    es = @globe_elevation_scale
    ms = @globe_moisture_scale
    elevation = Noise.fbm3d(eperm, x * es, y * es, z * es, 6)
    moisture = Noise.fbm3d(mperm, x * ms, y * ms, z * ms, 4)
    classify_terrain(elevation, moisture)
  end

  @doc "Generate terrain for a single hex."
  def generate_hex_terrain(seed, q, r) do
    elevation_perm = Noise.init(seed)
    moisture_perm = Noise.init(seed + 12345)
    elevation = Noise.fbm(elevation_perm, q * @elevation_scale, r * @elevation_scale, 6)
    moisture = Noise.fbm(moisture_perm, q * @moisture_scale, r * @moisture_scale, 4)
    classify_terrain(elevation, moisture)
  end

  @doc "Compute terrain type statistics from a terrain map."
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
  Find suitable spawn points on grassland tiles, spread apart.

  Globe form: `find_spawn_points(terrain_map, mesh, count)` — distance is
  chord distance between unit-sphere tile centers.
  Flat form: `find_spawn_points(terrain_map, count, world_width)` — wrap-aware
  axial distance.
  """
  def find_spawn_points(terrain_map, %{tiles: _} = mesh, count) do
    candidates =
      terrain_map
      |> Enum.filter(fn {_id, terrain} -> terrain == :grassland end)
      |> Enum.map(fn {id, _} -> id end)
      |> Enum.sort()

    select_spread_tiles(candidates, mesh, count)
  end

  def find_spawn_points(terrain_map, count, world_width) do
    candidates =
      terrain_map
      |> Enum.filter(fn {_coord, terrain} -> terrain == :grassland end)
      |> Enum.map(fn {coord, _} -> coord end)

    select_spread_points(candidates, count, world_width)
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

  defp select_spread_points([], _count, _w), do: []
  defp select_spread_points(_candidates, 0, _w), do: []

  defp select_spread_points(candidates, count, w) do
    mid = div(length(candidates), 2)
    first = Enum.at(candidates, mid)
    do_select([first], List.delete(candidates, first), count - 1, w)
  end

  defp do_select(selected, _candidates, 0, _w), do: selected
  defp do_select(selected, [], _remaining, _w), do: selected

  defp do_select(selected, candidates, remaining, w) do
    best =
      Enum.max_by(candidates, fn {q, r} ->
        Enum.map(selected, fn {sq, sr} ->
          dq = abs(q - sq)
          dq = min(dq, w - dq)
          dq + abs(r - sr)
        end)
        |> Enum.min()
      end)

    do_select([best | selected], List.delete(candidates, best), remaining - 1, w)
  end

  defp classify_terrain(elevation, moisture) do
    base = base_terrain(elevation)
    modify_by_moisture(base, moisture)
  end

  defp base_terrain(elevation) do
    Enum.find_value(@terrain_types, :mountains, fn {threshold, type} ->
      if elevation < threshold, do: type
    end)
  end

  defp modify_by_moisture(terrain, moisture) do
    case terrain do
      :grassland when moisture > 0.6 -> :forest
      :grassland when moisture < 0.35 -> :plains
      :plains when moisture > 0.7 -> :grassland
      other -> other
    end
  end
end
