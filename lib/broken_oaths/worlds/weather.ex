defmodule BrokenOaths.Worlds.Weather do
  @moduledoc """
  The airspace layer: per-tile cloud cover on the SAME Goldberg mesh as
  the terrain, one shell above it. Weather is a board, not a decoration
  — cloud tiles are real hexes with tile ids, rendered exactly like the
  surface (baked texture impostor far, translucent hex polygons near).

  Levels: 0 clear (omitted from the map), 1 wisps, 2 cloud, 3 storm.

  Weather CHANGES: the cloud field is sampled at an offset that drifts
  with the weather epoch (a #{600}s wall-clock bucket), so systems slide
  across the globe and morph between epochs. Still fully deterministic
  from `(seed, epoch)` — derivable data, never persisted, same as
  terrain. Tests pin the epoch via `config :broken_oaths, :weather_epoch`.
  """

  alias BrokenOaths.Worlds.Noise

  @cache_version 2

  # Offset keeps the cloud field independent of the terrain fields.
  @seed_offset 777_777
  @scale 3.1
  @octaves 4

  @thresholds {0.56, 0.63, 0.71}

  # One weather epoch = 10 minutes; systems visibly evolve session to
  # session and drift mid-session for anyone who stays a while.
  @epoch_seconds 600

  # Per-epoch drift of the sample window through noise space: mostly a
  # steady "zonal wind" along x with a slower wobble in y/z so patterns
  # morph rather than just translate.
  @drift {0.22, 0.09, 0.05}

  @doc """
  The current weather epoch (wall clock), or the pinned value from
  `config :broken_oaths, :weather_epoch` (used by tests).
  """
  def current_epoch do
    case Application.get_env(:broken_oaths, :weather_epoch) do
      nil -> System.system_time(:second) |> div(@epoch_seconds)
      pinned -> pinned
    end
  end

  @doc "Milliseconds until the next epoch boundary (for LiveView timers)."
  def ms_until_next_epoch do
    now = System.system_time(:millisecond)
    epoch_ms = @epoch_seconds * 1000
    epoch_ms - rem(now, epoch_ms) + 50
  end

  @doc """
  Whether weather cloud shells are enabled. Off by default (players found the
  drifting clouds confusing); `config :broken_oaths, :weather_enabled`.
  """
  @spec enabled?() :: boolean()
  def enabled?, do: Application.get_env(:broken_oaths, :weather_enabled, false)

  @doc """
  Sparse cloud map for a world at an epoch: `%{tile_id => level}` with
  level 1..3. Clear tiles are absent. Defaults to the current epoch. Returns
  an empty map (no clouds) when weather is disabled.
  """
  def map(seed, mesh, epoch \\ nil) do
    if enabled?() do
      cloud_map(seed, mesh, epoch)
    else
      # Clouds disabled: no airspace levels anywhere, so nothing renders and no
      # airspace texture is drawn. Callers already treat an empty map as "clear".
      %{}
    end
  end

  defp cloud_map(seed, mesh, epoch) do
    epoch = epoch || current_epoch()
    key = {__MODULE__, @cache_version, seed, mesh.frequency, epoch}

    case :persistent_term.get(key, nil) do
      nil ->
        map = build(seed, mesh, epoch)
        :persistent_term.put(key, map)
        # Keep only a short trail of epochs cached — erase the one that
        # just scrolled out of relevance so long-running nodes don't leak.
        :persistent_term.erase({__MODULE__, @cache_version, seed, mesh.frequency, epoch - 2})
        map

      map ->
        map
    end
  end

  @doc "Cloud level (0..3) for one tile at the current epoch."
  def level(seed, mesh, tile_id), do: Map.get(map(seed, mesh), tile_id, 0)

  defp build(seed, mesh, epoch) do
    perm = Noise.init(seed + @seed_offset)
    {t1, t2, t3} = @thresholds
    {dx, dy, dz} = @drift
    ox = epoch * dx
    oy = epoch * dy
    oz = epoch * dz

    for {id, tile} <- mesh.tiles,
        {x, y, z} = tile.center,
        v = Noise.fbm3d(perm, x * @scale + ox, y * @scale + oy, z * @scale + oz, @octaves),
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
