defmodule BrokenOathsWeb.WorldLive.Show do
  use BrokenOathsWeb, :live_view

  alias BrokenOaths.Worlds
  alias BrokenOaths.Worlds.{Generator, Globe, Projection}

  # Zoom = pixels per sphere radius. 350 fits the whole hemisphere disc
  # into the 960x700 viewport; higher values zoom into the surface.
  @zoom_scales [350, 500, 700, 1000, 1400, 2000]
  @default_zoom_index 2
  @container_w 960
  @container_h 700

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
          |> compute_view()

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
    new_index = min(socket.assigns.zoom_index + 1, length(@zoom_scales) - 1)

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
    %{pitch: pitch} = socket.assigns
    scale = Enum.at(@zoom_scales, socket.assigns.zoom_index)

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

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp do_rotate(socket, dir) do
    scale = Enum.at(@zoom_scales, socket.assigns.zoom_index)

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

  defp compute_view(socket) do
    %{mesh: mesh, terrain_map: tm, yaw: yaw, pitch: pitch, zoom_index: zi} = socket.assigns
    scale = Enum.at(@zoom_scales, zi)

    view = %{
      yaw: yaw,
      pitch: pitch,
      scale: scale,
      cx: @container_w / 2,
      cy: @container_h / 2,
      w: @container_w,
      h: @container_h
    }

    assign(socket,
      visible_tiles: Projection.visible_tiles(mesh, tm, view),
      scale: scale,
      container_w: @container_w,
      container_h: @container_h
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

        <div class="flex items-center gap-1">
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
            id="globe-viewport"
            class="globe-viewport"
            phx-hook=".GlobeDrag"
            style={"position:relative;width:#{@container_w}px;height:#{@container_h}px;"}
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

          <%!-- Rotate controls overlay --%>
          <div class="absolute bottom-4 left-4 grid grid-cols-3 gap-0.5 opacity-60 hover:opacity-100 transition-opacity">
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
            Drag or WASD / Arrows to rotate · +/− to zoom
          </div>
        </div>

        <%!-- Input-only drag hook: converts pointer drags into throttled
             drag_rotate events. All rendering stays server-side. --%>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".GlobeDrag">
          export default {
            mounted() {
              this.pending = {dx: 0, dy: 0}
              this.lastSent = 0
              this.timer = null
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
