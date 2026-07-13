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

  # Coarse LOD frequency for 3D mode. When the disc edge is visible the
  # whole front hemisphere is on screen (~half of 10f²+2 tiles), which
  # overwhelms the compositor at f=54; the coarse globe keeps that around
  # ~700 quads (smooth compositing lives in the hundreds). Terrain comes
  # from the same seeded noise field, so the continents match the
  # full-detail globe.
  @lod_frequency 12

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
        facets: [],
        coarse_facets: [],
        coarse_terrain: %{},
        selected_tile: nil,
        selected_terrain: nil,
        page_title: world.name,
        terrain_legend: @terrain_legend
      )
      |> compute_view()

    {:ok, socket}
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
    case socket.assigns.render_mode do
      :classic ->
        world = socket.assigns.world

        {:noreply,
         assign(socket,
           render_mode: :three_d,
           facets: Facets.get(world.frequency),
           coarse_facets: Facets.get(@lod_frequency),
           coarse_terrain: coarse_terrain(world.seed),
           visible_tiles: []
         )}

      :three_d ->
        # Snap the continuous 3D scale back to the nearest zoom level
        %{container_w: w, container_h: h, scale: scale} = socket.assigns
        fit = min(w, h) / 2

        zoom_index =
          @zoom_factors
          |> Enum.with_index()
          |> Enum.min_by(fn {factor, _} -> abs(factor * fit - scale) end)
          |> elem(1)

        socket =
          socket
          |> assign(
            render_mode: :classic,
            facets: [],
            coarse_facets: [],
            coarse_terrain: %{},
            zoom_index: zoom_index
          )
          |> compute_view()

        {:noreply, socket}
    end
  end

  # The Globe3D hook reports its settled view so the sidebar and any later
  # mode switch stay consistent.
  def handle_event("view_sync", %{"yaw" => yaw, "pitch" => pitch, "scale" => scale}, socket)
      when is_number(yaw) and is_number(pitch) and is_number(scale) do
    two_pi = 2 * :math.pi()
    yaw = yaw * 1.0
    yaw = yaw - two_pi * Float.floor(yaw / two_pi)
    pitch = min(max(pitch * 1.0, -@max_pitch), @max_pitch)
    scale = scale |> max(50) |> min(10_000) |> round()

    {:noreply, assign(socket, yaw: yaw, pitch: pitch, scale: scale)}
  end

  # A coarse-LOD tile lives in a different mesh; select the nearest tile of
  # the real world mesh instead.
  def handle_event("select_tile", %{"id" => id, "lod" => "coarse"}, socket) do
    coarse = Globe.tile(Globe.get(@lod_frequency), String.to_integer(id))
    tile = Globe.nearest_tile(socket.assigns.mesh, coarse.center)

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

        socket =
          if socket.assigns.render_mode == :three_d do
            assign(socket, coarse_terrain: coarse_terrain(world.seed))
          else
            socket
          end

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
    {:noreply, push_navigate(socket, to: ~p"/worlds/#{id}")}
  end

  # Both hooks report the viewport's real size on mount and resize.
  def handle_event("viewport_resize", %{"w" => w, "h" => h}, socket)
      when is_number(w) and is_number(h) do
    w = w |> round() |> max(200) |> min(4000)
    h = h |> round() |> max(200) |> min(4000)

    socket =
      socket
      |> assign(container_w: w, container_h: h)
      |> maybe_compute_view()

    {:noreply, socket}
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
    two_pi = 2 * :math.pi()
    yaw = socket.assigns.yaw + dyaw
    yaw = yaw - two_pi * Float.floor(yaw / two_pi)
    pitch = max(-@max_pitch, min(socket.assigns.pitch + dpitch, @max_pitch))

    socket
    |> assign(yaw: yaw, pitch: pitch)
    |> compute_view()
  end

  # 3D mode never re-projects server-side; the tile DOM is static.
  defp maybe_compute_view(%{assigns: %{render_mode: :three_d}} = socket), do: socket
  defp maybe_compute_view(socket), do: compute_view(socket)

  # Same seed, same noise field, coarser mesh — continents match the
  # full-detail globe.
  defp coarse_terrain(seed), do: Generator.generate_terrain_map(seed, Globe.get(@lod_frequency))

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
      <div class="flex flex-1 min-h-0">
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
          >
            <div class="globe-disc globe-disc3d"></div>

            <%!-- Keyed by world+seed so Regenerate swaps the ignored DOM.
                 Two detail levels; the hook shows exactly one: full detail
                 while the disc edge is off-screen, coarse when the edge is
                 visible (the whole hemisphere would otherwise composite). --%>
            <div id={"globe3d-#{@world.id}-#{@world.seed}"} phx-update="ignore" class="globe3d-anchor">
              <div class="globe3d globe3d-fine">
                <div
                  :for={facet <- @facets}
                  class={["hex-cell3d", terrain_class(Map.get(@terrain_map, facet.id, :ocean))]}
                  phx-click="select_tile"
                  phx-value-id={facet.id}
                  style={"width:#{facet.w}px;height:#{facet.h}px;clip-path:#{facet.clip};transform:#{facet.matrix};"}
                  title={"##{facet.id} #{Map.get(@terrain_map, facet.id, :ocean)}"}
                >
                </div>
              </div>
              <div class="globe3d globe3d-coarse" style="display:none;">
                <div
                  :for={facet <- @coarse_facets}
                  class={["hex-cell3d", terrain_class(Map.get(@coarse_terrain, facet.id, :ocean))]}
                  phx-click="select_tile"
                  phx-value-id={facet.id}
                  phx-value-lod="coarse"
                  style={"width:#{facet.w}px;height:#{facet.h}px;clip-path:#{facet.clip};transform:#{facet.matrix};"}
                >
                </div>
              </div>
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

              this.el.addEventListener("pointerdown", (e) => {
                if (e.button !== 0) return
                this.pointer = e.pointerId
                this.last = {x: e.clientX, y: e.clientY}
                this.moved = false
              })

              this.el.addEventListener("pointermove", (e) => {
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
              this.grab = () => {
                this.fine = this.el.querySelector(".globe3d-fine")
                this.coarse = this.el.querySelector(".globe3d-coarse")
                this.disc = this.el.querySelector(".globe-disc3d")
                this.coarseShown = false
              }
              this.grab()

              const d = this.el.dataset
              this.yaw = parseFloat(d.yaw) || 0
              this.pitch = parseFloat(d.pitch) || 0
              this.S = parseFloat(d.scale) || 700
              this.r0 = parseFloat(d.r0) || 700
              this.maxPitch = 1.50
              this.raf = null
              this.lastSync = 0
              this.syncTimer = null

              const measure = () => {
                const r = this.el.getBoundingClientRect()
                this.cx = r.width / 2
                this.cy = r.height / 2
                this.fit = Math.max(Math.min(r.width, r.height) / 2, 25)
                if (r.width > 0) this.pushEvent("viewport_resize", {w: Math.round(r.width), h: Math.round(r.height)})
              }
              measure()
              this.clampS = () => { this.S = Math.max(this.fit, Math.min(this.S, this.fit * 8)) }
              this.clampS()

              this.resizeTimer = null
              this.ro = new ResizeObserver(() => {
                clearTimeout(this.resizeTimer)
                this.resizeTimer = setTimeout(() => { measure(); this.clampS(); this.schedule() }, 150)
              })
              this.ro.observe(this.el)

              // LOD: full detail while the disc edge is off-screen; coarse
              // once the edge shows (the entire hemisphere would otherwise
              // hit the compositor). Hysteresis avoids flapping at the line.
              this.updateLod = () => {
                const corner = Math.hypot(this.cx, this.cy)
                const wantCoarse = this.coarseShown
                  ? this.S < corner * 1.12
                  : this.S < corner * 1.02
                if (wantCoarse !== this.coarseShown) {
                  this.coarseShown = wantCoarse
                  this.coarse.style.display = wantCoarse ? "" : "none"
                  this.fine.style.display = wantCoarse ? "none" : ""
                }
              }

              this.apply = () => {
                const cy = Math.cos(this.yaw), sy = Math.sin(this.yaw)
                const cp = Math.cos(this.pitch), sp = Math.sin(this.pitch)
                const s = this.S / this.r0
                // Columns of diag(1,-1,1)·R_view — orthographic (no perspective),
                // identical to the server projection.
                const m =
                  `matrix3d(${-sy * s},${sp * cy * s},${cp * cy * s},0,` +
                  `${cy * s},${sp * sy * s},${cp * sy * s},0,` +
                  `0,${-cp * s},${sp * s},0,` +
                  `${this.cx},${this.cy},0,1)`
                this.updateLod()
                const active = this.coarseShown ? this.coarse : this.fine
                active.style.transform = m
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

              this.sync = (force) => {
                const now = Date.now()
                if (!force && now - this.lastSync < 250) {
                  if (!this.syncTimer) {
                    this.syncTimer = setTimeout(() => { this.syncTimer = null; this.sync(true) }, 250)
                  }
                  return
                }
                if (this.syncTimer) { clearTimeout(this.syncTimer); this.syncTimer = null }
                this.lastSync = now
                this.pushEvent("view_sync", {yaw: this.yaw, pitch: this.pitch, scale: this.S})
              }

              // --- drag ---
              this.pointer = null
              this.moved = false
              this.el.addEventListener("pointerdown", (e) => {
                if (e.button !== 0) return
                this.pointer = e.pointerId
                this.last = {x: e.clientX, y: e.clientY}
                this.moved = false
              })
              this.el.addEventListener("pointermove", (e) => {
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
                if (this.pointer === null || e.pointerId !== this.pointer) return
                if (this.moved) this.sync(true)
                this.pointer = null
                this.moved = false
                this.el.classList.remove("dragging")
              }
              this.el.addEventListener("pointerup", end)
              this.el.addEventListener("pointercancel", end)

              // --- continuous wheel zoom ---
              this.el.addEventListener("wheel", (e) => {
                e.preventDefault()
                this.S *= Math.exp(-e.deltaY * 0.0015)
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

              // --- client-side selection highlight (tile DOM is ignored) ---
              this.el.addEventListener("click", (e) => {
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
              // Regenerate swaps the ignored subtree (new id) — re-grab refs
              this.grab()
              this.apply()
            },

            destroyed() {
              window.removeEventListener("keydown", this.onKey)
              if (this.ro) this.ro.disconnect()
              if (this.raf) cancelAnimationFrame(this.raf)
              if (this.syncTimer) clearTimeout(this.syncTimer)
              if (this.resizeTimer) clearTimeout(this.resizeTimer)
            }
          }
        </script>

        <%!-- Sidebar --%>
        <div class="w-72 bg-base-200 border-l border-base-300 overflow-y-auto p-4 space-y-6 flex-none">
          <%!-- World info --%>
          <div>
            <h3 class="font-bold text-sm uppercase tracking-wide opacity-60 mb-2">World Info</h3>
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
