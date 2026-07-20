defmodule BrokenOathsWeb.WorldLive.ViewportOverlay do
  @moduledoc """
  The globe viewport's own absolutely-positioned chrome — the classic-mode
  rotate (pan) button grid and the bottom-right control hint — mounted by
  `BrokenOathsWeb.WorldLive.Show` as a sibling of the classic/3D mode tile
  divs.

  Deliberately excludes the mode divs themselves and both `phx-hook`
  script tags: `Show`'s own moduledoc-equivalent reasoning in
  `GameLive.BoardOverlays` applies here too — `phx-hook=".Name"` is
  rewritten to `"\#{inspect(caller.module)}.Name"` at compile time, so a
  `<script :type={Phoenix.LiveView.ColocatedHook}>` body can only ever
  live in the SAME module as the element whose `phx-hook` attribute
  names it. Splitting either `.GlobeDrag`'s or `.Globe3D`'s hooked div
  out of `Show` would rename the hook and change the rendered DOM.

  A purely presentational function component: `Show` owns `render_mode`
  and dispatches every `"pan"` click itself (un-targeted, same as every
  other event this view handles); this component reads nothing on its
  own.
  """

  use BrokenOathsWeb, :html

  attr :render_mode, :atom, required: true

  def controls(assigns) do
    ~H"""
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
    """
  end
end
