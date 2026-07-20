defmodule BrokenOathsWeb.WorldLive.Sidebar do
  @moduledoc """
  The `/worlds/:id` map editor's collapsible info panel — the
  collapsed-sidebar opener button plus the World Info / Selected Tile /
  Terrain Stats sections, mounted by `BrokenOathsWeb.WorldLive.Show` as
  a sibling of the globe viewport.

  A purely presentational function component: `Show` owns
  `sidebar_open`/`selected_tile`/`selected_terrain`/`stats` and
  dispatches `"toggle_sidebar"` itself (un-targeted, same as every other
  event this view handles) — this component reads no `BrokenOaths.Worlds`
  state of its own, mirroring `GameLive.BoardOverlays`'s own "no read of
  its own" posture. Formatting (`deg/1`, `format_latlon/1`) is shared
  with `Show`'s own `"toggle_mode"` URL-building via
  `BrokenOathsWeb.WorldLive.ShowView` rather than duplicated here.
  """

  use BrokenOathsWeb, :html

  alias BrokenOaths.Worlds.{Globe, Terrain}
  alias BrokenOathsWeb.WorldLive.ShowView

  attr :sidebar_open, :boolean, required: true
  attr :world, :map, required: true
  attr :yaw, :float, required: true
  attr :pitch, :float, required: true
  attr :scale, :integer, required: true
  attr :selected_tile, :any, required: true
  attr :selected_terrain, :any, required: true
  attr :stats, :list, required: true

  def panel(assigns) do
    ~H"""
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
            <dd>{ShowView.deg(@yaw)}° / {ShowView.deg(@pitch)}°</dd>
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
            <dd>{ShowView.format_latlon(@selected_tile.center)}</dd>
          </div>
          <div class="flex items-center justify-between">
            <dt class="opacity-60">Terrain</dt>
            <dd class="flex items-center gap-1.5">
              <span
                class="inline-block w-3 h-3 rounded-sm"
                style={"background:#{Terrain.color(@selected_terrain)}"}
              >
              </span>
              {Terrain.label(@selected_terrain)}
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
            <span
              class="inline-block w-3 h-3 rounded-sm flex-none"
              style={"background:#{Terrain.color(terrain)}"}
            >
            </span>
            <span class="flex-1">{Terrain.label(terrain)}</span>
            <span class="opacity-60 font-mono text-xs">{pct}%</span>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
