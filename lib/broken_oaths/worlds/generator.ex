defmodule BrokenOaths.Worlds.Generator do
  @moduledoc """
  Procedural world generation using layered Perlin noise.
  Generates elevation and moisture maps to classify terrain types.
  """
  alias BrokenOaths.Worlds.Noise

  @elevation_scale 0.035
  @moisture_scale 0.045

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

  @doc "Find suitable spawn points on grassland hexes, spread apart."
  def find_spawn_points(terrain_map, count, world_width) do
    candidates =
      terrain_map
      |> Enum.filter(fn {_coord, terrain} -> terrain == :grassland end)
      |> Enum.map(fn {coord, _} -> coord end)

    select_spread_points(candidates, count, world_width)
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
