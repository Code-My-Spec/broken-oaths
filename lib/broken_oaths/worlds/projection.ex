defmodule BrokenOaths.Worlds.Projection do
  @moduledoc """
  Server-side orthographic projection of the globe for HTML rendering.

  The view is described by yaw/pitch (radians): the surface point at
  latitude `pitch`, longitude `yaw` rotates to the view center {0, 0, 1},
  with north up. Each visible tile projects to a screen-space bounding box
  plus a `clip-path: polygon(...)` of its true projected shape, so the
  LiveView can render it as one absolutely-positioned div — the spherical
  equivalent of the old flat compute_view/1.
  """

  alias BrokenOaths.Worlds.Globe

  # Icosahedron edge arc atan(2); divided by f it approximates the
  # center-to-center angular spacing of tiles.
  @icosa_edge_arc 1.1071487177940904

  @typedoc "View state: rotation, zoom scale (px per sphere radius), screen geometry."
  @type view :: %{
          yaw: float(),
          pitch: float(),
          scale: pos_integer(),
          cx: number(),
          cy: number(),
          w: pos_integer(),
          h: pos_integer()
        }

  @doc """
  Rotate a unit-sphere point into view space: yaw about the polar axis,
  then pitch. Returns {x', y', z'} where x' points screen-right (east),
  y' screen-up (north) and z' toward the viewer.

  The point at latitude `pitch`, longitude `yaw` maps to {0.0, 0.0, 1.0}.
  Length-preserving.
  """
  def rotate({x, y, z}, yaw, pitch) do
    cy = :math.cos(yaw)
    sy = :math.sin(yaw)
    x1 = x * cy + y * sy
    y1 = -x * sy + y * cy

    cp = :math.cos(pitch)
    sp = :math.sin(pitch)

    {y1, z * cp - x1 * sp, x1 * cp + z * sp}
  end

  @doc """
  Orthographic projection of a view-space point to screen pixels.
  Screen y grows downward, so view-space "up" is negated.
  """
  def project({vx, vy, _vz}, scale, cx, cy) do
    {cx + scale * vx, cy - scale * vy}
  end

  @doc """
  All tiles visible under `view`, each rendered to screen space:

      %{id, terrain, left, top, width, height, clip_path}

  Culling: rear hemisphere plus an adaptive limb cutoff (tiles whose
  projected width forshortens below ~1.5px), then screen bounds with a
  one-tile margin. Front-hemisphere tiles never overlap, so no z-sorting
  is needed.
  """
  def visible_tiles(mesh, terrain_map, view) do
    %{yaw: yaw, pitch: pitch, scale: scale, cx: cx, cy: cy, w: w, h: h} = view

    tile_arc = @icosa_edge_arc / mesh.frequency
    min_z = max(0.03, 1.5 / (scale * tile_arc))
    margin = scale * tile_arc

    mesh.tiles
    |> Map.values()
    |> Enum.reduce([], fn tile, acc ->
      {_, _, vz} = rotated_center = rotate(tile.center, yaw, pitch)

      if vz > min_z do
        {sx, sy} = project(rotated_center, scale, cx, cy)

        if sx >= -margin and sx <= w + margin and sy >= -margin and sy <= h + margin do
          [render_tile(tile, terrain_map, yaw, pitch, scale, cx, cy) | acc]
        else
          acc
        end
      else
        acc
      end
    end)
  end

  defp render_tile(tile, terrain_map, yaw, pitch, scale, cx, cy) do
    points =
      Enum.map(tile.corners, fn corner ->
        corner |> rotate(yaw, pitch) |> project(scale, cx, cy)
      end)

    {xs, ys} = Enum.unzip(points)

    left = xs |> Enum.min() |> Float.floor() |> trunc()
    top = ys |> Enum.min() |> Float.floor() |> trunc()
    right = xs |> Enum.max() |> Float.ceil() |> trunc()
    bottom = ys |> Enum.max() |> Float.ceil() |> trunc()

    width = max(right - left, 1)
    height = max(bottom - top, 1)

    clip_path =
      "polygon(" <>
        Enum.map_join(points, ", ", fn {px, py} ->
          "#{pct((px - left) / width)}% #{pct((py - top) / height)}%"
        end) <> ")"

    %{
      id: tile.id,
      terrain: Map.get(terrain_map, tile.id, :ocean),
      pentagon?: tile.pentagon?,
      left: left,
      top: top,
      width: width,
      height: height,
      clip_path: clip_path
    }
  end

  defp pct(fraction) do
    fraction
    |> max(0.0)
    |> min(1.0)
    |> Kernel.*(100)
    |> Float.round(1)
  end

  @doc """
  Angular radius (radians) allowed for a tile window of at most `budget`
  tiles out of `tile_count`: a spherical cap of angle θ holds
  `tile_count · (1 − cos θ) / 2` tiles.
  """
  def budget_theta(tile_count, budget) when 2 * budget >= tile_count, do: :math.pi()

  def budget_theta(tile_count, budget) do
    :math.acos(1.0 - 2.0 * budget / tile_count)
  end

  @doc """
  The near/far LOD multiplier `k`: the client shows real tile DOM only when
  scale > corner_distance · k, i.e. when the viewport (plus `margin` of
  drag slack) fits inside the budgeted window. 1.02 (edge barely hidden)
  when the budget doesn't bind.
  """
  def lod_k(tile_count, budget, margin) do
    theta_max = budget_theta(tile_count, budget)

    if theta_max >= 1.0 do
      1.02
    else
      usable = max(theta_max - margin, 0.05)
      max(1.02, 1.0 / :math.sin(min(usable, :math.pi() / 2)))
    end
  end

  @doc """
  Approximate great-circle distance (radians) between two unit vectors.
  Useful as an A* heuristic and for range checks.
  """
  def arc(a, b) do
    {ax, ay, az} = a
    {bx, by, bz} = b
    dot = ax * bx + ay * by + az * bz

    {cx_, cy_, cz_} = {ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx}
    cross_norm = :math.sqrt(cx_ * cx_ + cy_ * cy_ + cz_ * cz_)

    :math.atan2(cross_norm, dot)
  end

  @doc "Tile lat/lon delegated for sidebar display."
  defdelegate latlon(center), to: Globe
end
