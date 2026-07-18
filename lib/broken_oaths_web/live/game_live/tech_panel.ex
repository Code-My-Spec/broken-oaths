defmodule BrokenOathsWeb.GameLive.TechPanel do
  @moduledoc """
  The Stone Age tech tree (story 902): an always-visible `tech-tree-
  button` that toggles a panel listing all four `BrokenOaths.Game.
  Research.techs/0` — cost, unlock description, and (once earned) a
  completed marker — plus the player's current science income and, for
  whichever tech is `current_research`, a progress bar.

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

  The catalog itself (cost, unlock prose) is read straight from
  `BrokenOaths.Game.Research` — a pure, dependency-free core module,
  exactly the same "one source of truth for what's offered" status
  `GameLive.CityPanel` already gives `BrokenOaths.Game.Production`.

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
  immediately on click, no confirm step.
  """

  use BrokenOathsWeb, :live_component

  alias BrokenOaths.Game.Research

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :techs, Research.techs())

    ~H"""
    <div id={@id} class="relative">
      <button
        type="button"
        data-test="tech-tree-button"
        phx-click="toggle_tech_panel"
        class="btn btn-sm btn-outline gap-1"
      >
        <.icon name="hero-academic-cap" class="w-4 h-4" /> Tech
      </button>

      <div
        :if={@open?}
        data-test="tech-panel"
        class="card bg-base-200 shadow-xl w-80 absolute top-full left-0 mt-1 z-10"
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
    completed? = assigns.tech in assigns.player_research.completed_techs

    assigns =
      assign(assigns,
        completed?: completed?,
        cost: Research.cost(assigns.tech),
        unlock: Research.unlock_description(assigns.tech)
      )

    ~H"""
    <div class="flex flex-col gap-0.5 border-b border-base-300 pb-1 last:border-b-0 last:pb-0">
      <button
        type="button"
        data-test={"tech-#{@tech}"}
        data-disabled={to_string(@completed?)}
        disabled={@completed?}
        phx-click="select_research"
        phx-value-tech={@tech}
        class="btn btn-sm btn-outline justify-between w-full"
      >
        <span>{tech_label(@tech)}</span>
        <span data-test={"tech-cost-#{@tech}"}>{@cost}</span>
      </button>
      <p class="text-xs opacity-70" data-test={"tech-unlock-#{@tech}"}>{@unlock}</p>
      <p :if={@completed?} class="text-xs text-success" data-test={"tech-completed-#{@tech}"}>
        Completed
      </p>
    </div>
    """
  end

  attr :progress, :map, required: true

  defp research_progress(assigns) do
    ~H"""
    <div class="flex flex-col gap-1">
      <div data-test="research-progress" class="text-sm font-medium">
        {tech_label(@progress.tech)} {@progress.banked}/{@progress.cost}
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

  defp tech_label(:animal_husbandry), do: "Animal Husbandry"
  defp tech_label(:pottery), do: "Pottery"
  defp tech_label(:mining), do: "Mining"
  defp tech_label(:bronze_working), do: "Bronze Working"
end
