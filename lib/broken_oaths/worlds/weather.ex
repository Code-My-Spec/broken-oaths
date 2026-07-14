defmodule BrokenOaths.Worlds.Weather do
  @moduledoc """
  The airspace layer: per-tile cloud cover on the SAME Goldberg mesh as
  the terrain, one shell above it. Weather is a board, not a decoration
  — cloud tiles are real hexes with tile ids, rendered exactly like the
  surface (baked texture impostor far, translucent hex polygons near).

  Levels: 0 clear (omitted from the map), 1 wisps, 2 cloud, 3 storm.
  Deterministic from the world seed, so the whole layer is derivable
  data (never persisted), same as terrain.
  """

  alias BrokenOaths.Worlds.Noise

  @cache_version 1

  # Offset keeps the cloud field independent of the terrain fields.
  @seed_offset 777_777
  @scale 3.1
  @octaves 4

  @thresholds {0.56, 0.63, 0.71}

  @doc """
  Sparse cloud map for a world: `%{tile_id => level}` with level 1..3.
  Clear tiles are absent.
  """
  def map(seed, mesh) do
    key = {__MODULE__, @cache_version, seed, mesh.frequency}

    case :persistent_term.get(key, nil) do
      nil ->
        map = build(seed, mesh)
        :persistent_term.put(key, map)
        map

      map ->
        map
    end
  end

  @doc "Cloud level (0..3) for one tile."
  def level(seed, mesh, tile_id), do: Map.get(map(seed, mesh), tile_id, 0)

  defp build(seed, mesh) do
    perm = Noise.init(seed + @seed_offset)
    {t1, t2, t3} = @thresholds

    for {id, tile} <- mesh.tiles,
        {x, y, z} = tile.center,
        v = Noise.fbm3d(perm, x * @scale, y * @scale, z * @scale, @octaves),
        v > t1,
        into: %{} do
      level =
        cond do
          v > t3 -> 3
          v > t2 -> 2
          true -> 1
        end

      {id, level}
    end
  end

  def cache_version, do: @cache_version

  @doc "RGBA per level for the airspace palette (shared by texture + client)."
  def palette do
    %{
      0 => {0, 0, 0, 0},
      1 => {250, 251, 253, 96},
      2 => {240, 244, 249, 175},
      3 => {104, 110, 124, 215}
    }
  end
end
