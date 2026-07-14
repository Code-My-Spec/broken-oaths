defmodule BrokenOathsWeb.GameLive.Play do
  @moduledoc """
  The board — a fog-filtered globe for one player's civilization.

  Route: `/play/:id` (a `BrokenOaths.Worlds.World` id). Renders once the
  player has already joined that world (see `GameLive.Join`); a player
  with no claimed region is bounced back to the picker.

  This LiveView holds only a projection of `BrokenOaths.Game`'s live
  state: it subscribes to the world's PubSub topic, sends commands
  (`select_unit`, `queue_move`, `abandon_world`), and re-pushes the
  fog-filtered board on every diff. Per the board doctrine, there is no
  tile DOM — geometry, visibility and units travel as pushed client
  events and the canvas hook owns painting:

    * `game:window`     — `%{tiles: [[id, color, decor, cx, cy, cz, cx1, cy1, cz1, ...], ...]}`,
                           fog-filtered to only known (visible ∪ explored) tiles;
                           `decor` names a billboard sprite (or nil) per the
                           art-pipeline ADR
    * `game:visibility` — `%{visible: [tile_id], explored: [tile_id]}`
    * `game:units`      — `%{units: [unit]}`, fog-filtered (own units always
                           included; another player's unit only while visible)
    * `game:selected`   — `%{unit_id: id | nil}`, echoes the current selection
    * `game:path`       — `%{unit_id: id, tiles: [tile_id]}`, the selected
                           unit's remaining order path — pushed on queue, on
                           selection, and on every board refresh (empty when
                           the unit has no order)
    * `globe3d:airspace`— `%{levels: %{tile_id => 1..3}, arc: float}` (reused
                           weather layer from `BrokenOaths.Worlds.Weather`)

  Turn number, countdown, and the selected-unit's details are each their
  own `liveview_component` (`GameLive.TurnBar`, `GameLive.UnitPanel|`)
  mounted here as children — this view stays scoped to board state.

  ## `BrokenOaths.Game` surface this view depends on

  Beyond the sanctioned reads already exposed to specs
  (`claimed_region/2`, `player_units/2`, `advance_turn/1`,
  `restart_world_server/1` — see `BrokenOathsSpex.Fixtures`), the live
  board needs:

    * `subscribe(world)` — subscribe the caller to the world's topic;
      broadcasts `{:turn_advanced, turn}` after every boundary
    * `turn_number(world)` — current turn count
    * `turn_ends_at(world)` — `DateTime` the next boundary fires, for
      `GameLive.TurnBar`'s countdown
    * `gold(world, user)` — the player's current gold
    * `visibility(world, user)` — `%{visible: [tile_id], explored: [tile_id]}`
    * `units_visible_to(world, user)` — fog-filtered unit list; each unit
      exposes at least `id`, `type`, `tile_id`, `hp`, `max_hp`, `movement`,
      `max_movement`, and `order` (`nil` or `%{target_tile:, status:, path:}`,
      status `:pending | :interrupted`, path the remaining route) — shape
      expected by `GameLive.UnitPanel` and the board's path rendering
    * `queue_move(world, user, unit_id, to_tile)` —
      `{:ok, %{path: [tile_id]}} | {:error, reason}`
    * `abandon_world(world, user)` — wipes the player's units and frees
      their region
  """

  use BrokenOathsWeb, :live_view

  alias BrokenOaths.Game
  alias BrokenOaths.Worlds
  alias BrokenOaths.Worlds.{Generator, Globe, Terrain, Weather}

  @default_scale 700
  @max_pitch 1.50

  # -------------------------------------------------------------------
  # Mount
  # -------------------------------------------------------------------

  def mount(%{"id" => id}, _session, socket) do
    world = Worlds.get_world!(id)
    user = socket.assigns.current_scope.user

    case Game.claimed_region(world, user) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/play")}

      _region ->
        if connected?(socket), do: Game.subscribe(world)

        mesh = Globe.get(world.frequency)
        %{terrain: terrain_map} = Generator.generate_maps(world.seed, mesh)
        units = Game.units_visible_to(world, user)
        {yaw, pitch} = camera_on(units, mesh)

        socket =
          socket
          |> assign(
            world: world,
            user: user,
            mesh: mesh,
            terrain_map: terrain_map,
            turn: Game.turn_number(world),
            turn_ends_at: Game.turn_ends_at(world),
            gold: Game.gold(world, user),
            units: [],
            visible: [],
            explored: [],
            selected_unit_id: nil,
            selected_unit: nil,
            selected_order: nil,
            order_error: nil,
            confirm_abandon?: false,
            yaw: yaw,
            pitch: pitch,
            scale: @default_scale,
            page_title: world.name
          )
          |> refresh_board()

        {:ok, socket}
    end
  end

  # -------------------------------------------------------------------
  # Events
  # -------------------------------------------------------------------

  def handle_event("select_unit", %{"unit_id" => unit_id}, socket) do
    unit = Enum.find(socket.assigns.units, &(&1.id == unit_id))

    socket =
      socket
      |> assign(
        selected_unit_id: unit_id,
        selected_unit: unit,
        selected_order: unit && unit.order,
        order_error: nil
      )
      |> push_event("game:selected", %{unit_id: unit_id})
      |> push_selected_path()

    {:noreply, socket}
  end

  # Right-clicks arrive as the clicked point on the unit sphere, not a
  # tile id: the client's tile window is fog-filtered, so it cannot name
  # a tile it has never seen. The server resolves which tile the player
  # aimed at — orders into and through the fog of war are legal, and no
  # hidden tile data ever travels to the client to make them so.
  def handle_event("queue_move", %{"unit_id" => unit_id, "to_point" => [x, y, z]}, socket)
      when is_number(x) and is_number(y) and is_number(z) do
    to_tile = nearest_tile(socket.assigns.mesh, {x, y, z})
    handle_event("queue_move", %{"unit_id" => unit_id, "to_tile" => to_tile}, socket)
  end

  def handle_event("queue_move", %{"unit_id" => unit_id, "to_tile" => to_tile}, socket) do
    %{world: world, user: user} = socket.assigns

    case Game.queue_move(world, user, unit_id, to_tile) do
      {:ok, %{path: path}} ->
        socket =
          socket
          |> assign(order_error: nil)
          |> push_event("game:path", %{unit_id: unit_id, tiles: path})

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, order_error: order_error_message(reason))}
    end
  end

  def handle_event("abandon_world", _params, socket) do
    {:noreply, assign(socket, confirm_abandon?: true)}
  end

  def handle_event("abandon_cancel", _params, socket) do
    {:noreply, assign(socket, confirm_abandon?: false)}
  end

  def handle_event("abandon_confirm", _params, socket) do
    %{world: world, user: user} = socket.assigns
    :ok = Game.abandon_world(world, user)
    {:noreply, push_navigate(socket, to: ~p"/play")}
  end

  # -------------------------------------------------------------------
  # Live updates
  # -------------------------------------------------------------------

  # WorldServer broadcasts this after every boundary — connected players
  # see the new turn and any resolved moves with no refresh (story 874).
  def handle_info({:turn_advanced, turn}, socket) do
    %{world: world, user: user} = socket.assigns

    socket =
      socket
      |> assign(
        turn: turn,
        turn_ends_at: Game.turn_ends_at(world),
        gold: Game.gold(world, user)
      )
      |> refresh_board()

    {:noreply, socket}
  end

  # Any board mutation (a queued order executing immediately, a join, an
  # abandon) broadcasts :units_changed — every connected view re-pulls
  # the fog-filtered board so units move live, mid-turn.
  def handle_info(:units_changed, socket) do
    {:noreply, refresh_board(socket)}
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  # Camera aimed at the centroid of the player's own units at spawn
  # (criterion: returning player resumes with the camera on their
  # civilization). Never recomputed after mount — later refreshes must
  # not yank the view out from under the player.
  defp camera_on([], _mesh), do: {0.0, 0.0}

  defp camera_on(units, mesh) do
    {sx, sy, sz} =
      units
      |> Enum.map(fn unit -> Globe.tile(mesh, unit.tile_id).center end)
      |> Enum.reduce({0.0, 0.0, 0.0}, fn {x, y, z}, {ax, ay, az} -> {ax + x, ay + y, az + z} end)

    case :math.sqrt(sx * sx + sy * sy + sz * sz) do
      norm when norm > 0.0 ->
        {:math.atan2(sy / norm, sx / norm), :math.asin(clamp(sz / norm))}

      _ ->
        {0.0, 0.0}
    end
  end

  defp clamp(z), do: max(-1.0, min(1.0, z))

  # Single source of truth for "what does this player currently know":
  # re-fetches fog-filtered units + visibility and pushes the whole
  # board state down. Called at mount and on every turn boundary.
  defp refresh_board(socket) do
    %{world: world, user: user, selected_unit_id: selected_unit_id} = socket.assigns

    units = Game.units_visible_to(world, user)
    %{visible: visible, explored: explored} = Game.visibility(world, user)
    selected_unit = selected_unit_id && Enum.find(units, &(&1.id == selected_unit_id))

    socket
    |> assign(
      units: units,
      visible: visible,
      explored: explored,
      selected_unit: selected_unit,
      selected_order: selected_unit && selected_unit.order
    )
    |> push_board_state()
    |> push_selected_path()
  end

  # A queued order's remaining route renders whenever its unit is
  # selected — re-pushed on every refresh so the line shrinks as
  # movement consumes steps and disappears on arrival (story 875 rule).
  defp push_selected_path(socket) do
    case socket.assigns.selected_unit do
      nil ->
        socket

      unit ->
        tiles = (unit.order && unit.order.path) || []
        push_event(socket, "game:path", %{unit_id: unit.id, tiles: tiles})
    end
  end

  defp push_board_state(socket) do
    %{mesh: mesh, terrain_map: terrain_map, world: world} = socket.assigns
    %{units: units, visible: visible, explored: explored} = socket.assigns

    known = Enum.uniq(visible ++ explored)
    tiles = Enum.map(known, &tile_row(&1, mesh, terrain_map))
    levels = Weather.map(world.seed, mesh)

    socket
    |> push_event("game:window", %{tiles: tiles})
    |> push_event("game:visibility", %{visible: visible, explored: explored})
    |> push_event("game:units", %{units: units})
    |> push_event("globe3d:airspace", %{
      levels: levels,
      arc: Float.round(1.1071 / mesh.frequency, 5)
    })
  end

  # Compact row for the client painter:
  # [id, color, decor, cx, cy, cz, corner1x, corner1y, corner1z, ...]
  defp tile_row(tile_id, mesh, terrain_map) do
    tile = Globe.tile(mesh, tile_id)
    terrain = Map.get(terrain_map, tile_id)
    {cx, cy, cz} = tile.center
    corners = Enum.flat_map(tile.corners, fn {x, y, z} -> [round4(x), round4(y), round4(z)] end)

    [
      tile.id,
      Terrain.color(terrain),
      decor(terrain),
      round4(cx),
      round4(cy),
      round4(cz) | corners
    ]
  end

  # Which billboard sprite (if any) a tile's relief/feature earns — the
  # client learns decor from this push, never by re-deriving terrain
  # (ADR game-art-pipeline). Mountains dominate features; hills yield
  # to tree cover.
  defp decor(nil), do: nil
  defp decor(%{relief: :mountains}), do: "mountain"
  defp decor(%{feature: :woods}), do: "woods"
  defp decor(%{feature: :rainforest}), do: "rainforest"
  defp decor(%{relief: :hills}), do: "hills"
  defp decor(_terrain), do: nil

  defp round4(f), do: Float.round(f, 4)

  # The mesh tile whose center is nearest the given unit-sphere point
  # (max dot product). Linear over the mesh — ~29k tiles at f=54, a few
  # ms once per right-click.
  defp nearest_tile(mesh, {x, y, z}) do
    {id, _tile} =
      Enum.max_by(mesh.tiles, fn {_id, tile} ->
        {cx, cy, cz} = tile.center
        cx * x + cy * y + cz * z
      end)

    id
  end

  defp order_error_message(:not_owner), do: "You don't control that unit."
  defp order_error_message(:occupied), do: "Another unit already holds that tile."
  defp order_error_message(:impassable), do: "That terrain can't be crossed."
  defp order_error_message(:unreachable), do: "There's no path there."
  defp order_error_message(_other), do: "That order can't be queued."

  # -------------------------------------------------------------------
  # Render
  # -------------------------------------------------------------------

  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-[calc(100vh-64px)]">
      <div class="flex items-center gap-3 px-4 py-2 bg-base-200 border-b border-base-300 flex-wrap">
        <.live_component
          module={BrokenOathsWeb.GameLive.TurnBar}
          id="turn-bar"
          turn={@turn}
          turn_ends_at={@turn_ends_at}
        />

        <span class="badge badge-neutral gap-1" data-test="player-gold">
          <.icon name="hero-circle-stack" class="w-3 h-3" /> {@gold}
        </span>

        <div class="flex-1"></div>

        <button
          phx-click="abandon_world"
          class="btn btn-sm btn-error btn-outline"
          data-test="abandon-world"
        >
          Abandon World
        </button>

        <.link navigate={~p"/play"} class="btn btn-sm btn-ghost">All Worlds</.link>
      </div>

      <div :if={@confirm_abandon?} class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Abandon this world?</h3>
          <p class="py-4 opacity-70">
            Your civilization will be wiped and your region freed for another player. This cannot be undone.
          </p>
          <div class="modal-action">
            <button phx-click="abandon_cancel" class="btn btn-ghost">Cancel</button>
            <button phx-click="abandon_confirm" class="btn btn-error" data-test="abandon-confirm">
              Abandon Forever
            </button>
          </div>
        </div>
      </div>

      <div class="flex flex-1 min-h-0 relative">
        <div
          id="board-viewport"
          class="flex-1 overflow-hidden space-bg relative"
          phx-hook=".Board"
          data-yaw={@yaw}
          data-pitch={@pitch}
          data-scale={@scale}
        >
          <div id="board-own" phx-update="ignore" class="board-own">
            <canvas class="board-canvas" style="width:100%;height:100%;"></canvas>
          </div>

          <div class="fog-layer pointer-events-none absolute inset-0" data-test="fog-layer"></div>
          <div class="weather-layer pointer-events-none absolute inset-0" data-test="weather-layer">
          </div>
        </div>

        <div
          :if={@order_error}
          class="alert alert-error absolute top-4 left-4 w-auto shadow-lg"
          data-test="order-error"
        >
          <.icon name="hero-exclamation-triangle" class="w-4 h-4" /> {@order_error}
        </div>

        <.live_component
          :if={@selected_unit}
          module={BrokenOathsWeb.GameLive.UnitPanel}
          id="unit-panel"
          unit={@selected_unit}
          order={@selected_order}
        />
      </div>

      <%!-- Canvas-only board: no tile DOM. Camera (drag rotate + wheel zoom)
           lives entirely client-side since fog is unit-position-derived, not
           camera-derived — the server never needs to know the current view.
           A left click on a unit selects it; a right click queues a move
           toward the clicked point on the sphere — resolved to a tile
           server-side, so targets under the fog of war work too. --%>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Board">
        export default {
          mounted() {
            this.canvas = this.el.querySelector(".board-canvas")
            this.ctx = this.canvas.getContext("2d")

            const d = this.el.dataset
            this.yaw = parseFloat(d.yaw) || 0
            this.pitch = parseFloat(d.pitch) || 0
            this.scale = parseFloat(d.scale) || 700
            this.maxPitch = 1.50

            this.tiles = []
            this.tileById = new Map()
            this.units = []
            this.visibleSet = new Set()
            this.selectedId = null
            this.path = null
            this.anims = new Map()
            this.raf = null
            this.arc = 0.02

            // Billboard sprites (ADR game-art-pipeline). Anything not yet
            // loaded falls back to the original programmer art.
            this.sprites = {}
            for (const [key, path] of Object.entries({
              lord: "/images/game/units/lord.png",
              settler: "/images/game/units/settler.png",
              mountain: "/images/game/decor/mountain.png",
              hills: "/images/game/decor/hills.png",
              woods: "/images/game/decor/woods.png",
              rainforest: "/images/game/decor/rainforest.png",
            })) {
              const img = new Image()
              img.onload = () => this.draw()
              img.src = path
              this.sprites[key] = img
            }

            const measure = () => {
              const r = this.el.getBoundingClientRect()
              this.cx = r.width / 2
              this.cy = r.height / 2
              const dpr = Math.min(window.devicePixelRatio || 1, 2)
              this.canvas.width = Math.max(Math.round(r.width * dpr), 1)
              this.canvas.height = Math.max(Math.round(r.height * dpr), 1)
              this.dpr = dpr
              this.draw()
            }
            measure()
            this.ro = new ResizeObserver(measure)
            this.ro.observe(this.el)

            this.airspace = {}
            this.handleEvent("globe3d:airspace", ({levels, arc}) => {
              this.airspace = levels
              if (arc) this.arc = arc
              this.draw()
            })
            this.handleEvent("game:window", ({tiles}) => {
              this.tiles = tiles
              this.tileById = new Map(tiles.map((row) => [row[0], row]))
              this.draw()
            })
            this.handleEvent("game:visibility", ({visible}) => { this.visibleSet = new Set(visible); this.draw() })
            this.handleEvent("game:units", ({units}) => {
              // A unit whose tile changed slides there instead of teleporting.
              const prev = new Map(this.units.map((u) => [u.id, u.tile_id]))
              const now = performance.now()
              for (const u of units) {
                const was = prev.get(u.id)
                if (was != null && was !== u.tile_id) {
                  const from = this.unitPos({id: u.id, tile_id: was}, now)
                  const to = this.center(u.tile_id)
                  if (from && to) this.anims.set(u.id, {from, to, start: now})
                }
              }
              this.units = units
              this.ensureLoop()
              this.draw()
            })
            this.handleEvent("game:selected", ({unit_id}) => { this.selectedId = unit_id; this.path = null; this.draw() })
            this.handleEvent("game:path", ({unit_id, tiles}) => {
              if (unit_id === this.selectedId) this.path = tiles
              this.draw()
            })

            this.dragging = false
            this.moved = false

            this.el.addEventListener("pointerdown", (e) => {
              this.dragging = true
              this.moved = false
              this.button = e.button
              this.last = {x: e.clientX, y: e.clientY}
              this.el.setPointerCapture(e.pointerId)
            })

            // Right-click is a game action (queue move), not a menu
            this.el.addEventListener("contextmenu", (e) => e.preventDefault())

            this.el.addEventListener("pointermove", (e) => {
              if (!this.dragging) return
              const dx = e.clientX - this.last.x
              const dy = e.clientY - this.last.y
              if (!this.moved && Math.abs(dx) + Math.abs(dy) < 4) return
              this.moved = true
              this.last = {x: e.clientX, y: e.clientY}
              this.yaw -= dx / this.scale / Math.max(Math.cos(this.pitch), 0.25)
              this.pitch = Math.max(-this.maxPitch, Math.min(this.maxPitch, this.pitch + dy / this.scale))
              this.draw()
            })

            this.el.addEventListener("pointerup", (e) => {
              this.dragging = false
              if (this.moved) return
              if (this.button === 2) this.orderMove(e)
              else this.click(e)
            })

            this.el.addEventListener("wheel", (e) => {
              e.preventDefault()
              this.scale = Math.max(200, Math.min(this.scale * (e.deltaY < 0 ? 1.1 : 0.9), 4000))
              this.draw()
            }, {passive: false})
          },

          unproject(sx, sy) {
            const vx = (sx - this.cx) / this.scale
            const vy = (this.cy - sy) / this.scale
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
          },

          project(x, y, z) {
            const cyw = Math.cos(this.yaw), syw = Math.sin(this.yaw)
            const cp = Math.cos(this.pitch), sp = Math.sin(this.pitch)
            const depth = cp * cyw * x + cp * syw * y + sp * z
            const px = this.cx + this.scale * (-syw * x + cyw * y)
            const py = this.cy - this.scale * (-sp * cyw * x - sp * syw * y + cp * z)
            return {px, py, depth}
          },

          // Nearest tile to a screen point, by exact tile geometry —
          // correct at any zoom (no fuzzy capture radius).
          hitTile(e) {
            const r = this.el.getBoundingClientRect()
            const p = this.unproject(e.clientX - r.left, e.clientY - r.top)
            if (!p || this.tiles.length === 0) return null

            let nearestTile = null, bestTileDot = -Infinity
            for (const row of this.tiles) {
              const dot = row[3] * p.x + row[4] * p.y + row[5] * p.z
              if (dot > bestTileDot) { bestTileDot = dot; nearestTile = row[0] }
            }

            return nearestTile
          },

          // Left click: select the unit standing on the clicked tile
          // (or clear the selection when the tile is empty).
          click(e) {
            const tile = this.hitTile(e)
            if (tile == null) return

            const unit = this.units.find((u) => u.tile_id === tile)
            if (unit) this.pushEvent("select_unit", {unit_id: unit.id})
          },

          // Right click: queue the selected unit's move toward the clicked
          // point on the globe. The point (not a tile id) goes up because
          // the client's tile window is fog-filtered — the server resolves
          // which tile was aimed at, so orders into the shroud work.
          orderMove(e) {
            if (this.selectedId == null) return
            const r = this.el.getBoundingClientRect()
            const p = this.unproject(e.clientX - r.left, e.clientY - r.top)
            if (!p) return

            this.pushEvent("queue_move", {unit_id: this.selectedId, to_point: [p.x, p.y, p.z]})
          },

          center(tileId) {
            const row = this.tileById.get(tileId)
            return row ? [row[3], row[4], row[5]] : null
          },

          spriteFor(key) {
            const img = key && this.sprites[key]
            return img && img.complete && img.naturalWidth ? img : null
          },

          // Where a unit currently renders: mid-slide if animating,
          // otherwise its tile center.
          unitPos(u, now) {
            const a = this.anims.get(u.id)
            if (!a) return this.center(u.tile_id)
            const t = Math.min(1, (now - a.start) / 450)
            const ease = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2
            return this.slerp(a.from, a.to, ease)
          },

          slerp(a, b, t) {
            let dot = a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
            dot = Math.min(1, Math.max(-1, dot))
            const th = Math.acos(dot)
            if (th < 1e-4) return b
            const s = Math.sin(th)
            const wa = Math.sin((1 - t) * th) / s
            const wb = Math.sin(t * th) / s
            return [a[0] * wa + b[0] * wb, a[1] * wa + b[1] * wb, a[2] * wa + b[2] * wb]
          },

          // Animation loop — runs only while a slide is in flight or a
          // unit with a pending path needs its pulse.
          ensureLoop() {
            if (this.raf) return
            const step = () => {
              this.raf = null
              const now = performance.now()
              for (const [id, a] of this.anims) {
                if (now - a.start > 450) this.anims.delete(id)
              }
              this.draw()
              const pulsing = this.units.some((u) => u.order && u.order.status === "pending")
              if (this.anims.size || pulsing) this.raf = requestAnimationFrame(step)
            }
            this.raf = requestAnimationFrame(step)
          },

          draw() {
            const ctx = this.ctx
            if (!ctx) return
            const dpr = this.dpr || 1
            ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
            ctx.clearRect(0, 0, this.canvas.width, this.canvas.height)

            // Fog of war: the unexplored planet is a flat, opaque,
            // colorless cloud shroud — the "cloud-wrapped" globe. Known
            // tiles paint over it; everything else stays under cloud.
            ctx.beginPath()
            ctx.arc(this.cx, this.cy, this.scale, 0, 2 * Math.PI)
            ctx.fillStyle = "#a8acb5"
            ctx.fill()

            const order = this.tiles
              .map((row) => ({row, depth: this.project(row[3], row[4], row[5]).depth}))
              .filter(({depth}) => depth > 0.02)
              .sort((a, b) => a.depth - b.depth)

            for (const {row} of order) {
              const [id, color] = row
              ctx.beginPath()
              for (let i = 6; i < row.length; i += 3) {
                const {px, py} = this.project(row[i], row[i + 1], row[i + 2])
                if (i === 6) ctx.moveTo(px, py); else ctx.lineTo(px, py)
              }
              ctx.closePath()
              ctx.fillStyle = color
              ctx.fill()

              // Explored-but-out-of-vision: remembered terrain under a
              // thin wash of the fog tone (distinct from full shroud)
              if (!this.visibleSet.has(id)) {
                ctx.fillStyle = "rgba(168,172,181,0.45)"
                ctx.fill()
              }
            }

            // Terrain decor billboards (mountains, hills, tree cover) at
            // projected tile centers, back-to-front, dimmed on remembered
            // tiles. Skipped entirely below readability size.
            ctx.imageSmoothingEnabled = false
            const decorSize = Math.min(Math.max(this.scale * this.arc * 1.7, 10), 72)
            if (decorSize >= 10) {
              for (const {row} of order) {
                const img = this.spriteFor(row[2])
                if (!img) continue
                const {px, py} = this.project(row[3], row[4], row[5])
                ctx.globalAlpha = this.visibleSet.has(row[0]) ? 1 : 0.55
                ctx.drawImage(img, px - decorSize / 2, py - decorSize * 0.62, decorSize, decorSize)
              }
              ctx.globalAlpha = 1
            }

            // Weather: translucent cloud hexes one shell above known
            // terrain (levels from the airspace push; palette mirrors
            // Worlds.Weather). Deliberately translucent + tinted so it
            // never reads as the flat opaque fog shroud.
            const CLOUD = {1: "rgba(250,251,253,0.38)", 2: "rgba(240,244,249,0.62)", 3: "rgba(104,110,124,0.8)"}
            for (const {row} of order) {
              const lvl = this.airspace[row[0]]
              if (!lvl) continue
              ctx.beginPath()
              for (let i = 6; i < row.length; i += 3) {
                const {px, py} = this.project(row[i] * 1.035, row[i + 1] * 1.035, row[i + 2] * 1.035)
                if (i === 6) ctx.moveTo(px, py); else ctx.lineTo(px, py)
              }
              ctx.closePath()
              ctx.fillStyle = CLOUD[lvl]
              ctx.fill()
            }

            const now = performance.now()
            const unitSize = Math.min(Math.max(this.scale * this.arc * 1.5, 14), 64)
            for (const u of this.units) {
              const pos = this.unitPos(u, now)
              if (!pos) continue
              const {px, py, depth} = this.project(pos[0], pos[1], pos[2])
              if (depth < 0.02) continue
              const color = u.type === "lord" ? "#f5c542" : "#42a5f5"
              const img = this.spriteFor(u.type)
              const ringR = img ? unitSize * 0.45 : 8

              // A unit with a pending path pulses — the "I'm on the move"
              // signal, visible without selecting it.
              if (u.order && u.order.status === "pending") {
                const ph = (now % 1200) / 1200
                ctx.beginPath()
                ctx.arc(px, py, ringR + ph * 8, 0, 2 * Math.PI)
                ctx.strokeStyle = color
                ctx.globalAlpha = 0.7 * (1 - ph)
                ctx.lineWidth = 2
                ctx.stroke()
                ctx.globalAlpha = 1
              }

              if (img) {
                // Ground ellipse marks selection under the sprite's feet.
                if (u.id === this.selectedId) {
                  ctx.beginPath()
                  ctx.ellipse(px, py + unitSize * 0.28, unitSize * 0.4, unitSize * 0.16, 0, 0, 2 * Math.PI)
                  ctx.strokeStyle = "#ffffff"
                  ctx.lineWidth = 2
                  ctx.stroke()
                }
                ctx.drawImage(img, px - unitSize / 2, py - unitSize * 0.68, unitSize, unitSize)
              } else {
                // Fallback programmer art — the board never depends on an
                // asset request to be playable (ADR game-art-pipeline).
                ctx.beginPath()
                ctx.arc(px, py, u.id === this.selectedId ? 7 : 5, 0, 2 * Math.PI)
                ctx.fillStyle = color
                ctx.fill()
                ctx.lineWidth = 1.5
                ctx.strokeStyle = "#1a1a1a"
                ctx.stroke()
              }
            }

            if (this.path && this.path.length) {
              ctx.beginPath()
              // Path steps under fog have no client geometry — the line
              // simply bridges between the tiles the player knows.
              this.path.forEach((tileId) => {
                const c = this.center(tileId)
                if (!c) return
                const {px, py} = this.project(c[0], c[1], c[2])
                ctx.lineTo(px, py)
              })
              ctx.strokeStyle = "#ffffff"
              ctx.lineWidth = 2
              ctx.setLineDash([4, 4])
              ctx.stroke()
              ctx.setLineDash([])
            }
          },

          destroyed() {
            if (this.ro) this.ro.disconnect()
            if (this.raf) cancelAnimationFrame(this.raf)
          }
        }
      </script>

      <.live_component
        module={BrokenOathsWeb.FeedbackWidget}
        id="codemyspec-feedback"
        current_scope={@current_scope}
      />
    </div>
    """
  end
end
