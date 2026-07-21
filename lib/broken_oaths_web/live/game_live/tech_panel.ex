defmodule BrokenOathsWeb.GameLive.TechPanel do
  @moduledoc """
  The Ancient-era tech tree (story 902, EXPANDED per playtest issue
  133b4893 to the full eleven-tech, prerequisite-gated Civ-6-accurate
  tree): an always-visible `tech-tree-button` that toggles a panel
  listing all eleven `BrokenOaths.Technology.Research.techs/0` — cost,
  unlock description, prerequisite links, and each tech's `:locked |
  :available | :in_progress | :completed` state
  (`BrokenOaths.Technology.Research.tech_state/2`) — plus the player's
  current science income and, for whichever tech is `current_research`,
  a progress bar.

  A presentational component mounted unconditionally by
  `BrokenOathsWeb.GameLive.Play` (so `tech-tree-button` is always
  reachable, whether or not the panel is open — the same "always
  mounted" status `GameLive.ChatPanel` has for its own toggle button),
  which owns every bit of research state itself: this component never
  calls `BrokenOaths.Game` and defines no `handle_event/3` of its own.
  Every interactive element pushes a plain DOM event with no
  `phx-target`, so it bubbles to `Play` exactly like `GameLive.
  CityPanel`/`GameLive.UnitPanel`'s pattern — unlike `GameLive.
  ChatPanel`'s stateful, `@myself`-targeted shape. `Play` is the one
  that calls `BrokenOaths.Game.set_research/3` and re-pulls
  `BrokenOaths.Game.player_research/2` after every change (including
  the world-wide `:research_changed` broadcast and each turn boundary,
  since science accrual moves this state every tick).

  Assigns (from `Play`):

    * `:id` - the DOM id for this component instance
    * `:open?` - whether the panel itself is expanded (the button is
      always rendered regardless)
    * `:player_research` - `BrokenOaths.Game.player_research/2`'s own
      shape: `%{completed_techs:, current_research:, banked_science:,
      progress:, science_per_turn:}` — `progress` is `%{tech:, banked:,
      cost:}` for `current_research`, or `nil` with nothing selected
    * `:bronze_working_pending?` - true between clicking the
      `tech-bronze_working` row and the player resolving the
      `bronze-working-warning` confirm modal one way or the other

  The catalog itself (cost, unlock prose, prerequisites) is read
  straight from `BrokenOaths.Technology.Research` — a pure, dependency-free
  core module, exactly the same "one source of truth for what's
  offered" status `GameLive.CityPanel` already gives `BrokenOaths.Game.
  Production`.

  ## Prerequisite links + lock state (issue 133b4893)

  Each tech row renders `Research.prereqs/1` inline (`"Requires:
  <label(s)>"`, `data-test="tech-prereqs-<tech>"`) whenever it has any
  — so a locked tech always names exactly what it's waiting on, right
  on its own row, rather than leaving the player to guess. The row's
  overall state comes from a single `Research.tech_state/2` call per
  tech, rendered as one of four mutually exclusive markers:

    * `data-test="tech-completed-<tech>"` — state is `:completed`.
    * `data-test="tech-in-progress-<tech>"` — state is `:in_progress`
      (also visible via the shared `research-progress` bar below).
    * `data-test="tech-locked-<tech>"` — state is `:locked`; the row's
      button is `disabled` and visually dimmed, mirroring `CityPanel`'s
      own `disabled?`/`data-disabled` convention for an unqueueable
      production option.
    * `:available` renders no extra marker — an enabled, unlabeled row
      is the default "you can pick this" state.

  ## Mobile layering + overflow (QA issue ff4400be "Revise tech menu")

  The open panel used to be `absolute top-full left-0` inside `Play`'s
  own top status bar row — the same row that carries
  `overflow-x-auto` below `md:` so the bar itself can scroll
  horizontally instead of wrapping (see `Play`'s render/1 moduledoc
  note next to that row). Per the CSS overflow spec, setting
  `overflow-x` to anything but `visible` forces the *other* axis to
  compute to `auto` too, even if never written — so on a portrait
  phone that row silently clipped anything a child popped open below
  it. The dropdown wasn't behind the globe board so much as clipped
  away entirely by its own scrolling ancestor, which reads to a player
  as "it's rendering behind the board" since the board is exactly
  what they see where the panel should have been. A raw z-index bump
  alone can't fix that — z-index only orders paint among boxes that
  are actually visible, it doesn't rescue a box an ancestor has
  clipped.

  Below `md:` the panel now escapes that ancestor with `fixed`
  positioning (anchored to the viewport, clear of both the app navbar
  and this game's own top bar), `inset-x-3` for a bounded, full-width-
  minus-margin box instead of a fixed `w-80` that could run past a
  narrow screen's edge, `max-h-[70vh] overflow-y-auto` (the same
  bounded-scroll convention `BoardOverlays`'s own side panels already
  use) so the eleven-tech list scrolls inside the card instead of
  running off-screen, and `z-30` — above `BoardOverlays`'s own z-20
  overlay tier, so it's guaranteed to paint over the board canvas
  regardless of DOM order. `md:` and up is untouched: `md:absolute
  md:top-full md:left-0 md:w-80 md:z-10`, the same dropdown-under-the-
  button shape this panel (and `ChatPanel`/`AlliancePanel`/
  `FeudalTopBar`'s own dropdowns) already have at desktop widths,
  where the top bar never scrolls and never clips.

  ## The Bronze Working confirm flow

  Clicking `tech-bronze_working` never reaches `Game.set_research/3`
  directly — `Play`'s own `"select_research"` handler special-cases
  `"bronze_working"` into `bronze_working_pending?: true` instead,
  surfacing the `bronze-working-warning` modal this component renders
  (copy: "This will advance you to Bronze Age. Continue?", the story's
  own acceptance-criteria text) with its own `bronze-working-confirm`/
  `bronze-working-cancel` controls — the same `modal modal-open`
  pattern `Play`'s own `abandon-world` flow already uses. Confirming is
  what actually calls `Game.set_research(world, user, :bronze_working)`;
  cancelling dismisses with nothing selected. Every other tech commits
  immediately on click, no confirm step. Since Bronze Working now
  requires Mining first, `Play` only ever raises this warning once
  Bronze Working is actually researchable — see its own moduledoc note
  on `"select_research"`.
  """

  use BrokenOathsWeb, :live_component

  alias BrokenOaths.Technology.Research

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:techs, Research.techs())
      |> assign(:button_fill_pct, button_fill_pct(assigns.player_research.progress))

    ~H"""
    <div id={@id} class="relative">
      <button
        type="button"
        data-test="tech-tree-button"
        phx-click="toggle_tech_panel"
        class="btn btn-sm btn-outline gap-1 relative overflow-hidden"
      >
        <%!-- Playtest issue 2 — a compact fill (banked/cost of whatever's
             currently researching) so progress reads at a glance without
             opening the panel below; zero width with nothing selected. --%>
        <span
          data-test="tech-button-fill"
          class="absolute inset-y-0 left-0 bg-primary/30 pointer-events-none"
          style={"width: #{@button_fill_pct}%"}
        >
        </span>
        <span class="relative flex items-center gap-1">
          <.icon name="hero-academic-cap" class="w-4 h-4" /> Tech
        </span>
      </button>

      <div
        :if={@open?}
        data-test="tech-panel"
        class="card bg-base-200 shadow-xl z-30 fixed inset-x-3 top-24 max-h-[70vh] overflow-y-auto md:absolute md:inset-x-auto md:left-0 md:top-full md:mt-1 md:w-80 md:z-10"
      >
        <div class="card-body p-3 gap-2">
          <h3 class="card-title text-sm">Technology</h3>

          <div data-test="science-per-turn" class="text-xs opacity-70">
            {@player_research.science_per_turn} science/turn
          </div>

          <div class="flex flex-col gap-2">
            <.tech_row :for={tech <- @techs} tech={tech} player_research={@player_research} />
          </div>

          <.research_progress :if={@player_research.progress} progress={@player_research.progress} />
        </div>
      </div>

      <div :if={@bronze_working_pending?} class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg" data-test="bronze-working-warning">
            This will advance you to Bronze Age. Continue?
          </h3>
          <div class="modal-action">
            <button
              type="button"
              data-test="bronze-working-cancel"
              phx-click="bronze_working_cancel"
              class="btn btn-ghost"
            >
              Cancel
            </button>
            <button
              type="button"
              data-test="bronze-working-confirm"
              phx-click="bronze_working_confirm"
              class="btn btn-primary"
            >
              Continue
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :tech, :atom, required: true
  attr :player_research, :map, required: true

  defp tech_row(assigns) do
    state = Research.tech_state(assigns.player_research, assigns.tech)
    prereqs = Research.prereqs(assigns.tech)
    locked? = state == :locked
    disabled? = state in [:locked, :completed]

    assigns =
      assign(assigns,
        state: state,
        locked?: locked?,
        completed?: state == :completed,
        in_progress?: state == :in_progress,
        disabled?: disabled?,
        cost: Research.cost(assigns.tech),
        unlock: Research.unlock_description(assigns.tech),
        prereqs: prereqs
      )

    ~H"""
    <div class="flex flex-col gap-0.5 border-b border-base-300 pb-1 last:border-b-0 last:pb-0">
      <button
        type="button"
        data-test={"tech-#{@tech}"}
        data-state={@state}
        data-disabled={to_string(@disabled?)}
        disabled={@disabled?}
        phx-click="select_research"
        phx-value-tech={@tech}
        class={[
          "btn btn-sm btn-outline justify-between w-full",
          @locked? && "opacity-50"
        ]}
      >
        <span>{Research.tech_label(@tech)}</span>
        <span data-test={"tech-cost-#{@tech}"}>{@cost}</span>
      </button>
      <p :if={@prereqs != []} class="text-xs opacity-60" data-test={"tech-prereqs-#{@tech}"}>
        Requires: {Enum.map_join(@prereqs, ", ", &Research.tech_label/1)}
      </p>
      <p class="text-xs opacity-70" data-test={"tech-unlock-#{@tech}"}>{@unlock}</p>
      <p :if={@completed?} class="text-xs text-success" data-test={"tech-completed-#{@tech}"}>
        Completed
      </p>
      <p :if={@in_progress?} class="text-xs text-info" data-test={"tech-in-progress-#{@tech}"}>
        Researching
      </p>
      <p :if={@locked?} class="text-xs text-warning" data-test={"tech-locked-#{@tech}"}>
        Locked
      </p>
    </div>
    """
  end

  attr :progress, :map, required: true

  defp research_progress(assigns) do
    ~H"""
    <div class="flex flex-col gap-1">
      <div data-test="research-progress" class="text-sm font-medium">
        {Research.tech_label(@progress.tech)} {@progress.banked}/{@progress.cost}
      </div>
      <progress
        data-test="research-progress-bar"
        class="progress progress-primary w-full"
        value={@progress.banked}
        max={@progress.cost}
      >
      </progress>
    </div>
    """
  end

  # Playtest issue 2 — the Tech button's own collapsed-state preview:
  # zero with nothing selected, else banked/cost as a whole percent
  # (capped at 100 the same defensive-clamp way `ProgressPanel`'s own
  # Bronze Working row already caps an over-banked tech).
  defp button_fill_pct(nil), do: 0
  defp button_fill_pct(%{banked: banked, cost: cost}), do: div(min(banked, cost) * 100, cost)
end
