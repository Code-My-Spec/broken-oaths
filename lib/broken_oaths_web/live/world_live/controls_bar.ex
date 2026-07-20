defmodule BrokenOathsWeb.WorldLive.ControlsBar do
  @moduledoc """
  The `/worlds/:id` map editor's top controls bar — rename, seed badge,
  Regenerate, the classic/3D mode toggle, classic-mode zoom buttons, and
  the world switcher.

  A purely presentational function component: `BrokenOathsWeb.WorldLive.Show`
  owns every assign this renders and every command it dispatches
  (`"update_name"`/`"regenerate"`/`"toggle_mode"`/`"zoom_out"`/
  `"zoom_in"`/`"switch_world"` all bubble straight to the LiveView, same
  as every other un-targeted event this view already handles) — this
  component reads no `BrokenOaths.Worlds` state of its own, mirroring
  `GameLive.BoardOverlays`'s own "no read of its own" posture.
  """

  use BrokenOathsWeb, :html

  attr :world, :map, required: true
  attr :worlds, :list, required: true
  attr :render_mode, :atom, required: true
  attr :scale, :integer, required: true

  def bar(assigns) do
    ~H"""
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
    """
  end
end
