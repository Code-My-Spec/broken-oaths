defmodule BrokenOathsWeb.WorldLive.Show do
  use BrokenOathsWeb, :live_view

  alias BrokenOaths.Worlds
  alias BrokenOaths.Worlds.{Facets, Generator, Globe, Projection}

  # Zoom levels as multiples of the "whole globe fits" scale (min(w,h)/2
  # pixels per sphere radius). Relative zoom keeps the on-screen TILE count
  # roughly constant at any viewport size, so a full-screen globe costs the
  # same as a small one — tiles just render larger.
  @zoom_factors [1.0, 1.4286, 2.0, 2.8571, 4.0, 5.7143]
  @default_zoom_index 2

  # Viewport size before the client reports its real dimensions.
  @default_container_w 960
  @default_container_h 700

  # 3D tile-window budgets: coarse-pointer (touch) devices composite far
  # fewer preserve-3d quads before framerate collapses, so they get a
  # smaller window, less drag margin, and a later canvas→hexes switchover.
  @tile_budget_touch 1500
  @tile_budget_desktop 7500
  @window_margin_touch 0.2
  @window_margin_desktop 0.35

  # Rotation step ≈ this many pixels of screen travel at the view center.
  @pan_px 150
  # Pitch clamp (±85.9°) keeps the up-vector sane; pole tiles are still
  # dead-center visible well before the clamp.
  @max_pitch 1.50

  @terrain_legend [
    {:ocean, "#1e3a8a", "Ocean"},
    {:shallow_water, "#3b82f6", "Shallow Water"},
    {:beach, "#fbbf24", "Beach / Coast"},
    {:grassland, "#22c55e", "Grassland"},
    {:plains, "#84cc16", "Plains"},
    {:forest, "#15803d", "Forest"},
    {:hills, "#92400e", "Hills"},
    {:mountains, "#525252", "Mountains"}
  ]

  # -------------------------------------------------------------------
  # Mount
  # -------------------------------------------------------------------

  def mount(%{"id" => id}, _session, socket) do
    world = Worlds.get_world!(id)
    worlds = Worlds.list_worlds()

    mesh = Globe.get(world.frequency)
    terrain_map = Generator.generate_terrain_map(world.seed, mesh)
    stats = Generator.terrain_stats(terrain_map)

    socket =
      socket
      |> assign(
        world: world,
        worlds: worlds,
        mesh: mesh,
        terrain_map: terrain_map,
        stats: stats,
        yaw: 0.0,
        pitch: 0.0,
        zoom_index: @default_zoom_index,
        container_w: @default_container_w,
        container_h: @default_container_h,
        render_mode: :classic,
        renderer3d: :canvas,
        facets: [],
        view_bucket: nil,
        device_coarse: false,
        lod_k: 1.02,
        sidebar_open: false,
        selected_tile: nil,
        selected_terrain: nil,
        page_title: world.name,
        terrain_legend: @terrain_legend
      )
      |> compute_view()

    {:ok, socket}
  end

  # Render mode and the camera live in the URL (?mode=3d&yaw=..&pitch=..&zoom=..),
  # so views survive refreshes, are shareable, and — critically — tests can
  # mount the LiveView at any exact camera state.
  def handle_params(params, _uri, socket) do
    mode = if params["mode"] == "3d", do: :three_d, else: :classic
    # Default near renderer is the vector canvas; ?renderer=css3d keeps the
    # matrix3d-facets experiment reachable.
    renderer = if params["renderer"] == "css3d", do: :css3d, else: :canvas

    {socket, view_changed?} = apply_view_params(socket, params)
    socket = socket |> assign(renderer3d: renderer) |> set_mode(mode)

    socket =
      case socket.assigns.render_mode do
        :classic when view_changed? -> compute_view(socket)
        # Bucket-deduped, so this is a no-op unless the params moved the view
        # or switched renderers while already in 3D
        :three_d -> rewindow(socket)
        _ -> socket
      end

    {:noreply, socket}
  end

  # yaw/pitch arrive in degrees (matching the sidebar display); zoom is the
  # scale in px per sphere radius. Absent or malformed params leave the
  # current view untouched.
  defp apply_view_params(socket, params) do
    yaw = parse_degrees(params["yaw"])
    pitch = parse_degrees(params["pitch"])
    zoom = parse_zoom(params["zoom"])

    changes =
      Enum.reject(
        [
          yaw && {:yaw, wrap_yaw(yaw)},
          pitch && {:pitch, clamp_pitch(pitch)},
          zoom && {:scale, zoom},
          zoom && {:zoom_index, nearest_zoom_index(socket, zoom)}
        ],
        &is_nil/1
      )

    if changes == [] do
      {socket, false}
    else
      {assign(socket, changes), true}
    end
  end

  defp parse_degrees(nil), do: nil

  defp parse_degrees(value) do
    case Float.parse(to_string(value)) do
      {deg, _} -> deg * :math.pi() / 180.0
      :error -> nil
    end
  end

  defp parse_zoom(nil), do: nil

  defp parse_zoom(value) do
    case Float.parse(to_string(value)) do
      {v, _} -> v |> round() |> max(50) |> min(10_000)
      :error -> nil
    end
  end

  # -------------------------------------------------------------------
  # Events
  # -------------------------------------------------------------------

  # In 3D mode the Globe3D hook owns the view client-side; server-side
  # rotation/zoom events are inert (the tile DOM is phx-update="ignore").
  def handle_event(event, _params, %{assigns: %{render_mode: :three_d}} = socket)
      when event in ["pan", "zoom_in", "zoom_out", "drag_rotate", "keydown"] do
    {:noreply, socket}
  end

  def handle_event("toggle_mode", _params, socket) do
    %{world: world, yaw: yaw, pitch: pitch, scale: scale} = socket.assigns

    view = [yaw: deg(yaw), pitch: deg(pitch), zoom: scale]

    to =
      if socket.assigns.render_mode == :classic,
        do: ~p"/worlds/#{world.id}?#{[{:mode, "3d"} | view]}",
        else: ~p"/worlds/#{world.id}?#{view}"

    {:noreply, push_patch(socket, to: to)}
  end

  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, assign(socket, sidebar_open: !socket.assigns.sidebar_open)}
  end

  # The Globe3D hook reports its view for the sidebar; when the view has
  # settled (drag end / wheel pause) the fine-tile window follows it.
  def handle_event(
        "view_sync",
        %{"yaw" => yaw, "pitch" => pitch, "scale" => scale} = params,
        socket
      )
      when is_number(yaw) and is_number(pitch) and is_number(scale) do
    two_pi = 2 * :math.pi()
    yaw = yaw * 1.0
    yaw = yaw - two_pi * Float.floor(yaw / two_pi)
    pitch = min(max(pitch * 1.0, -@max_pitch), @max_pitch)
    scale = scale |> max(50) |> min(10_000) |> round()

    socket = assign(socket, yaw: yaw, pitch: pitch, scale: scale)

    socket =
      if params["settled"] && socket.assigns.render_mode == :three_d,
        do: rewindow(socket),
        else: socket

    {:noreply, socket}
  end

  # In 3D mode a viewport change also re-windows (dims are in the bucket).
  # The hook reports whether this is a coarse-pointer (touch) device, which
  # sets the tile budget and LOD switchover.
  def handle_event("viewport_resize", %{"w" => w, "h" => h} = params, socket)
      when is_number(w) and is_number(h) do
    w = w |> round() |> max(200) |> min(4000)
    h = h |> round() |> max(200) |> min(4000)
    coarse = params["coarse"] == true

    socket =
      assign(socket,
        container_w: w,
        container_h: h,
        device_coarse: coarse,
        lod_k: lod_k(socket, coarse)
      )

    socket =
      case socket.assigns.render_mode do
        :three_d -> rewindow(socket)
        :classic -> compute_view(socket)
      end

    {:noreply, socket}
  end

  # Far-zoom clicks land on the canvas impostor; the hook inverse-projects
  # them to a unit-sphere point and the nearest real tile gets selected.
  def handle_event("select_at", %{"x" => x, "y" => y, "z" => z}, socket)
      when is_number(x) and is_number(y) and is_number(z) do
    tile = Globe.nearest_tile(socket.assigns.mesh, {x * 1.0, y * 1.0, z * 1.0})

    {:noreply,
     assign(socket,
       selected_tile: tile,
       selected_terrain: Map.get(socket.assigns.terrain_map, tile.id)
     )}
  end

  def handle_event("select_tile", %{"id" => id}, socket) do
    id = String.to_integer(id)
    tile = Globe.tile(socket.assigns.mesh, id)
    terrain = Map.get(socket.assigns.terrain_map, id)

    {:noreply,
     assign(socket,
       selected_tile: tile,
       selected_terrain: terrain
     )}
  end

  def handle_event("regenerate", _params, socket) do
    new_seed = :rand.uniform(999_999_999)

    case Worlds.update_world(socket.assigns.world, %{seed: new_seed}) do
      {:ok, world} ->
        # The mesh depends only on frequency; only terrain regenerates.
        terrain_map = Generator.generate_terrain_map(world.seed, socket.assigns.mesh)
        stats = Generator.terrain_stats(terrain_map)
        worlds = Worlds.list_worlds()

        socket =
          socket
          |> assign(
            world: world,
            worlds: worlds,
            terrain_map: terrain_map,
            stats: stats,
            selected_tile: nil,
            selected_terrain: nil,
            page_title: world.name
          )
          |> maybe_compute_view()

        # New seed = new bucket: pushes a recolored tile window in 3D mode
        socket =
          if socket.assigns.render_mode == :three_d, do: rewindow(socket), else: socket

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Seed collision – try again")}
    end
  end

  def handle_event("update_name", %{"name" => name}, socket) do
    case Worlds.update_world(socket.assigns.world, %{name: name}) do
      {:ok, world} ->
        {:noreply, assign(socket, world: world, page_title: name)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("zoom_in", _params, socket) do
    new_index = min(socket.assigns.zoom_index + 1, length(@zoom_factors) - 1)

    socket =
      socket
      |> assign(zoom_index: new_index)
      |> compute_view()

    {:noreply, socket}
  end

  def handle_event("zoom_out", _params, socket) do
    new_index = max(socket.assigns.zoom_index - 1, 0)

    socket =
      socket
      |> assign(zoom_index: new_index)
      |> compute_view()

    {:noreply, socket}
  end

  def handle_event("pan", %{"dir" => dir}, socket) do
    do_rotate(socket, dir)
  end

  # Client drag (GlobeDrag hook) sends accumulated pixel deltas; dragging
  # pulls the globe surface with the pointer, so the view moves opposite.
  def handle_event("drag_rotate", %{"dx" => dx, "dy" => dy}, socket)
      when is_number(dx) and is_number(dy) do
    %{pitch: pitch, scale: scale} = socket.assigns

    dyaw = -dx / scale / max(:math.cos(pitch), 0.25)
    dpitch = dy / scale

    {:noreply, apply_rotation(socket, dyaw, dpitch)}
  end

  def handle_event("keydown", %{"key" => key}, socket) do
    case key do
      k when k in ["ArrowLeft", "a"] -> do_rotate(socket, "left")
      k when k in ["ArrowRight", "d"] -> do_rotate(socket, "right")
      k when k in ["ArrowUp", "w"] -> do_rotate(socket, "up")
      k when k in ["ArrowDown", "s"] -> do_rotate(socket, "down")
      k when k in ["+", "="] -> handle_event("zoom_in", %{}, socket)
      k when k in ["-", "_"] -> handle_event("zoom_out", %{}, socket)
      _ -> {:noreply, socket}
    end
  end

  def handle_event("switch_world", %{"world_id" => id}, socket) do
    to =
      if socket.assigns.render_mode == :three_d,
        do: ~p"/worlds/#{id}?mode=3d",
        else: ~p"/worlds/#{id}"

    {:noreply, push_navigate(socket, to: to)}
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp do_rotate(socket, dir) do
    scale = socket.assigns.scale

    step = @pan_px / scale
    # East-west steps cover similar screen distance near the poles
    yaw_step = step / max(:math.cos(socket.assigns.pitch), 0.25)

    {dyaw, dpitch} =
      case dir do
        "left" -> {-yaw_step, 0.0}
        "right" -> {yaw_step, 0.0}
        "up" -> {0.0, step}
        "down" -> {0.0, -step}
        _ -> {0.0, 0.0}
      end

    {:noreply, apply_rotation(socket, dyaw, dpitch)}
  end

  defp apply_rotation(socket, dyaw, dpitch) do
    socket
    |> assign(
      yaw: wrap_yaw(socket.assigns.yaw + dyaw),
      pitch: clamp_pitch(socket.assigns.pitch + dpitch)
    )
    |> compute_view()
  end

  defp wrap_yaw(yaw) do
    two_pi = 2 * :math.pi()
    yaw - two_pi * Float.floor(yaw / two_pi)
  end

  defp clamp_pitch(pitch), do: max(-@max_pitch, min(pitch, @max_pitch))

  defp tile_budget(true), do: @tile_budget_touch
  defp tile_budget(false), do: @tile_budget_desktop

  defp window_margin(true), do: @window_margin_touch
  defp window_margin(false), do: @window_margin_desktop

  defp lod_k(socket, coarse) do
    socket.assigns.world.frequency
    |> Globe.tile_count()
    |> Projection.lod_k(tile_budget(coarse), window_margin(coarse))
    |> Float.round(2)
  end

  defp nearest_zoom_index(socket, scale) do
    %{container_w: w, container_h: h} = socket.assigns
    fit = min(w, h) / 2

    @zoom_factors
    |> Enum.with_index()
    |> Enum.min_by(fn {factor, _} -> abs(factor * fit - scale) end)
    |> elem(1)
  end

  defp set_mode(%{assigns: %{render_mode: mode}} = socket, mode), do: socket

  defp set_mode(socket, :three_d) do
    world = socket.assigns.world

    # Facet transforms are only needed by the css3d experimental renderer
    facets =
      if socket.assigns.renderer3d == :css3d, do: Facets.get(world.frequency), else: []

    socket
    |> assign(
      render_mode: :three_d,
      facets: facets,
      visible_tiles: [],
      view_bucket: nil
    )
    |> rewindow()
  end

  defp set_mode(socket, :classic) do
    socket
    |> assign(
      render_mode: :classic,
      facets: [],
      view_bucket: nil,
      # Snap the continuous 3D scale back to the nearest zoom level
      zoom_index: nearest_zoom_index(socket, socket.assigns.scale)
    )
    |> compute_view()
  end

  # Only fine tiles near the view center exist client-side — keeping all
  # 29k 3D-transformed divs mounted makes the browser re-rasterize and
  # depth-sort the world on every zoom change. The window is pushed as a
  # rendered HTML string and injected via innerHTML into a permanently
  # phx-update="ignore" container: LiveView never diffs tile DOM, so big
  # swaps can't stall morphdom or race the hook mid-drag.
  defp rewindow(socket) do
    %{yaw: yaw, pitch: pitch, scale: scale} = socket.assigns
    %{container_w: w, container_h: h, facets: facets} = socket.assigns

    v = {:math.cos(pitch) * :math.cos(yaw), :math.cos(pitch) * :math.sin(yaw), :math.sin(pitch)}
    bucket = view_bucket(v, scale, socket)

    if bucket == socket.assigns.view_bucket do
      socket
    else
      coarse = socket.assigns.device_coarse
      corner = :math.sqrt(w * w / 4 + h * h / 4)

      # Angular radius of the viewport plus a drag margin, capped both
      # generically (past ~1 rad the canvas impostor shows anyway) and by
      # the device's tile budget.
      theta_budget =
        Projection.budget_theta(
          Globe.tile_count(socket.assigns.world.frequency),
          tile_budget(coarse)
        )

      theta =
        (:math.asin(min(corner / scale, 1.0)) + window_margin(coarse))
        |> min(1.0)
        |> min(theta_budget)

      min_dot = :math.cos(theta)
      {vx, vy, vz} = v
      terrain_map = socket.assigns.terrain_map

      payload =
        case socket.assigns.renderer3d do
          :canvas ->
            tiles =
              socket.assigns.mesh.tiles
              |> Map.values()
              |> Enum.filter(fn %{center: {cx, cy, cz}} ->
                cx * vx + cy * vy + cz * vz > min_dot
              end)
              |> Enum.map(&tile_row(&1, terrain_map))

            %{palette: palette_colors(), tiles: tiles}

          :css3d ->
            html =
              facets
              |> Enum.filter(fn %{center: {cx, cy, cz}} ->
                cx * vx + cy * vy + cz * vz > min_dot
              end)
              |> Enum.map(&facet_div(&1, terrain_map))
              |> IO.iodata_to_binary()

            %{html: html}
        end

      socket
      |> assign(view_bucket: bucket)
      |> push_event("globe3d:window", payload)
    end
  end

  # Compact tile row for the vector-canvas renderer:
  # [id, palette_index, cx, cy, cz, corner1x, corner1y, corner1z, ...]
  defp tile_row(tile, terrain_map) do
    {cx, cy, cz} = tile.center

    corners =
      Enum.flat_map(tile.corners, fn {x, y, z} ->
        [Float.round(x, 4), Float.round(y, 4), Float.round(z, 4)]
      end)

    [
      tile.id,
      palette_index(Map.get(terrain_map, tile.id, :ocean)),
      Float.round(cx, 4),
      Float.round(cy, 4),
      Float.round(cz, 4) | corners
    ]
  end

  defp palette_colors, do: Enum.map(@terrain_legend, fn {_t, color, _label} -> color end)

  defp palette_index(terrain) do
    Enum.find_index(@terrain_legend, fn {t, _color, _label} -> t == terrain end) || 0
  end

  # Seed, container dims and device class are part of the bucket so
  # Regenerate, viewport changes and budget changes force a fresh push.
  defp view_bucket({vx, vy, vz}, scale, socket) do
    %{container_w: w, container_h: h, world: world, device_coarse: coarse} = socket.assigns

    {round(vx * 8), round(vy * 8), round(vz * 8), round(:math.log2(scale / 50) * 2), world.seed,
     div(w, 200), div(h, 200), coarse, socket.assigns.renderer3d}
  end

  # Server-built tile markup (no user data involved); phx-click works via
  # LiveView's delegated event handling even inside ignored DOM.
  defp facet_div(facet, terrain_map) do
    terrain = Map.get(terrain_map, facet.id, :ocean)
    id = Integer.to_string(facet.id)
    terrain_s = Atom.to_string(terrain)

    [
      ~s(<div class="hex-cell3d hex-),
      terrain_s,
      ~s(" phx-click="select_tile" phx-value-id="),
      id,
      ~s(" style="width:),
      Integer.to_string(facet.w),
      "px;height:",
      Integer.to_string(facet.h),
      "px;clip-path:",
      facet.clip,
      ";transform:",
      facet.matrix,
      ~s(;" title="#),
      id,
      " ",
      terrain_s,
      ~s("></div>)
    ]
  end

  # 3D mode never re-projects server-side; the tile DOM is static.
  defp maybe_compute_view(%{assigns: %{render_mode: :three_d}} = socket), do: socket
  defp maybe_compute_view(socket), do: compute_view(socket)

  defp compute_view(socket) do
    %{mesh: mesh, terrain_map: tm, yaw: yaw, pitch: pitch, zoom_index: zi} = socket.assigns
    %{container_w: w, container_h: h} = socket.assigns

    fit_scale = min(w, h) / 2
    scale = max(round(Enum.at(@zoom_factors, zi) * fit_scale), 1)

    view = %{
      yaw: yaw,
      pitch: pitch,
      scale: scale,
      cx: w / 2,
      cy: h / 2,
      w: w,
      h: h
    }

    assign(socket,
      visible_tiles: Projection.visible_tiles(mesh, tm, view),
      scale: scale
    )
  end

  defp terrain_class(terrain), do: "hex-#{terrain}"

  defp deg(radians), do: Float.round(radians * 180.0 / :math.pi(), 1)

  defp format_latlon(center) do
    {lat, lon} = Globe.latlon(center)
    ns = if lat >= 0, do: "N", else: "S"
    ew = if lon >= 0, do: "E", else: "W"
    "#{Float.round(abs(lat), 1)}°#{ns} #{Float.round(abs(lon), 1)}°#{ew}"
  end

  defp terrain_label(nil), do: "—"

  defp terrain_label(terrain) do
    case terrain do
      :ocean -> "Ocean"
      :shallow_water -> "Shallow Water"
      :beach -> "Beach"
      :grassland -> "Grassland"
      :plains -> "Plains"
      :forest -> "Forest"
      :hills -> "Hills"
      :mountains -> "Mountains"
      _ -> to_string(terrain)
    end
  end

  # -------------------------------------------------------------------
  # Render
  # -------------------------------------------------------------------

  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-[calc(100vh-64px)]" phx-window-keydown="keydown">
      <%!-- Controls bar --%>
      <div class="flex items-center gap-2 px-4 py-2 bg-base-200 border-b border-base-300 flex-wrap">
        <form phx-change="update_name" phx-submit="update_name" class="flex-none">
          <input
            type="text"
            name="name"
            value={@world.name}
            class="input input-sm input-bordered w-48 font-semibold"
          />
        </form>

        <span class="badge badge-neutral font-mono text-xs">Seed: {@world.seed}</span>

        <button phx-click="regenerate" class="btn btn-sm btn-primary">
          <.icon name="hero-arrow-path" class="w-4 h-4" /> Regenerate
        </button>

        <div class="flex-1"></div>

        <button phx-click="toggle_mode" class="btn btn-sm btn-ghost">
          {if @render_mode == :classic, do: "3D β", else: "Classic"}
        </button>

        <div :if={@render_mode == :classic} class="flex items-center gap-1">
          <button phx-click="zoom_out" class="btn btn-xs btn-square btn-ghost text-lg">−</button>
          <span class="text-xs font-mono w-10 text-center">{@scale}</span>
          <button phx-click="zoom_in" class="btn btn-xs btn-square btn-ghost text-lg">+</button>
        </div>

        <div class="divider divider-horizontal mx-0"></div>

        <form phx-change="switch_world">
          <select class="select select-sm select-bordered" name="world_id">
            <option :for={w <- @worlds} value={w.id} selected={w.id == @world.id}>
              {w.name}
            </option>
          </select>
        </form>

        <.link navigate={~p"/worlds"} class="btn btn-sm btn-ghost">All Worlds</.link>
      </div>

      <%!-- Main content --%>
      <div class="flex flex-1 min-h-0 relative">
        <%!-- Globe viewport --%>
        <div class="flex-1 overflow-hidden bg-base-300 relative">
          <div
            :if={@render_mode == :classic}
            id="globe-viewport"
            class="globe-viewport"
            phx-hook=".GlobeDrag"
            style="position:relative;width:100%;height:100%;"
          >
            <%!-- Sphere disc behind the tiles: fills hairline seams dark --%>
            <div
              class="globe-disc"
              style={"left:#{@container_w / 2 - @scale}px;top:#{@container_h / 2 - @scale}px;width:#{@scale * 2}px;height:#{@scale * 2}px;"}
            >
            </div>

            <div
              :for={tile <- @visible_tiles}
              class={[
                "hex-cell",
                terrain_class(tile.terrain),
                @selected_tile && @selected_tile.id == tile.id && "hex-selected"
              ]}
              phx-click="select_tile"
              phx-value-id={tile.id}
              style={"left:#{tile.left}px;top:#{tile.top}px;width:#{tile.width}px;height:#{tile.height}px;clip-path:#{tile.clip_path};"}
              title={"##{tile.id} #{tile.terrain}"}
            >
            </div>
          </div>

          <%!-- Experimental CSS-3D mode: every tile rendered once with a
               static matrix3d; the Globe3D hook rotates/zooms the parent
               container client-side at 60fps. No perspective = orthographic,
               matching the classic projection exactly. --%>
          <div
            :if={@render_mode == :three_d}
            id="globe3d-stage"
            class="globe3d-stage"
            phx-hook=".Globe3D"
            data-yaw={@yaw}
            data-pitch={@pitch}
            data-scale={@scale}
            data-r0={Facets.r0()}
            data-lod-k={@lod_k}
            data-renderer={@renderer3d}
            data-selected-id={@selected_tile && @selected_tile.id}
            data-texture={~p"/worlds/#{@world.id}/texture.png?seed=#{@world.seed}"}
          >
            <%!-- EVERYTHING the hook mutates lives inside this single
                 phx-update="ignore" wrapper. The hook styles the disc,
                 resizes/paints the canvas, and fills the fine layer via
                 innerHTML from pushed "globe3d:window" events — if any of
                 it were LiveView-rendered, every patch would reset it to
                 template state and fight the hook (canvas back to 300x150,
                 styles stripped), which is exactly the bug this fixes. --%>
            <div id={"globe3d-own-#{@world.id}"} phx-update="ignore" class="globe3d-own">
              <div class="globe-disc globe-disc3d"></div>
              <canvas class="globe-canvas" style="display:none;"></canvas>
              <div class="globe3d globe3d-fine"></div>
            </div>
          </div>

          <%!-- Rotate controls overlay --%>
          <div
            :if={@render_mode == :classic}
            class="absolute bottom-4 left-4 grid grid-cols-3 gap-0.5 opacity-60 hover:opacity-100 transition-opacity"
          >
            <div></div>
            <button
              phx-click="pan"
              phx-value-dir="up"
              class="btn btn-xs btn-circle btn-ghost bg-base-100/70"
            >
              <.icon name="hero-chevron-up" class="w-3 h-3" />
            </button>
            <div></div>
            <button
              phx-click="pan"
              phx-value-dir="left"
              class="btn btn-xs btn-circle btn-ghost bg-base-100/70"
            >
              <.icon name="hero-chevron-left" class="w-3 h-3" />
            </button>
            <div></div>
            <button
              phx-click="pan"
              phx-value-dir="right"
              class="btn btn-xs btn-circle btn-ghost bg-base-100/70"
            >
              <.icon name="hero-chevron-right" class="w-3 h-3" />
            </button>
            <div></div>
            <button
              phx-click="pan"
              phx-value-dir="down"
              class="btn btn-xs btn-circle btn-ghost bg-base-100/70"
            >
              <.icon name="hero-chevron-down" class="w-3 h-3" />
            </button>
            <div></div>
          </div>

          <%!-- Keyboard hint --%>
          <div class="absolute bottom-4 right-4 text-xs opacity-40">
            {if @render_mode == :classic,
              do: "Drag or WASD / Arrows to rotate · Wheel or +/− to zoom",
              else: "3D β — drag to spin · wheel to zoom · WASD to rotate"}
          </div>
        </div>

        <%!-- Input-only hook: converts pointer drags into throttled
             drag_rotate events, wheel into zoom steps, and reports the
             viewport's real size. All rendering stays server-side. --%>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".GlobeDrag">
          export default {
            mounted() {
              this.pending = {dx: 0, dy: 0}
              this.lastSent = 0
              this.timer = null
              this.pointer = null
              this.moved = false

              // --- viewport size: report on mount and on resize ---
              this.reportSize = () => {
                const r = this.el.getBoundingClientRect()
                const w = Math.round(r.width), h = Math.round(r.height)
                if (w > 0 && h > 0 && (w !== this.w || h !== this.h)) {
                  this.w = w
                  this.h = h
                  this.pushEvent("viewport_resize", {w, h})
                }
              }
              this.reportSize()
              this.resizeTimer = null
              this.ro = new ResizeObserver(() => {
                clearTimeout(this.resizeTimer)
                this.resizeTimer = setTimeout(this.reportSize, 150)
              })
              this.ro.observe(this.el)

              // --- wheel zoom: one zoom step per ~140ms of scrolling ---
              this.wheelAccum = 0
              this.lastZoom = 0
              this.el.addEventListener("wheel", (e) => {
                e.preventDefault()
                this.wheelAccum += e.deltaY
                const now = Date.now()
                if (Math.abs(this.wheelAccum) >= 20 && now - this.lastZoom >= 140) {
                  this.pushEvent(this.wheelAccum < 0 ? "zoom_in" : "zoom_out", {})
                  this.wheelAccum = 0
                  this.lastZoom = now
                }
              }, {passive: false})

              this.touches = new Map()
              this.pinchDist = null

              this.el.addEventListener("pointerdown", (e) => {
                if (e.pointerType === "mouse" && e.button !== 0) return
                this.touches.set(e.pointerId, {x: e.clientX, y: e.clientY})

                if (this.touches.size === 2) {
                  // Second finger: abandon drag, enter pinch
                  this.pointer = null
                  this.moved = false
                  this.el.classList.remove("dragging")
                  const [a, b] = [...this.touches.values()]
                  this.pinchDist = Math.hypot(a.x - b.x, a.y - b.y)
                  this.el.setPointerCapture(e.pointerId)
                } else if (this.touches.size === 1) {
                  this.pointer = e.pointerId
                  this.last = {x: e.clientX, y: e.clientY}
                  this.moved = false
                }
              })

              this.el.addEventListener("pointermove", (e) => {
                // Pinch: step through the server zoom levels as the spread
                // crosses ±25% thresholds
                if (this.pinchDist !== null && this.touches.has(e.pointerId)) {
                  this.touches.set(e.pointerId, {x: e.clientX, y: e.clientY})
                  if (this.touches.size === 2) {
                    const [a, b] = [...this.touches.values()]
                    const d = Math.hypot(a.x - b.x, a.y - b.y)
                    if (d > this.pinchDist * 1.25) {
                      this.pushEvent("zoom_in", {})
                      this.pinchDist = d
                    } else if (d < this.pinchDist * 0.8) {
                      this.pushEvent("zoom_out", {})
                      this.pinchDist = d
                    }
                  }
                  return
                }

                if (this.pointer === null || e.pointerId !== this.pointer) return
                const dx = e.clientX - this.last.x
                const dy = e.clientY - this.last.y

                if (!this.moved) {
                  // Small threshold so plain clicks still select tiles
                  if (Math.abs(dx) + Math.abs(dy) < 4) return
                  this.moved = true
                  // Capturing retargets the eventual click to this element,
                  // so a drag never fires a tile's phx-click
                  this.el.setPointerCapture(this.pointer)
                  this.el.classList.add("dragging")
                }

                this.last = {x: e.clientX, y: e.clientY}
                this.pending.dx += dx
                this.pending.dy += dy
                this.flush(false)
              })

              const end = (e) => {
                this.touches.delete(e.pointerId)

                if (this.pinchDist !== null && this.touches.size < 2) {
                  this.pinchDist = null
                  return
                }

                if (this.pointer === null || e.pointerId !== this.pointer) return
                if (this.moved) this.flush(true)
                this.pointer = null
                this.moved = false
                this.el.classList.remove("dragging")
              }
              this.el.addEventListener("pointerup", end)
              this.el.addEventListener("pointercancel", end)
            },

            flush(force) {
              const now = Date.now()

              if (!force && now - this.lastSent < 90) {
                if (!this.timer) {
                  this.timer = setTimeout(() => {
                    this.timer = null
                    this.flush(true)
                  }, 90 - (now - this.lastSent))
                }
                return
              }

              if (this.timer) {
                clearTimeout(this.timer)
                this.timer = null
              }

              const {dx, dy} = this.pending
              if (dx === 0 && dy === 0) return
              this.pending = {dx: 0, dy: 0}
              this.lastSent = now
              this.pushEvent("drag_rotate", {dx, dy})
            },

            destroyed() {
              if (this.timer) clearTimeout(this.timer)
              if (this.resizeTimer) clearTimeout(this.resizeTimer)
              if (this.ro) this.ro.disconnect()
            }
          }
        </script>

        <%!-- 3D mode: the hook owns yaw/pitch/scale and rotates the whole
             globe with ONE matrix3d update per frame. The server only hears
             about the settled view (view_sync) and tile clicks. --%>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".Globe3D">
          export default {
            mounted() {
              this.farMode = false

              this.grab = () => {
                this.fine = this.el.querySelector(".globe3d-fine")
                this.disc = this.el.querySelector(".globe-disc3d")
                this.canvas = this.el.querySelector(".globe-canvas")
              }
              this.grab()

              // Tile windows bypass LiveView's DOM diffing entirely:
              // vector payloads (canvas renderer) are drawn as polygons;
              // css3d payloads arrive as pre-rendered HTML into the stable
              // .globe3d-fine node.
              this.handleEvent("globe3d:window", (payload) => {
                if (payload.tiles) {
                  this.tiles = payload.tiles
                  this.palette = payload.palette || []
                  this.schedule()
                } else if (payload.html && this.fine) {
                  this.fine.innerHTML = payload.html
                  this.schedule()
                }
              })

              // --- baked world texture for the far-zoom impostor ---
              // Two-stage: the tiny level-0 bake paints almost instantly,
              // then the full-resolution level 1 replaces it.
              this.tex = null
              this.loadedUrl = null
              this.decode = (src, cb) => {
                const img = new Image()
                img.onload = () => {
                  const oc = document.createElement("canvas")
                  oc.width = img.width
                  oc.height = img.height
                  const octx = oc.getContext("2d")
                  octx.drawImage(img, 0, 0)
                  const idata = octx.getImageData(0, 0, img.width, img.height)
                  cb({data: new Uint32Array(idata.data.buffer), w: img.width, h: img.height})
                }
                img.src = src
              }
              this.loadTexture = () => {
                const url = this.el.dataset.texture
                if (!url || url === this.loadedUrl) return
                this.loadedUrl = url
                this.decode(url + "&level=0", (tex) => {
                  // Don't downgrade if a full-res bake for this URL landed first
                  if (this.loadedUrl === url && (!this.tex || this.tex.level0)) {
                    tex.level0 = true
                    this.tex = tex
                    this.schedule()
                  }
                })
                this.decode(url, (tex) => {
                  if (this.loadedUrl === url) {
                    this.tex = tex
                    this.schedule()
                  }
                })
              }
              this.loadTexture()

              const d = this.el.dataset
              this.yaw = parseFloat(d.yaw) || 0
              this.pitch = parseFloat(d.pitch) || 0
              this.S = parseFloat(d.scale) || 700
              this.r0 = parseFloat(d.r0) || 700
              this.lodK = parseFloat(d.lodK) || 1.02
              this.renderer = d.renderer || "canvas"
              this.selectedId = d.selectedId ? parseInt(d.selectedId) : null
              this.maxPitch = 1.50
              this.raf = null
              this.lastSync = 0
              this.syncTimer = null
              this.tiles = null
              this.palette = []

              // Touch devices: smaller tile budget upstream, deeper zoom so
              // the budgeted hex window is still reachable, cheaper canvas.
              this.coarse = window.matchMedia("(pointer: coarse)").matches

              // Far mode renders below full resolution and upscales — the
              // intentional "fuzzy at a distance" look, and far fewer
              // pixels. Near vector mode renders dpr-sharp.
              this.q = this.coarse ? 0.4 : 0.5

              // Resize the canvas backing store for the current LOD: cheap
              // low-res for the texture warp, dpr-sharp for polygons.
              this.sizeCanvas = () => {
                const nearVector = this.renderer === "canvas" && !this.farMode
                const scale = nearVector ? Math.min(window.devicePixelRatio || 1, 2) : this.q
                const cw = Math.max(Math.round(this.cssW * scale), 1)
                const ch = Math.max(Math.round(this.cssH * scale), 1)
                if (this.canvas.width === cw && this.canvas.height === ch) return
                this.pxScale = scale
                this.canvas.width = cw
                this.canvas.height = ch
                this.canvas.style.width = this.cssW + "px"
                this.canvas.style.height = this.cssH + "px"
                this.ctx = this.canvas.getContext("2d")
                this.frame = this.ctx.createImageData(cw, ch)
                this.frame32 = new Uint32Array(this.frame.data.buffer)
              }

              const measure = () => {
                const r = this.el.getBoundingClientRect()
                this.cx = r.width / 2
                this.cy = r.height / 2
                this.cssW = Math.max(r.width, 1)
                this.cssH = Math.max(r.height, 1)
                this.fit = Math.max(Math.min(r.width, r.height) / 2, 25)
                this.sizeCanvas()
                if (r.width > 0) {
                  this.pushEvent("viewport_resize", {
                    w: Math.round(r.width),
                    h: Math.round(r.height),
                    coarse: this.coarse
                  })
                }
              }
              measure()
              this.maxZoom = this.coarse ? 14 : 8
              this.clampS = () => { this.S = Math.max(this.fit, Math.min(this.S, this.fit * this.maxZoom)) }
              this.clampS()

              this.resizeTimer = null
              this.ro = new ResizeObserver(() => {
                clearTimeout(this.resizeTimer)
                this.resizeTimer = setTimeout(() => { measure(); this.clampS(); this.schedule() }, 150)
              })
              this.ro.observe(this.el)

              // LOD: near detail only when the viewport fits inside the
              // device's budgeted tile window (data-lod-k, server-computed);
              // the baked-texture warp otherwise. With the vector renderer
              // both levels draw on the canvas (polygons near, texture far);
              // css3d swaps the canvas for the matrix3d tile DOM. Display
              // state is force-written every apply (cheap; browsers dedup
              // same-value writes). Hysteresis lives in farMode.
              this.updateLod = () => {
                const corner = Math.hypot(this.cx, this.cy)
                const wasFar = this.farMode
                this.farMode = this.farMode
                  ? this.S < corner * this.lodK * 1.1
                  : this.S < corner * this.lodK

                if (this.renderer === "canvas") {
                  if (wasFar !== this.farMode) this.sizeCanvas()
                  this.canvas.style.display = ""
                  this.fine.style.display = "none"
                } else {
                  this.canvas.style.display = this.farMode ? "" : "none"
                  this.fine.style.display = this.farMode ? "none" : ""
                }
              }

              // World vector for a screen point (inverse view rotation).
              this.unproject = (sx, sy) => {
                const vx = (sx - this.cx) / this.S
                const vy = (this.cy - sy) / this.S
                const r2 = vx * vx + vy * vy
                if (r2 > 1) return null
                const vz = Math.sqrt(1 - r2)
                const cyw = Math.cos(this.yaw), syw = Math.sin(this.yaw)
                const cp = Math.cos(this.pitch), sp = Math.sin(this.pitch)
                return {
                  x: -syw * vx - sp * cyw * vy + cp * cyw * vz,
                  y: cyw * vx - sp * syw * vy + cp * syw * vz,
                  z: cp * vy + sp * vz
                }
              }

              // Near mode, vector renderer: the windowed tiles as filled 2D
              // paths — crisp at any zoom, no DOM, no compositor limits.
              this.renderPolygons = () => {
                const tiles = this.tiles
                const ctx = this.ctx
                if (!ctx) return
                ctx.clearRect(0, 0, this.canvas.width, this.canvas.height)
                if (!tiles) return

                const k = this.pxScale
                const S = this.S * k, ccx = this.cx * k, ccy = this.cy * k
                const cyw = Math.cos(this.yaw), syw = Math.sin(this.yaw)
                const cp = Math.cos(this.pitch), sp = Math.sin(this.pitch)
                // View-space z of a world point (backface test)
                const vz = (x, y, z) => cp * cyw * x + cp * syw * y + sp * z
                let selected = null

                for (const row of tiles) {
                  if (vz(row[2], row[3], row[4]) <= 0.02) continue

                  ctx.beginPath()
                  for (let i = 5; i < row.length; i += 3) {
                    const x = row[i], y = row[i + 1], z = row[i + 2]
                    const px = ccx + S * (-syw * x + cyw * y)
                    const py = ccy - S * (-sp * cyw * x - sp * syw * y + cp * z)
                    if (i === 5) ctx.moveTo(px, py); else ctx.lineTo(px, py)
                  }
                  ctx.closePath()
                  const color = this.palette[row[1]] || "#1e3a8a"
                  ctx.fillStyle = color
                  ctx.fill()
                  // Hairline same-color stroke seals seams between polygons
                  ctx.strokeStyle = color
                  ctx.lineWidth = 1
                  ctx.stroke()
                  if (row[0] === this.selectedId) selected = row
                }

                if (selected) {
                  ctx.beginPath()
                  for (let i = 5; i < selected.length; i += 3) {
                    const x = selected[i], y = selected[i + 1], z = selected[i + 2]
                    const px = ccx + S * (-syw * x + cyw * y)
                    const py = ccy - S * (-sp * cyw * x - sp * syw * y + cp * z)
                    if (i === 5) ctx.moveTo(px, py); else ctx.lineTo(px, py)
                  }
                  ctx.closePath()
                  ctx.strokeStyle = "#ffffff"
                  ctx.lineWidth = Math.max(2 * k, 2)
                  ctx.stroke()
                }
              }

              this.renderCanvas = () => {
                if (!this.tex || !this.frame32) return
                const out = this.frame32
                out.fill(0)
                const q = this.pxScale
                const S = this.S * q, ccx = this.cx * q, ccy = this.cy * q
                const cw = this.canvas.width, ch = this.canvas.height
                const cyw = Math.cos(this.yaw), syw = Math.sin(this.yaw)
                const cp = Math.cos(this.pitch), sp = Math.sin(this.pitch)
                const tex = this.tex.data, TW = this.tex.w, TH = this.tex.h
                const INV2PI = 1 / (2 * Math.PI), INVPI = 1 / Math.PI
                const x0 = Math.max(0, Math.floor(ccx - S)), x1 = Math.min(cw - 1, Math.ceil(ccx + S))
                const y0 = Math.max(0, Math.floor(ccy - S)), y1 = Math.min(ch - 1, Math.ceil(ccy + S))
                for (let py = y0; py <= y1; py++) {
                  const vy = (ccy - py) / S
                  const row = py * cw
                  for (let px = x0; px <= x1; px++) {
                    const vx = (px - ccx) / S
                    const r2 = vx * vx + vy * vy
                    if (r2 > 1) continue
                    const vz = Math.sqrt(1 - r2)
                    const wx = -syw * vx - sp * cyw * vy + cp * cyw * vz
                    const wy = cyw * vx - sp * syw * vy + cp * syw * vz
                    const wz = cp * vy + sp * vz
                    let tx = ((Math.atan2(wy, wx) * INV2PI + 0.5) * TW) | 0
                    let ty = ((0.5 - Math.asin(wz) * INVPI) * TH) | 0
                    if (tx < 0) tx = 0; else if (tx >= TW) tx = TW - 1
                    if (ty < 0) ty = 0; else if (ty >= TH) ty = TH - 1
                    out[row + px] = tex[ty * TW + tx]
                  }
                }
                this.ctx.putImageData(this.frame, 0, 0)
              }

              this.apply = () => {
                this.updateLod()
                if (this.farMode) {
                  this.renderCanvas()
                } else if (this.renderer === "canvas") {
                  this.renderPolygons()
                } else {
                  const cy = Math.cos(this.yaw), sy = Math.sin(this.yaw)
                  const cp = Math.cos(this.pitch), sp = Math.sin(this.pitch)
                  const s = this.S / this.r0
                  // Columns of diag(1,-1,1)·R_view — orthographic (no
                  // perspective), identical to the server projection.
                  this.fine.style.transform =
                    `matrix3d(${-sy * s},${sp * cy * s},${cp * cy * s},0,` +
                    `${cy * s},${sp * sy * s},${cp * sy * s},0,` +
                    `0,${-cp * s},${sp * s},0,` +
                    `${this.cx},${this.cy},0,1)`
                  // Layers start hidden (CSS) until their first transform
                  this.fine.style.visibility = "visible"
                }
                const S = this.S
                this.disc.style.left = (this.cx - S) + "px"
                this.disc.style.top = (this.cy - S) + "px"
                this.disc.style.width = (2 * S) + "px"
                this.disc.style.height = (2 * S) + "px"
              }

              this.schedule = () => {
                if (this.raf) return
                this.raf = requestAnimationFrame(() => { this.raf = null; this.apply() })
              }

              this.rotateBy = (dxPx, dyPx) => {
                this.yaw -= dxPx / this.S / Math.max(Math.cos(this.pitch), 0.25)
                const twoPi = 2 * Math.PI
                this.yaw -= twoPi * Math.floor(this.yaw / twoPi)
                this.pitch = Math.max(-this.maxPitch, Math.min(this.pitch + dyPx / this.S, this.maxPitch))
                this.schedule()
                this.sync(false)
              }

              // Mid-motion syncs keep the sidebar fresh; a "settled" sync
              // (drag end / motion pause) lets the server re-window the
              // fine tile DOM around the new view.
              this.sync = (force, settled) => {
                const now = Date.now()
                if (!force && now - this.lastSync < 250) {
                  if (!this.syncTimer) {
                    this.syncTimer = setTimeout(() => { this.syncTimer = null; this.sync(true, false) }, 250)
                  }
                  this.scheduleSettle()
                  return
                }
                if (this.syncTimer) { clearTimeout(this.syncTimer); this.syncTimer = null }
                this.lastSync = now
                this.pushEvent("view_sync", {yaw: this.yaw, pitch: this.pitch, scale: this.S, settled: !!settled})
                if (!settled) this.scheduleSettle()
              }

              // Settle fires 300ms after the last motion.
              this.settleTimer = null
              this.scheduleSettle = () => {
                clearTimeout(this.settleTimer)
                this.settleTimer = setTimeout(() => this.sync(true, true), 300)
              }

              // --- drag + pinch ---
              this.pointer = null
              this.moved = false
              this.touches = new Map()
              this.pinchDist = null

              this.el.addEventListener("pointerdown", (e) => {
                if (e.pointerType === "mouse" && e.button !== 0) return
                this.touches.set(e.pointerId, {x: e.clientX, y: e.clientY})

                if (this.touches.size === 2) {
                  // Second finger: abandon drag, enter pinch
                  this.pointer = null
                  this.moved = false
                  this.el.classList.remove("dragging")
                  const [a, b] = [...this.touches.values()]
                  this.pinchDist = Math.hypot(a.x - b.x, a.y - b.y)
                  this.el.setPointerCapture(e.pointerId)
                } else if (this.touches.size === 1) {
                  this.pointer = e.pointerId
                  this.last = {x: e.clientX, y: e.clientY}
                  this.moved = false
                }
              })

              this.el.addEventListener("pointermove", (e) => {
                if (this.pinchDist !== null && this.touches.has(e.pointerId)) {
                  this.touches.set(e.pointerId, {x: e.clientX, y: e.clientY})
                  if (this.touches.size === 2) {
                    const [a, b] = [...this.touches.values()]
                    const d = Math.hypot(a.x - b.x, a.y - b.y)
                    if (d > 0 && this.pinchDist > 0) {
                      this.S *= d / this.pinchDist
                      this.clampS()
                      this.pinchDist = d
                      this.schedule()
                      this.sync(false)
                    }
                  }
                  return
                }

                if (this.pointer === null || e.pointerId !== this.pointer) return
                const dx = e.clientX - this.last.x
                const dy = e.clientY - this.last.y
                if (!this.moved) {
                  if (Math.abs(dx) + Math.abs(dy) < 4) return
                  this.moved = true
                  this.el.setPointerCapture(this.pointer)
                  this.el.classList.add("dragging")
                }
                this.last = {x: e.clientX, y: e.clientY}
                this.rotateBy(dx, dy)
              })

              const end = (e) => {
                this.touches.delete(e.pointerId)

                if (this.pinchDist !== null && this.touches.size < 2) {
                  this.pinchDist = null
                  this.suppressClick = true
                  this.sync(true, true)
                  return
                }

                if (this.pointer === null || e.pointerId !== this.pointer) return
                if (this.moved) {
                  this.sync(true, true)
                  this.suppressClick = true
                }
                this.pointer = null
                this.moved = false
                this.el.classList.remove("dragging")
              }
              this.el.addEventListener("pointerup", end)
              this.el.addEventListener("pointercancel", end)

              // --- continuous wheel zoom ---
              this.el.addEventListener("wheel", (e) => {
                e.preventDefault()
                // deltaMode 1 = lines (Firefox wheels); normalize to ~pixels
                const dy = e.deltaMode === 1 ? e.deltaY * 16 : e.deltaY
                this.S *= Math.exp(-dy * 0.0015)
                this.clampS()
                this.schedule()
                this.sync(false)
              }, {passive: false})

              // --- keys (client-side in 3D mode) ---
              this.onKey = (e) => {
                switch (e.key) {
                  case "ArrowLeft": case "a": this.rotateBy(150, 0); break
                  case "ArrowRight": case "d": this.rotateBy(-150, 0); break
                  case "ArrowUp": case "w": this.rotateBy(0, 150); break
                  case "ArrowDown": case "s": this.rotateBy(0, -150); break
                  case "+": case "=": this.S *= 1.4; this.clampS(); this.schedule(); this.sync(false); break
                  case "-": case "_": this.S /= 1.4; this.clampS(); this.schedule(); this.sync(false); break
                }
              }
              window.addEventListener("keydown", this.onKey)

              // --- clicks: tile highlight up close, inverse-projected
              //     select_at on the impostor ---
              this.el.addEventListener("click", (e) => {
                if (this.suppressClick) {
                  this.suppressClick = false
                  return
                }

                if (this.farMode || this.renderer === "canvas") {
                  const r = this.el.getBoundingClientRect()
                  const p = this.unproject(e.clientX - r.left, e.clientY - r.top)
                  if (p) this.pushEvent("select_at", p)
                  return
                }

                const t = e.target
                if (t.classList && t.classList.contains("hex-cell3d")) {
                  this.el.querySelectorAll(".hex-cell3d.hex-selected")
                    .forEach((el) => el.classList.remove("hex-selected"))
                  t.classList.add("hex-selected")
                }
              })

              this.apply()
            },

            updated() {
              // Regenerate swaps the ignored subtree (new id) and changes
              // the texture URL — re-grab refs and reload the bake. The LOD
              // threshold and selection can also change server-side.
              this.grab()
              this.lodK = parseFloat(this.el.dataset.lodK) || this.lodK
              const sel = this.el.dataset.selectedId
              this.selectedId = sel ? parseInt(sel) : null
              this.loadTexture()
              this.apply()
            },

            destroyed() {
              window.removeEventListener("keydown", this.onKey)
              if (this.ro) this.ro.disconnect()
              if (this.raf) cancelAnimationFrame(this.raf)
              if (this.syncTimer) clearTimeout(this.syncTimer)
              if (this.settleTimer) clearTimeout(this.settleTimer)
              if (this.resizeTimer) clearTimeout(this.resizeTimer)
            }
          }
        </script>

        <%!-- Collapsed-sidebar opener --%>
        <button
          :if={!@sidebar_open}
          phx-click="toggle_sidebar"
          class="absolute top-1/2 right-0 -translate-y-1/2 btn btn-sm btn-ghost bg-base-200/80 rounded-r-none border border-base-300 z-10"
          title="Show info panel"
        >
          <.icon name="hero-chevron-left" class="w-4 h-4" />
        </button>

        <%!-- Sidebar --%>
        <div
          :if={@sidebar_open}
          class="w-72 bg-base-200 border-l border-base-300 overflow-y-auto p-4 space-y-6 flex-none"
        >
          <%!-- World info --%>
          <div>
            <div class="flex items-center justify-between mb-2">
              <h3 class="font-bold text-sm uppercase tracking-wide opacity-60">World Info</h3>
              <button
                phx-click="toggle_sidebar"
                class="btn btn-xs btn-square btn-ghost"
                title="Hide info panel"
              >
                <.icon name="hero-chevron-right" class="w-4 h-4" />
              </button>
            </div>
            <dl class="text-sm space-y-1">
              <div class="flex justify-between">
                <dt class="opacity-60">Seed</dt>
                <dd class="font-mono text-xs">{@world.seed}</dd>
              </div>
              <div class="flex justify-between">
                <dt class="opacity-60">Size</dt>
                <dd>GP({@world.frequency}) · {Globe.tile_count(@world.frequency)} tiles</dd>
              </div>
              <div class="flex justify-between">
                <dt class="opacity-60">View</dt>
                <dd>{deg(@yaw)}° / {deg(@pitch)}°</dd>
              </div>
              <div class="flex justify-between">
                <dt class="opacity-60">Zoom</dt>
                <dd>{@scale}px</dd>
              </div>
            </dl>
          </div>

          <div class="divider my-0"></div>

          <%!-- Selected tile --%>
          <div>
            <h3 class="font-bold text-sm uppercase tracking-wide opacity-60 mb-2">Selected Tile</h3>
            <div :if={@selected_tile == nil} class="text-sm opacity-40">
              Click a tile to inspect it
            </div>
            <dl :if={@selected_tile} class="text-sm space-y-1">
              <div class="flex justify-between">
                <dt class="opacity-60">Tile</dt>
                <dd>#{@selected_tile.id}</dd>
              </div>
              <div class="flex justify-between">
                <dt class="opacity-60">Position</dt>
                <dd>{format_latlon(@selected_tile.center)}</dd>
              </div>
              <div class="flex items-center justify-between">
                <dt class="opacity-60">Terrain</dt>
                <dd class="flex items-center gap-1.5">
                  <span class={["inline-block w-3 h-3 rounded-sm", terrain_class(@selected_terrain)]}>
                  </span>
                  {terrain_label(@selected_terrain)}
                </dd>
              </div>
              <div class="flex justify-between">
                <dt class="opacity-60">Neighbors</dt>
                <dd>{length(@selected_tile.neighbors)}</dd>
              </div>
              <div :if={@selected_tile.pentagon?} class="mt-1">
                <span class="badge badge-warning badge-sm">Pentagon (impassable)</span>
              </div>
            </dl>
          </div>

          <div class="divider my-0"></div>

          <%!-- Terrain statistics --%>
          <div>
            <h3 class="font-bold text-sm uppercase tracking-wide opacity-60 mb-2">Terrain Stats</h3>
            <div class="space-y-1">
              <div :for={{terrain, _count, pct} <- @stats} class="flex items-center gap-2 text-sm">
                <span class={["inline-block w-3 h-3 rounded-sm flex-none", terrain_class(terrain)]}>
                </span>
                <span class="flex-1">{terrain_label(terrain)}</span>
                <span class="opacity-60 font-mono text-xs">{pct}%</span>
              </div>
            </div>
          </div>

          <div class="divider my-0"></div>

          <%!-- Legend --%>
          <div>
            <h3 class="font-bold text-sm uppercase tracking-wide opacity-60 mb-2">Legend</h3>
            <div class="space-y-1">
              <div
                :for={{_terrain, color, label} <- @terrain_legend}
                class="flex items-center gap-2 text-sm"
              >
                <span class="inline-block w-4 h-3 rounded-sm flex-none" style={"background:#{color}"}>
                </span>
                <span>{label}</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
