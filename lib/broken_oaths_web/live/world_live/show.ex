defmodule BrokenOathsWeb.WorldLive.Show do
  @moduledoc """
  The globe world-builder — `/worlds/:id`, the map editor's classic
  (server-rendered tile DOM) and 3D (pushed-geometry canvas/matrix3d)
  render modes, seed regeneration, and the collapsible info sidebar.

  This LiveView stays an imperative shell: `mount/3`/`handle_params/3`/
  `handle_event/3`/`handle_info/2` own the socket and every side effect
  (`assign`/`push_event`/`push_patch` — there is no multiplayer state
  here, just one editor's own view of a `BrokenOaths.Worlds.World`).
  Pure derivation — angle/zoom parsing, projection math, 3D tile-window
  payload building, formatting — lives in
  `BrokenOathsWeb.WorldLive.ShowView`; render regions with no
  `phx-hook` of their own (`ControlsBar`, `ViewportOverlay`, `Sidebar`)
  are extracted `Phoenix.Component`s, the same "imperative shell,
  functional core" split `GameLive.PlayView`/`GameLive.BoardOverlays`
  already establish for the board LiveView one layer up from the
  `.code_my_spec/knowledge/genserver_decomposition.md` pragdave
  pattern.

  The globe viewport's two mode divs (`phx-hook=".GlobeDrag"` and
  `phx-hook=".Globe3D"`) and their colocated `<script>` hook bodies
  stay here rather than moving into their own components: a colocated
  hook's `phx-hook="."` name is rewritten to
  `"\#{inspect(caller.module)}.Name"` at compile time, so a hook's
  trigger element and its script tag can only ever live in the SAME
  module — the same reasoning `GameLive.BoardOverlays`'s own moduledoc
  documents for the game board's `.Board` hook.
  """

  use BrokenOathsWeb, :live_view

  alias BrokenOaths.Worlds
  alias BrokenOaths.Worlds.{Facets, Generator, Globe, Terrain, Texture, Weather}
  alias BrokenOathsWeb.WorldLive.{ControlsBar, ShowView, Sidebar, ViewportOverlay}

  # Zoom levels as multiples of the "whole globe fits" scale (min(w,h)/2
  # pixels per sphere radius). Relative zoom keeps the on-screen TILE count
  # roughly constant at any viewport size, so a full-screen globe costs the
  # same as a small one — tiles just render larger.
  @zoom_factors [1.0, 1.4286, 2.0, 2.8571, 4.0, 5.7143]
  @default_zoom_index 2

  # Viewport size before the client reports its real dimensions.
  @default_container_w 960
  @default_container_h 700

  # Full day/night cycle length in seconds (purely visual for now; move
  # sun state server-side when gameplay starts caring about time of day).
  @sun_period 1800

  # Rotation step ≈ this many pixels of screen travel at the view center.
  @pan_px 150
  # Pitch clamp (±85.9°) keeps the up-vector sane; pole tiles are still
  # dead-center visible well before the clamp.
  @max_pitch 1.50

  # -------------------------------------------------------------------
  # Mount
  # -------------------------------------------------------------------

  def mount(%{"id" => id}, _session, socket) do
    world = Worlds.get_world!(id)
    worlds = Worlds.list_worlds()

    mesh = Globe.get(world.frequency)
    %{terrain: terrain_map, elevation: elevation_map} = Generator.generate_maps(world.seed, mesh)
    stats = Generator.terrain_stats(terrain_map)

    socket =
      socket
      |> assign(
        world: world,
        worlds: worlds,
        mesh: mesh,
        terrain_map: terrain_map,
        elevation_map: elevation_map,
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
        sun_period: @sun_period,
        weather_epoch: Weather.current_epoch(),
        sidebar_open: false,
        selected_tile: nil,
        selected_terrain: nil,
        page_title: world.name
      )
      |> compute_view()

    # Weather evolves by epoch: wake at each boundary to re-push the new
    # cloud map and bust the airspace texture URL.
    if connected?(socket) do
      Process.send_after(self(), :weather_epoch, Weather.ms_until_next_epoch())
    end

    {:ok, socket}
  end

  # Render mode and the camera live in the URL (?mode=classic&yaw=..&pitch=..&zoom=..),
  # so views survive refreshes, are shareable, and — critically — tests can
  # mount the LiveView at any exact camera state. The 3D globe is the
  # default; ?mode=classic keeps the selector-testable DOM board reachable.
  def handle_params(params, _uri, socket) do
    mode = if params["mode"] == "classic", do: :classic, else: :three_d
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
    %{container_w: w, container_h: h} = socket.assigns

    case ShowView.view_param_changes(params, w, h, @zoom_factors, @max_pitch) do
      [] -> {socket, false}
      changes -> {assign(socket, changes), true}
    end
  end

  # -------------------------------------------------------------------
  # Weather epochs
  # -------------------------------------------------------------------

  def handle_info(:weather_epoch, socket) do
    Process.send_after(self(), :weather_epoch, Weather.ms_until_next_epoch())

    socket = assign(socket, weather_epoch: Weather.current_epoch())

    socket =
      if socket.assigns.render_mode == :three_d,
        do: push_airspace(socket),
        else: socket

    {:noreply, socket}
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

    view = [yaw: ShowView.deg(yaw), pitch: ShowView.deg(pitch), zoom: scale]

    to =
      if socket.assigns.render_mode == :classic,
        do: ~p"/worlds/#{world.id}?#{view}",
        else: ~p"/worlds/#{world.id}?#{[{:mode, "classic"} | view]}"

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
    {yaw, pitch, scale} = ShowView.normalize_view_sync(yaw, pitch, scale, @max_pitch)

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
        lod_k: ShowView.lod_k(socket.assigns.world.frequency, coarse)
      )

    socket =
      case socket.assigns.render_mode do
        :three_d -> rewindow(socket)
        :classic -> compute_view(socket)
      end

    {:noreply, socket}
  end

  # Canvas clicks at ANY zoom: the hook inverse-projects to a unit-sphere
  # point and the nearest real tile gets selected.
  def handle_event("select_at", %{"x" => x, "y" => y, "z" => z}, socket)
      when is_number(x) and is_number(y) and is_number(z) do
    tile = Globe.nearest_tile(socket.assigns.mesh, {x * 1.0, y * 1.0, z * 1.0})

    socket =
      socket
      |> assign(
        selected_tile: tile,
        selected_terrain: Map.get(socket.assigns.terrain_map, tile.id)
      )
      |> push_selection()

    {:noreply, socket}
  end

  def handle_event("select_tile", %{"id" => id}, socket) do
    id = String.to_integer(id)
    tile = Globe.tile(socket.assigns.mesh, id)
    terrain = Map.get(socket.assigns.terrain_map, id)

    socket =
      socket
      |> assign(selected_tile: tile, selected_terrain: terrain)
      |> push_selection()

    {:noreply, socket}
  end

  def handle_event("regenerate", _params, socket) do
    new_seed = :rand.uniform(999_999_999)

    case Worlds.update_world(socket.assigns.world, %{seed: new_seed}) do
      {:ok, world} ->
        # The mesh depends only on frequency; only terrain regenerates.
        %{terrain: terrain_map, elevation: elevation_map} =
          Generator.generate_maps(world.seed, socket.assigns.mesh)

        stats = Generator.terrain_stats(terrain_map)
        worlds = Worlds.list_worlds()

        socket =
          socket
          |> assign(
            world: world,
            worlds: worlds,
            terrain_map: terrain_map,
            elevation_map: elevation_map,
            stats: stats,
            selected_tile: nil,
            selected_terrain: nil,
            page_title: world.name
          )
          |> maybe_compute_view()

        # New seed = new bucket: pushes a recolored tile window in 3D mode
        socket =
          if socket.assigns.render_mode == :three_d,
            do: socket |> rewindow() |> push_selection() |> push_airspace(),
            else: socket

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
    {dyaw, dpitch} = ShowView.drag_delta(dx, dy, scale, pitch)

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
        do: ~p"/worlds/#{id}",
        else: ~p"/worlds/#{id}?mode=classic"

    {:noreply, push_navigate(socket, to: to)}
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp do_rotate(socket, dir) do
    {dyaw, dpitch} =
      ShowView.rotate_delta(dir, socket.assigns.scale, socket.assigns.pitch, @pan_px)

    {:noreply, apply_rotation(socket, dyaw, dpitch)}
  end

  defp apply_rotation(socket, dyaw, dpitch) do
    socket
    |> assign(
      yaw: ShowView.wrap_yaw(socket.assigns.yaw + dyaw),
      pitch: ShowView.clamp_pitch(socket.assigns.pitch + dpitch, @max_pitch)
    )
    |> compute_view()
  end

  # Selection as pushed geometry: both canvas render paths (texture far,
  # polygons near) draw the ring from it, so clicks are visible at any zoom.
  defp push_selection(%{assigns: %{render_mode: :three_d}} = socket) do
    push_event(
      socket,
      "globe3d:selected",
      ShowView.selection_payload(socket.assigns.selected_tile)
    )
  end

  defp push_selection(socket), do: socket

  # Airspace: the sparse per-tile cloud map, pushed once per world/seed.
  # The near renderer draws these as translucent hexes one shell above
  # the surface; the far renderer samples the baked airspace texture.
  defp push_airspace(socket) do
    %{world: world, mesh: mesh} = socket.assigns
    push_event(socket, "globe3d:airspace", ShowView.airspace_payload(world, mesh))
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
    |> push_selection()
    |> push_airspace()
  end

  defp set_mode(socket, :classic) do
    %{container_w: w, container_h: h, scale: scale} = socket.assigns

    socket
    |> assign(
      render_mode: :classic,
      facets: [],
      view_bucket: nil,
      # Snap the continuous 3D scale back to the nearest zoom level
      zoom_index: ShowView.nearest_zoom_index(w, h, scale, @zoom_factors)
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

    %{container_w: w, container_h: h, facets: facets, world: world, terrain_map: terrain_map} =
      socket.assigns

    %{device_coarse: coarse, renderer3d: renderer3d} = socket.assigns

    v = ShowView.view_vector(yaw, pitch)
    bucket = ShowView.view_bucket(v, scale, w, h, world.seed, coarse, renderer3d)

    if bucket == socket.assigns.view_bucket do
      socket
    else
      min_dot = ShowView.window_min_dot(world.frequency, scale, w, h, coarse)

      payload =
        case renderer3d do
          :canvas ->
            ShowView.canvas_window_payload(
              socket.assigns.mesh,
              terrain_map,
              socket.assigns.elevation_map,
              min_dot,
              v
            )

          :css3d ->
            ShowView.css3d_window_payload(facets, terrain_map, min_dot, v)
        end

      socket
      |> assign(view_bucket: bucket)
      |> push_event("globe3d:window", payload)
    end
  end

  # 3D mode never re-projects server-side; the tile DOM is static.
  defp maybe_compute_view(%{assigns: %{render_mode: :three_d}} = socket), do: socket
  defp maybe_compute_view(socket), do: compute_view(socket)

  defp compute_view(socket) do
    %{mesh: mesh, terrain_map: tm, yaw: yaw, pitch: pitch, zoom_index: zi} = socket.assigns
    %{container_w: w, container_h: h} = socket.assigns

    %{visible_tiles: visible_tiles, scale: scale} =
      ShowView.compute_view(mesh, tm, yaw, pitch, zi, w, h, @zoom_factors)

    assign(socket, visible_tiles: visible_tiles, scale: scale)
  end

  # -------------------------------------------------------------------
  # Render
  # -------------------------------------------------------------------

  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-[calc(100vh-64px)]" phx-window-keydown="keydown">
      <%!-- Controls bar --%>
      <ControlsBar.bar world={@world} worlds={@worlds} render_mode={@render_mode} scale={@scale} />

      <%!-- Main content --%>
      <div class="flex flex-1 min-h-0 relative">
        <%!-- Globe viewport --%>
        <div class="flex-1 overflow-hidden space-bg relative">
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
                @selected_tile && @selected_tile.id == tile.id && "hex-selected"
              ]}
              phx-click="select_tile"
              phx-value-id={tile.id}
              style={"left:#{tile.left}px;top:#{tile.top}px;width:#{tile.width}px;height:#{tile.height}px;clip-path:#{tile.clip_path};background-color:#{Terrain.color(tile.terrain)};"}
              title={"##{tile.id} #{Terrain.label(tile.terrain)}"}
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
            data-sun-period={@sun_period}
            data-renderer={@renderer3d}
            data-selected-id={@selected_tile && @selected_tile.id}
            data-texture={
              ~p"/worlds/#{@world.id}/texture.png?seed=#{@world.seed}&v=#{Texture.version()}"
            }
            data-airspace={
              ~p"/worlds/#{@world.id}/airspace.png?seed=#{@world.seed}&v=#{Texture.version()}&e=#{@weather_epoch}"
            }
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
          <ViewportOverlay.controls render_mode={@render_mode} />
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
                  this.buildShades()
                  this.schedule()
                } else if (payload.html && this.fine) {
                  this.fine.innerHTML = payload.html
                  this.schedule()
                }
              })

              // 16 brightness steps per terrain color (0.30 night .. 1.15
              // sunlit peak) — precomputed so per-frame shading allocates
              // nothing.
              this.shades = null
              this.buildShades = () => {
                this.shades = this.palette.map((hex) => {
                  const r = parseInt(hex.slice(1, 3), 16)
                  const g = parseInt(hex.slice(3, 5), 16)
                  const b = parseInt(hex.slice(5, 7), 16)
                  const out = []
                  for (let i = 0; i < 16; i++) {
                    const f = 0.30 + (i / 15) * 0.85
                    out.push(
                      `rgb(${Math.min(255, Math.round(r * f))},${Math.min(255, Math.round(g * f))},${Math.min(255, Math.round(b * f))})`
                    )
                  }
                  return out
                })
              }

              // Sun direction from wall clock: one full day per sun-period
              // seconds, with a slight axial tilt. Visual-only for now.
              this.sunPeriod = parseFloat(this.el.dataset.sunPeriod) || 1800
              this.sunVec = () => {
                const a = ((Date.now() / 1000) % this.sunPeriod) / this.sunPeriod * 2 * Math.PI
                const tz = 0.20
                const n = Math.sqrt(1 + tz * tz)
                return [Math.cos(a) / n, Math.sin(a) / n, tz / n]
              }
              // Keep the terminator creeping while idle
              this.sunTimer = setInterval(() => this.schedule(), 10000)

              // Selection geometry — drawable at any zoom, in both render
              // paths, independent of the current tile window.
              this.selected = null
              this.handleEvent("globe3d:selected", (sel) => {
                this.selected = sel.id === null ? null : sel
                this.schedule()
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

                // Airspace: the cloud-layer bake (palette+tRNS, so the
                // decoded pixels carry per-tile alpha)
                const aurl = this.el.dataset.airspace
                if (aurl && aurl !== this.airspaceUrl) {
                  this.airspaceUrl = aurl
                  this.decode(aurl, (tex) => {
                    if (this.airspaceUrl === aurl) {
                      this.atex = tex
                      this.schedule()
                    }
                  })
                }
              }
              this.atex = null
              this.airspaceUrl = null

              // Airspace near path: sparse tile id -> cloud level (1..3),
              // drawn as translucent hexes one shell above the surface.
              // Base RGBA per level mirrors Worlds.Weather.palette/0;
              // 16-step day/night shade tables like the terrain pass.
              this.airspace = null
              this.stormCells = null
              this.tileArc = 0.0205
              this.cloudShades = null
              this.handleEvent("globe3d:airspace", ({levels, storms, arc}) => {
                this.airspace = levels
                this.stormCells = storms || []
                if (arc) this.tileArc = arc
                const base = {1: [250, 251, 253, 96], 2: [240, 244, 249, 175], 3: [104, 110, 124, 215]}
                this.cloudShades = {}
                for (const lvl of [1, 2, 3]) {
                  const [r, g, b, a255] = base[lvl]
                  const a = (a255 / 255).toFixed(3)
                  const steps = []
                  for (let i = 0; i < 16; i++) {
                    const f = 0.35 + 0.65 * (i / 15)
                    steps.push("rgba(" + ((r * f) | 0) + "," + ((g * f) | 0) + "," + ((b * f) | 0) + "," + a + ")")
                  }
                  this.cloudShades[lvl] = steps
                }
                this.schedule()
              })

              // Cloud shell altitude, as a multiple of the surface radius
              this.ALT = 1.035

              // Rain + lightning animate at a low tick while any
              // rain-bearing tile is on screen (near view only)
              this.hasWeatherAnim = false
              this.weatherTimer = setInterval(() => {
                if (this.hasWeatherAnim && !document.hidden) this.schedule()
              }, 240)

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

              // World vector for a screen point — shared render core.
              this.unproject = (sx, sy) => {
                return window.GlobeRender.unproject(
                  {yaw: this.yaw, pitch: this.pitch, scale: this.S, cx: this.cx, cy: this.cy},
                  sx, sy
                )
              }

              // Art parity with the game board (issue dd5f2867): the same
              // sprites and ground textures via the shared render core.
              this.sprites = window.GlobeRender.loadSprites(() => this.schedule())
              this.terrainTex = window.GlobeRender.loadTerrainTextures(() => this.schedule())
              this.patterns = window.GlobeRender.patternPool(this.terrainTex)

              // Near mode, vector renderer: the windowed tiles as filled 2D
              // paths — crisp at any zoom, no DOM, no compositor limits.
              this.renderPolygons = () => {
                const tiles = this.tiles
                const ctx = this.ctx
                if (!ctx) return
                ctx.clearRect(0, 0, this.canvas.width, this.canvas.height)
                if (!tiles) return

                const GR = window.GlobeRender
                const k = this.pxScale
                const S = this.S * k, ccx = this.cx * k, ccy = this.cy * k
                const R = GR.rot({yaw: this.yaw, pitch: this.pitch, scale: S, cx: ccx, cy: ccy})
                const [sun_x, sun_y, sun_z] = this.sunVec()

                // Painter's order (far first) so relief-lifted tiles at the
                // rim overlap their lower neighbors correctly
                const order = []
                for (const row of tiles) {
                  const z = GR.depth(R, row[4], row[5], row[6])
                  if (z > 0.02) order.push([z, row])
                }
                order.sort((a, b) => a[0] - b[0])

                for (const [, row] of order) {
                  // Day/night: smoothstep across the terminator, plus a
                  // brightness accent for high ground
                  const light = row[4] * sun_x + row[5] * sun_y + row[6] * sun_z
                  let t = (light + 0.15) / 0.3
                  t = t < 0 ? 0 : t > 1 ? 1 : t
                  t = t * t * (3 - 2 * t)
                  const h = row[7]
                  const relief = Math.max(h - 0.40, 0)
                  const f = 0.30 + t * (0.62 + relief * 0.55)
                  let idx = Math.round(((f - 0.30) / 0.85) * 15)
                  idx = idx < 0 ? 0 : idx > 15 ? 15 : idx
                  const color = this.shades ? this.shades[row[1]][idx] : this.palette[row[1]]

                  // Radial extrusion: land rises above sea level (visible
                  // as silhouette relief at the planet's rim)
                  const lift = 1 + relief * 0.04

                  // Ground texture pattern (anchored to the projected tile
                  // center, like the game board) with the flat shade as
                  // fallback; day/night arrives as a darkness overlay so
                  // the terminator survives the pattern fill.
                  const c = GR.project(R, row[4], row[5], row[6])
                  const pat = this.patterns.for(ctx, row[3], S, c.px, c.py)

                  ctx.beginPath()
                  GR.tracePolygon(ctx, R, row, 8, lift)
                  ctx.fillStyle = pat || color
                  ctx.fill()
                  // Same-color stroke seals seams — slightly wider than a
                  // hairline to also cover relief-lift gaps at elevation steps
                  ctx.strokeStyle = pat || color
                  ctx.lineWidth = Math.max(1.5, k)
                  ctx.stroke()

                  if (pat) {
                    const dark = Math.max(0, Math.min(1 - f, 0.75))
                    if (dark > 0.02) {
                      ctx.fillStyle = "rgba(8,12,26," + dark.toFixed(3) + ")"
                      ctx.fill()
                    }
                  }
                }

                // Terrain decor billboards — art parity with the game
                // board, dimmed through the night side, skipped below
                // readability size.
                ctx.imageSmoothingEnabled = false
                const decorSize = Math.min(Math.max(S * this.tileArc * 1.7, 10 * k), 72 * k)
                if (decorSize >= 10 * k) {
                  for (const [, row] of order) {
                    const img = GR.ready(row[2] && this.sprites[row[2]])
                    if (!img) continue
                    const light = row[4] * sun_x + row[5] * sun_y + row[6] * sun_z
                    let t = (light + 0.15) / 0.3
                    t = t < 0 ? 0 : t > 1 ? 1 : t
                    const c = GR.project(R, row[4], row[5], row[6])
                    ctx.globalAlpha = 0.45 + 0.55 * t
                    GR.drawBillboard(ctx, img, c.px, c.py, decorSize)
                  }
                  ctx.globalAlpha = 1
                }

                // Airspace pass: cloud tiles as translucent hexes at
                // ALT above the surface — same geometry, same painter
                // order (all clouds sit above all terrain). Storm cells
                // (level 3) strike with lightning.
                this.hasWeatherAnim = false
                if (this.airspace && this.cloudShades) {
                  const A = this.ALT
                  const storms = []

                  for (const [, row] of order) {
                    const lvl = this.airspace[row[0]]
                    if (!lvl) continue
                    const light = row[4] * sun_x + row[5] * sun_y + row[6] * sun_z
                    let t = (light + 0.15) / 0.3
                    t = t < 0 ? 0 : t > 1 ? 1 : t
                    t = t * t * (3 - 2 * t)
                    let idx = Math.round(t * 15)
                    const style = this.cloudShades[lvl][idx]

                    ctx.beginPath()
                    GR.tracePolygon(ctx, R, row, 8, A)
                    ctx.fillStyle = style
                    ctx.fill()

                    if (lvl === 3) storms.push(row)
                  }

                  if (storms.length) {
                    this.hasWeatherAnim = true

                    // Lightning: storm cells strike on a hash-flickered
                    // ~480ms window — jagged bolt cloud->ground plus a
                    // flash refill of the hex
                    const bucket = (Date.now() / 480) | 0
                    for (const row of storms) {
                      const id = row[0]
                      const h = ((id + 1) * 2654435761 ^ bucket * 40503) >>> 0
                      if (h % 9 !== 0) continue

                      const g = GR.project(R, row[4], row[5], row[6])
                      const c2 = GR.project(R, row[4] * A, row[5] * A, row[6] * A)
                      const fc = GR.project(R, row[8], row[9], row[10])
                      const gx = g.px, gy = g.py
                      const cx2 = c2.px, cy2 = c2.py
                      const hr = Math.hypot(fc.px - gx, fc.py - gy)

                      // Bolt: 4 jagged segments with per-strike jitter
                      ctx.beginPath()
                      ctx.moveTo(cx2, cy2)
                      for (let sgi = 1; sgi <= 4; sgi++) {
                        const f2 = sgi / 4
                        const jit = (((h >>> (sgi * 4)) & 15) / 15 - 0.5) * hr * 0.7
                        ctx.lineTo(cx2 + (gx - cx2) * f2 + (sgi < 4 ? jit : 0), cy2 + (gy - cy2) * f2)
                      }
                      ctx.strokeStyle = "rgba(255,250,190,0.95)"
                      ctx.lineWidth = Math.max(1.5, k)
                      ctx.stroke()

                      // Lit-from-within flash on the storm hex
                      ctx.beginPath()
                      GR.tracePolygon(ctx, R, row, 8, A)
                      ctx.fillStyle = "rgba(255,252,215,0.30)"
                      ctx.fill()
                    }
                  }
                }

                this.drawSelection()
              }

              // Selection ring, drawn over either render path at any zoom.
              this.drawSelection = () => {
                const sel = this.selected
                if (!sel) return
                const GR = window.GlobeRender
                const ctx = this.ctx
                const k = this.pxScale
                const R = GR.rot({
                  yaw: this.yaw, pitch: this.pitch,
                  scale: this.S * k, cx: this.cx * k, cy: this.cy * k
                })

                const [cx0, cy0, cz0] = sel.center
                if (GR.depth(R, cx0, cy0, cz0) <= 0.02) return

                ctx.beginPath()
                GR.tracePolygon(ctx, R, sel.corners, 0)
                ctx.strokeStyle = "#ffffff"
                ctx.lineWidth = Math.max(2 * k, 2)
                ctx.stroke()
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
                const atexObj = this.atex
                const atex = atexObj && atexObj.data, AW = atexObj && atexObj.w, AH = atexObj && atexObj.h
                const A = this.ALT, A2 = A * A
                const RMAX = atex ? A : 1
                const INV2PI = 1 / (2 * Math.PI), INVPI = 1 / Math.PI
                const [sun_x, sun_y, sun_z] = this.sunVec()
                const x0 = Math.max(0, Math.floor(ccx - S * RMAX)), x1 = Math.min(cw - 1, Math.ceil(ccx + S * RMAX))
                const y0 = Math.max(0, Math.floor(ccy - S * RMAX)), y1 = Math.min(ch - 1, Math.ceil(ccy + S * RMAX))
                for (let py = y0; py <= y1; py++) {
                  const vy = (ccy - py) / S
                  const row = py * cw
                  for (let px = x0; px <= x1; px++) {
                    const vx = (px - ccx) / S
                    const r2 = vx * vx + vy * vy
                    if (r2 > A2 || (r2 > 1 && !atex)) continue

                    let pr = 0, pg = 0, pb = 0, pa = 0

                    if (r2 <= 1) {
                      // Surface sample, day/night shaded
                      const vz = Math.sqrt(1 - r2)
                      const wx = -syw * vx - sp * cyw * vy + cp * cyw * vz
                      const wy = cyw * vx - sp * syw * vy + cp * syw * vz
                      const wz = cp * vy + sp * vz
                      const lon = Math.atan2(wy, wx)
                      const lat = Math.asin(wz)
                      let tx = ((lon * INV2PI + 0.5) * TW) | 0
                      let ty = ((0.5 - lat * INVPI) * TH) | 0
                      if (tx < 0) tx = 0; else if (tx >= TW) tx = TW - 1
                      if (ty < 0) ty = 0; else if (ty >= TH) ty = TH - 1

                      const light = wx * sun_x + wy * sun_y + wz * sun_z
                      let t = (light + 0.15) / 0.3
                      t = t < 0 ? 0 : t > 1 ? 1 : t
                      t = t * t * (3 - 2 * t)
                      const f = 0.32 + t * 0.68

                      const v = tex[ty * TW + tx]
                      pr = ((v & 255) * f) | 0
                      pg = (((v >>> 8) & 255) * f) | 0
                      pb = (((v >>> 16) & 255) * f) | 0
                      pa = 255
                    }

                    // Airspace shell: unproject the same pixel onto the
                    // cloud sphere at ALT and alpha-blend the hex bake.
                    // Different radius = real parallax against the ground
                    // and a cloud crescent past the limb.
                    if (atex) {
                      const azn = Math.sqrt(A2 - r2) / A
                      const axn = vx / A, ayn = vy / A
                      const wx = -syw * axn - sp * cyw * ayn + cp * cyw * azn
                      const wy = cyw * axn - sp * syw * ayn + cp * syw * azn
                      const wz = cp * ayn + sp * azn
                      let ax = ((Math.atan2(wy, wx) * INV2PI + 0.5) * AW) | 0
                      let ay = ((0.5 - Math.asin(wz) * INVPI) * AH) | 0
                      if (ax < 0) ax = 0; else if (ax >= AW) ax = AW - 1
                      if (ay < 0) ay = 0; else if (ay >= AH) ay = AH - 1
                      const cv = atex[ay * AW + ax]
                      const ca = cv >>> 24
                      if (ca > 0) {
                        const light = wx * sun_x + wy * sun_y + wz * sun_z
                        let t = (light + 0.15) / 0.3
                        t = t < 0 ? 0 : t > 1 ? 1 : t
                        t = t * t * (3 - 2 * t)
                        const f = 0.35 + t * 0.65
                        const cr = ((cv & 255) * f) | 0
                        const cg = (((cv >>> 8) & 255) * f) | 0
                        const cb = (((cv >>> 16) & 255) * f) | 0
                        const ia = 255 - ca
                        pr = (cr * ca + pr * ia + 127) / 255 | 0
                        pg = (cg * ca + pg * ia + 127) / 255 | 0
                        pb = (cb * ca + pb * ia + 127) / 255 | 0
                        pa = Math.max(pa, ca)
                      }
                    }

                    if (pa > 0) out[row + px] = (pa << 24) | (pb << 16) | (pg << 8) | pr
                  }
                }
                this.ctx.putImageData(this.frame, 0, 0)

                // Lightning at far zoom: storm cells strike over the
                // warped texture using their pushed centers
                this.hasWeatherAnim = false
                if (this.stormCells && this.stormCells.length) {
                  const ctx = this.ctx
                  const A = this.ALT
                  const bucket = (Date.now() / 480) | 0
                  const hr = Math.max(S * this.tileArc * 0.62, 2)
                  let visible = false
                  for (let ci = 0; ci < this.stormCells.length; ci++) {
                    const c = this.stormCells[ci]
                    const x = c[0], y = c[1], z = c[2]
                    const vz2 = cp * cyw * x + cp * syw * y + sp * z
                    if (vz2 < 0.1) continue
                    const gx = ccx + S * (-syw * x + cyw * y)
                    const gy = ccy - S * (-sp * cyw * x - sp * syw * y + cp * z)
                    if (gx < -hr || gx > cw + hr || gy < -hr || gy > ch + hr) continue
                    visible = true

                    const h = ((ci + 1) * 2654435761 ^ bucket * 40503) >>> 0
                    if (h % 9 !== 0) continue

                    const cx2 = ccx + S * A * (-syw * x + cyw * y)
                    const cy2 = ccy - S * A * (-sp * cyw * x - sp * syw * y + cp * z)

                    // Flash core reads at any distance; bolt when there's
                    // room between the cloud shell and the ground
                    ctx.beginPath()
                    ctx.arc(cx2, cy2, hr * 0.85, 0, 6.2832)
                    ctx.fillStyle = "rgba(255,252,215,0.5)"
                    ctx.fill()

                    if (Math.hypot(gx - cx2, gy - cy2) > 3) {
                      ctx.beginPath()
                      ctx.moveTo(cx2, cy2)
                      for (let sgi = 1; sgi <= 4; sgi++) {
                        const f2 = sgi / 4
                        const jit = (((h >>> (sgi * 4)) & 15) / 15 - 0.5) * hr * 0.7
                        ctx.lineTo(cx2 + (gx - cx2) * f2 + (sgi < 4 ? jit : 0), cy2 + (gy - cy2) * f2)
                      }
                      ctx.strokeStyle = "rgba(255,250,190,0.9)"
                      ctx.lineWidth = Math.max(1, q)
                      ctx.stroke()
                    }
                  }
                  this.hasWeatherAnim = visible
                }

                this.drawSelection()
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
              if (this.sunTimer) clearInterval(this.sunTimer)
              if (this.weatherTimer) clearInterval(this.weatherTimer)
            }
          }
        </script>

        <%!-- Collapsed-sidebar opener + info panel --%>
        <Sidebar.panel
          sidebar_open={@sidebar_open}
          world={@world}
          yaw={@yaw}
          pitch={@pitch}
          scale={@scale}
          selected_tile={@selected_tile}
          selected_terrain={@selected_terrain}
          stats={@stats}
        />
      </div>
    </div>
    """
  end
end
