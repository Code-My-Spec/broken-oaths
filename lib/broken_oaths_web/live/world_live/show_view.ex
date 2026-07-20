defmodule BrokenOathsWeb.WorldLive.ShowView do
  @moduledoc """
  Pure view-model helpers for `BrokenOathsWeb.WorldLive.Show`.

  Everything here is a plain function: given already-fetched globe/world
  state (never a `socket`), it returns a value — a derived assign, a
  parsed param, a projection/window payload, a formatted string. No
  `Phoenix.LiveView` call (no `assign`/`push_event`/`connected?`), no
  process/PubSub interaction. `Show`'s own `mount/3`/`handle_params/3`/
  `handle_event/3`/`handle_info/2` callbacks (and the few socket-touching
  helpers they share, like `rewindow/1`/`compute_view/1`) call these to
  keep their own bodies thin — the same "imperative shell, functional
  core" split `GameLive.PlayView` already establishes for the board
  LiveView (the LiveView analog of the
  `.code_my_spec/knowledge/genserver_decomposition.md` pragdave pattern),
  applied here to the `/worlds/:id` map editor.
  """

  alias BrokenOaths.Worlds.{Globe, Projection, Terrain, Weather}

  # 3D tile-window budgets: coarse-pointer (touch) devices composite far
  # fewer preserve-3d quads before framerate collapses, so they get a
  # smaller window and a smaller drag margin. Mirrors `Show`'s own
  # `@tile_budget_*`/`@window_margin_*` — kept here since both only ever
  # feed pure computation (`lod_k/2`, `window_min_dot/5`).
  @tile_budget_touch 1500
  @tile_budget_desktop 7500
  @window_margin_touch 0.2
  @window_margin_desktop 0.35

  # -------------------------------------------------------------------
  # Angle/param parsing
  # -------------------------------------------------------------------

  # yaw/pitch arrive in degrees (matching the sidebar display); returns
  # radians. Absent or malformed input yields nil (leaves the current
  # view untouched).
  def parse_degrees(nil), do: nil

  def parse_degrees(value) do
    case Float.parse(to_string(value)) do
      {deg, _} -> deg * :math.pi() / 180.0
      :error -> nil
    end
  end

  # zoom arrives as a scale in px per sphere radius, clamped to a sane
  # drag range.
  def parse_zoom(nil), do: nil

  def parse_zoom(value) do
    case Float.parse(to_string(value)) do
      {v, _} -> v |> round() |> max(50) |> min(10_000)
      :error -> nil
    end
  end

  # The `yaw`/`pitch`/`zoom` query-param overrides `handle_params/3`
  # applies to the socket — returns the list of `{key, value}` assign
  # changes (empty when nothing in `params` was recognized).
  def view_param_changes(params, w, h, zoom_factors, max_pitch) do
    yaw = parse_degrees(params["yaw"])
    pitch = parse_degrees(params["pitch"])
    zoom = parse_zoom(params["zoom"])

    [
      yaw && {:yaw, wrap_yaw(yaw)},
      pitch && {:pitch, clamp_pitch(pitch, max_pitch)},
      zoom && {:scale, zoom},
      zoom && {:zoom_index, nearest_zoom_index(w, h, zoom, zoom_factors)}
    ]
    |> Enum.reject(&is_nil/1)
  end

  # The client's reported settled/mid-drag view (`"view_sync"`),
  # normalized the same way every other yaw/pitch/scale entry point is:
  # yaw wrapped into [0, 2π), pitch clamped to the pole limit, scale
  # clamped to the drag range.
  def normalize_view_sync(yaw, pitch, scale, max_pitch) do
    {wrap_yaw(yaw * 1.0), clamp_pitch(pitch * 1.0, max_pitch),
     scale |> max(50) |> min(10_000) |> round()}
  end

  # -------------------------------------------------------------------
  # Rotation
  # -------------------------------------------------------------------

  def wrap_yaw(yaw) do
    two_pi = 2 * :math.pi()
    yaw - two_pi * Float.floor(yaw / two_pi)
  end

  def clamp_pitch(pitch, max_pitch), do: max(-max_pitch, min(pitch, max_pitch))

  # Pan-button/keyboard step: rotation step ≈ `pan_px` pixels of screen
  # travel at the view center; east-west steps cover similar screen
  # distance near the poles.
  def rotate_delta(dir, scale, pitch, pan_px) do
    step = pan_px / scale
    yaw_step = step / max(:math.cos(pitch), 0.25)

    case dir do
      "left" -> {-yaw_step, 0.0}
      "right" -> {yaw_step, 0.0}
      "up" -> {0.0, step}
      "down" -> {0.0, -step}
      _ -> {0.0, 0.0}
    end
  end

  # Client drag (GlobeDrag hook) sends accumulated pixel deltas;
  # dragging pulls the globe surface with the pointer, so the view
  # moves opposite.
  def drag_delta(dx, dy, scale, pitch) do
    dyaw = -dx / scale / max(:math.cos(pitch), 0.25)
    dpitch = dy / scale
    {dyaw, dpitch}
  end

  # -------------------------------------------------------------------
  # Zoom
  # -------------------------------------------------------------------

  def nearest_zoom_index(w, h, scale, zoom_factors) do
    fit = min(w, h) / 2

    zoom_factors
    |> Enum.with_index()
    |> Enum.min_by(fn {factor, _} -> abs(factor * fit - scale) end)
    |> elem(1)
  end

  # -------------------------------------------------------------------
  # Classic-mode projection (server-rendered tile DOM)
  # -------------------------------------------------------------------

  def compute_view(mesh, terrain_map, yaw, pitch, zoom_index, w, h, zoom_factors) do
    fit_scale = min(w, h) / 2
    scale = max(round(Enum.at(zoom_factors, zoom_index) * fit_scale), 1)

    view = %{
      yaw: yaw,
      pitch: pitch,
      scale: scale,
      cx: w / 2,
      cy: h / 2,
      w: w,
      h: h
    }

    %{visible_tiles: Projection.visible_tiles(mesh, terrain_map, view), scale: scale}
  end

  # -------------------------------------------------------------------
  # 3D-mode tile window
  # -------------------------------------------------------------------

  def tile_budget(true), do: @tile_budget_touch
  def tile_budget(false), do: @tile_budget_desktop

  def window_margin(true), do: @window_margin_touch
  def window_margin(false), do: @window_margin_desktop

  def lod_k(frequency, coarse) do
    frequency
    |> Globe.tile_count()
    |> Projection.lod_k(tile_budget(coarse), window_margin(coarse))
    |> Float.round(2)
  end

  # View direction unit vector for the current yaw/pitch.
  def view_vector(yaw, pitch) do
    {:math.cos(pitch) * :math.cos(yaw), :math.cos(pitch) * :math.sin(yaw), :math.sin(pitch)}
  end

  # Seed, container dims and device class are part of the bucket so
  # Regenerate, viewport changes and budget changes force a fresh push.
  def view_bucket({vx, vy, vz}, scale, w, h, seed, coarse, renderer3d) do
    {round(vx * 8), round(vy * 8), round(vz * 8), round(:math.log2(scale / 50) * 2), seed,
     div(w, 200), div(h, 200), coarse, renderer3d}
  end

  # Angular radius of the viewport plus a drag margin, capped both
  # generically (past ~1 rad the canvas impostor shows anyway) and by
  # the device's tile budget — the cosine of that radius is the
  # dot-product cutoff a tile's center must clear to be windowed.
  def window_min_dot(frequency, scale, w, h, coarse) do
    corner = :math.sqrt(w * w / 4 + h * h / 4)
    theta_budget = Projection.budget_theta(Globe.tile_count(frequency), tile_budget(coarse))

    theta =
      (:math.asin(min(corner / scale, 1.0)) + window_margin(coarse))
      |> min(1.0)
      |> min(theta_budget)

    :math.cos(theta)
  end

  # Vector-canvas window payload: only fine tiles near the view center,
  # with a dynamic palette of distinct composed `Terrain` colors in this
  # window (tiles reference them by index).
  def canvas_window_payload(mesh, terrain_map, elevation_map, min_dot, {vx, vy, vz}) do
    window =
      mesh.tiles
      |> Map.values()
      |> Enum.filter(fn %{center: {cx, cy, cz}} -> cx * vx + cy * vy + cz * vz > min_dot end)

    {rows, {rev_palette, _index}} =
      Enum.map_reduce(window, {[], %{}}, fn tile, {plist, pmap} ->
        terrain = Map.get(terrain_map, tile.id)
        color = Terrain.color(terrain)

        {idx, plist, pmap} =
          case pmap do
            %{^color => idx} -> {idx, plist, pmap}
            _ -> {map_size(pmap), [color | plist], Map.put(pmap, color, map_size(pmap))}
          end

        {tile_row(tile, idx, terrain, elevation_map), {plist, pmap}}
      end)

    %{palette: Enum.reverse(rev_palette), tiles: rows}
  end

  # Experimental css3d window payload: every windowed facet rendered
  # once as a server-built `<div>` with a static `matrix3d` transform.
  def css3d_window_payload(facets, terrain_map, min_dot, {vx, vy, vz}) do
    html =
      facets
      |> Enum.filter(fn %{center: {cx, cy, cz}} -> cx * vx + cy * vy + cz * vz > min_dot end)
      |> Enum.map(&facet_div(&1, terrain_map))
      |> IO.iodata_to_binary()

    %{html: html}
  end

  # Compact tile row for the vector-canvas renderer:
  # [id, palette_index, decor, tex, cx, cy, cz, elevation, corner1x, ...]
  # decor/tex mirror the game board's art keys (Terrain.decor/texture)
  # so both canvas globes draw the same sprites and ground patterns.
  def tile_row(tile, palette_index, terrain, elevation_map) do
    {cx, cy, cz} = tile.center

    corners =
      Enum.flat_map(tile.corners, fn {x, y, z} ->
        [Float.round(x, 4), Float.round(y, 4), Float.round(z, 4)]
      end)

    [
      tile.id,
      palette_index,
      Terrain.decor(terrain),
      Terrain.texture(terrain),
      Float.round(cx, 4),
      Float.round(cy, 4),
      Float.round(cz, 4),
      Map.get(elevation_map, tile.id, 0.0) | corners
    ]
  end

  # Server-built tile markup (no user data involved); phx-click works
  # via LiveView's delegated event handling even inside ignored DOM.
  def facet_div(facet, terrain_map) do
    terrain = Map.get(terrain_map, facet.id)
    id = Integer.to_string(facet.id)

    [
      ~s(<div class="hex-cell3d" phx-click="select_tile" phx-value-id="),
      id,
      ~s(" style="width:),
      Integer.to_string(facet.w),
      "px;height:",
      Integer.to_string(facet.h),
      "px;clip-path:",
      facet.clip,
      ";transform:",
      facet.matrix,
      ";background-color:",
      Terrain.color(terrain),
      ~s(;" title="#),
      id,
      " ",
      Terrain.label(terrain),
      ~s("></div>)
    ]
  end

  # -------------------------------------------------------------------
  # Pushed geometry payloads
  # -------------------------------------------------------------------

  # Selection ring geometry, drawable by both the canvas (texture far,
  # polygons near) render paths at any zoom.
  def selection_payload(nil), do: %{id: nil}

  def selection_payload(%Globe.Tile{} = tile) do
    {cx, cy, cz} = tile.center

    corners =
      Enum.flat_map(tile.corners, fn {x, y, z} ->
        [Float.round(x, 4), Float.round(y, 4), Float.round(z, 4)]
      end)

    %{
      id: tile.id,
      center: [Float.round(cx, 4), Float.round(cy, 4), Float.round(cz, 4)],
      corners: corners
    }
  end

  # Airspace: the sparse per-tile cloud map, pushed once per world/seed.
  # The near renderer draws these as translucent hexes one shell above
  # the surface; the far renderer samples the baked airspace texture.
  def airspace_payload(world, mesh) do
    levels = Weather.map(world.seed, mesh)

    # Storm-cell centers for the far renderer, which has no tile
    # geometry: [x, y, z] unit vectors for every level-3 tile.
    storms =
      for {id, 3} <- levels do
        {x, y, z} = Globe.tile(mesh, id).center
        [Float.round(x, 4), Float.round(y, 4), Float.round(z, 4)]
      end

    %{levels: levels, storms: storms, arc: Float.round(1.1071 / mesh.frequency, 5)}
  end

  # -------------------------------------------------------------------
  # Formatting
  # -------------------------------------------------------------------

  def deg(radians), do: Float.round(radians * 180.0 / :math.pi(), 1)

  def format_latlon(center) do
    {lat, lon} = Globe.latlon(center)
    ns = if lat >= 0, do: "N", else: "S"
    ew = if lon >= 0, do: "E", else: "W"
    "#{Float.round(abs(lat), 1)}°#{ns} #{Float.round(abs(lon), 1)}°#{ew}"
  end
end
