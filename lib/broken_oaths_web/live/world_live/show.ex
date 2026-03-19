defmodule BrokenOathsWeb.WorldLive.Show do
  use BrokenOathsWeb, :live_view

  alias BrokenOaths.Worlds
  alias BrokenOaths.Worlds.Generator

  @zoom_levels [3, 5, 8, 12, 18, 25]
  @default_zoom_index 2
  @pan_step 10
  @container_w 960
  @container_h 700

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

    terrain_map = Generator.generate_terrain_map(world.seed, world.width, world.height)
    stats = Generator.terrain_stats(terrain_map)

    socket =
      socket
      |> assign(
        world: world,
        worlds: worlds,
        terrain_map: terrain_map,
        stats: stats,
        viewport: %{x: 0, y: 0},
        zoom_index: @default_zoom_index,
        hex_size: Enum.at(@zoom_levels, @default_zoom_index),
        selected_hex: nil,
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

  def handle_event("select_hex", %{"q" => q, "r" => r}, socket) do
    q = String.to_integer(q)
    r = String.to_integer(r)
    terrain = Map.get(socket.assigns.terrain_map, {q, r})

    {:noreply,
     assign(socket,
       selected_hex: {q, r},
       selected_terrain: terrain
     )}
  end

  def handle_event("regenerate", _params, socket) do
    new_seed = :rand.uniform(999_999_999)

    case Worlds.update_world(socket.assigns.world, %{seed: new_seed}) do
      {:ok, world} ->
        terrain_map = Generator.generate_terrain_map(world.seed, world.width, world.height)
        stats = Generator.terrain_stats(terrain_map)
        worlds = Worlds.list_worlds()

        socket =
          socket
          |> assign(
            world: world,
            worlds: worlds,
            terrain_map: terrain_map,
            stats: stats,
            selected_hex: nil,
            selected_terrain: nil,
            viewport: %{x: 0, y: 0},
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
    new_index = min(socket.assigns.zoom_index + 1, length(@zoom_levels) - 1)

    socket =
      socket
      |> assign(zoom_index: new_index, hex_size: Enum.at(@zoom_levels, new_index))
      |> compute_view()

    {:noreply, socket}
  end

  def handle_event("zoom_out", _params, socket) do
    new_index = max(socket.assigns.zoom_index - 1, 0)

    socket =
      socket
      |> assign(zoom_index: new_index, hex_size: Enum.at(@zoom_levels, new_index))
      |> compute_view()

    {:noreply, socket}
  end

  def handle_event("pan", %{"dir" => dir}, socket) do
    do_pan(socket, dir)
  end

  def handle_event("keydown", %{"key" => key}, socket) do
    case key do
      k when k in ["ArrowLeft", "a"] -> do_pan(socket, "left")
      k when k in ["ArrowRight", "d"] -> do_pan(socket, "right")
      k when k in ["ArrowUp", "w"] -> do_pan(socket, "up")
      k when k in ["ArrowDown", "s"] -> do_pan(socket, "down")
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

  defp do_pan(socket, dir) do
    %{viewport: vp, world: w} = socket.assigns

    {dx, dy} =
      case dir do
        "left" -> {-@pan_step, 0}
        "right" -> {@pan_step, 0}
        "up" -> {0, -@pan_step}
        "down" -> {0, @pan_step}
        _ -> {0, 0}
      end

    new_x = rem(rem(vp.x + dx, w.width) + w.width, w.width)
    new_y = max(0, min(vp.y + dy, w.height - 1))

    socket =
      socket
      |> assign(viewport: %{x: new_x, y: new_y})
      |> compute_view()

    {:noreply, socket}
  end

  defp compute_view(socket) do
    %{terrain_map: tm, viewport: vp, hex_size: hs, world: w} = socket.assigns

    sqrt3 = :math.sqrt(3)
    hex_w = round(hs * 2)
    hex_h = max(round(hs * sqrt3), 1)

    cols = min(div(@container_w, max(round(hs * 1.5), 1)) + 2, w.width)
    rows = min(div(@container_h, max(round(hs * sqrt3), 1)) + 2, w.height - vp.y)
    rows = max(rows, 1)

    hexes =
      for dq <- 0..(cols - 1),
          dr <- 0..(rows - 1) do
        q = rem(vp.x + dq, w.width)
        r = vp.y + dr

        if r >= 0 and r < w.height do
          px = Float.round(hs * 1.5 * dq, 1)
          py = Float.round(hs * (sqrt3 / 2 * dq + sqrt3 * dr), 1)
          terrain = Map.get(tm, {q, r}, :ocean)
          %{q: q, r: r, x: px, y: py, terrain: terrain}
        end
      end
      |> Enum.reject(&is_nil/1)

    grid_w = round(hs * 1.5 * (cols + 1))
    grid_h = round(hs * sqrt3 * (rows + 1))

    assign(socket,
      visible_hexes: hexes,
      hex_w: hex_w,
      hex_h: hex_h,
      grid_w: grid_w,
      grid_h: grid_h
    )
  end

  defp terrain_class(terrain), do: "hex-#{terrain}"

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
          <span class="text-xs font-mono w-6 text-center">{@hex_size}</span>
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
        <%!-- Hex grid viewport --%>
        <div class="flex-1 overflow-hidden bg-base-300 relative">
          <div
            class="hex-grid-viewport"
            style={"position:relative;width:#{@grid_w}px;height:#{@grid_h}px;"}
          >
            <div
              :for={hex <- @visible_hexes}
              class={[
                "hex-cell",
                terrain_class(hex.terrain),
                @selected_hex == {hex.q, hex.r} && "hex-selected"
              ]}
              phx-click="select_hex"
              phx-value-q={hex.q}
              phx-value-r={hex.r}
              style={"left:#{hex.x}px;top:#{hex.y}px;width:#{@hex_w}px;height:#{@hex_h}px;"}
              title={"(#{hex.q}, #{hex.r}) #{hex.terrain}"}
            >
            </div>
          </div>

          <%!-- Pan controls overlay --%>
          <div class="absolute bottom-4 left-4 grid grid-cols-3 gap-0.5 opacity-60 hover:opacity-100 transition-opacity">
            <div></div>
            <button phx-click="pan" phx-value-dir="up" class="btn btn-xs btn-circle btn-ghost bg-base-100/70">
              <.icon name="hero-chevron-up" class="w-3 h-3" />
            </button>
            <div></div>
            <button phx-click="pan" phx-value-dir="left" class="btn btn-xs btn-circle btn-ghost bg-base-100/70">
              <.icon name="hero-chevron-left" class="w-3 h-3" />
            </button>
            <div></div>
            <button phx-click="pan" phx-value-dir="right" class="btn btn-xs btn-circle btn-ghost bg-base-100/70">
              <.icon name="hero-chevron-right" class="w-3 h-3" />
            </button>
            <div></div>
            <button phx-click="pan" phx-value-dir="down" class="btn btn-xs btn-circle btn-ghost bg-base-100/70">
              <.icon name="hero-chevron-down" class="w-3 h-3" />
            </button>
            <div></div>
          </div>

          <%!-- Keyboard hint --%>
          <div class="absolute bottom-4 right-4 text-xs opacity-40">
            WASD / Arrows to pan · +/− to zoom
          </div>
        </div>

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
                <dd>{@world.width} × {@world.height}</dd>
              </div>
              <div class="flex justify-between">
                <dt class="opacity-60">Viewport</dt>
                <dd>({@viewport.x}, {@viewport.y})</dd>
              </div>
              <div class="flex justify-between">
                <dt class="opacity-60">Zoom</dt>
                <dd>{@hex_size}px</dd>
              </div>
            </dl>
          </div>

          <div class="divider my-0"></div>

          <%!-- Selected hex --%>
          <div>
            <h3 class="font-bold text-sm uppercase tracking-wide opacity-60 mb-2">Selected Hex</h3>
            <div :if={@selected_hex == nil} class="text-sm opacity-40">
              Click a hex to inspect it
            </div>
            <dl :if={@selected_hex} class="text-sm space-y-1">
              <div class="flex justify-between">
                <dt class="opacity-60">Position</dt>
                <dd>({elem(@selected_hex, 0)}, {elem(@selected_hex, 1)})</dd>
              </div>
              <div class="flex items-center justify-between">
                <dt class="opacity-60">Terrain</dt>
                <dd class="flex items-center gap-1.5">
                  <span class={["inline-block w-3 h-3 rounded-sm", terrain_class(@selected_terrain)]}></span>
                  {terrain_label(@selected_terrain)}
                </dd>
              </div>
            </dl>
          </div>

          <div class="divider my-0"></div>

          <%!-- Terrain statistics --%>
          <div>
            <h3 class="font-bold text-sm uppercase tracking-wide opacity-60 mb-2">Terrain Stats</h3>
            <div class="space-y-1">
              <div :for={{terrain, _count, pct} <- @stats} class="flex items-center gap-2 text-sm">
                <span class={["inline-block w-3 h-3 rounded-sm flex-none", terrain_class(terrain)]}></span>
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
              <div :for={{_terrain, color, label} <- @terrain_legend} class="flex items-center gap-2 text-sm">
                <span class="inline-block w-4 h-3 rounded-sm flex-none" style={"background:#{color}"}></span>
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
