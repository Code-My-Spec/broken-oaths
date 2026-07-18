defmodule BrokenOathsWeb.GameLive.ProgressPanel do
  @moduledoc """
  The Stone Age progress panel (story 904): current age, science
  income and a projected turns-to-Bronze-Working estimate, career
  totals (cities founded, camps destroyed, barbarians killed), and
  four always-rendered first-time milestones — same "presentational,
  reads render straight off whatever `Play` hands it" status
  `GameLive.AgePanel`/`GameLive.TechPanel` already have (`stone_age.md`
  §12.1). No `handle_event/3` of its own; every figure here is derived
  from state `BrokenOaths.Game` already owns elsewhere, not tracked
  independently by this component.

  A presentational component mounted unconditionally by
  `BrokenOathsWeb.GameLive.Play`, which owns pulling every input this
  panel reads and keeps them fresh on the same signals `refresh_board/1`
  already refreshes cities/known-players on (mount, every turn
  boundary, `:units_changed`, `:cities_changed`).

  Assigns (from `Play`):

    * `:id` - the DOM id for this component instance
    * `:player_research` - `BrokenOaths.Game.player_research/2`'s own
      shape (the same one `GameLive.AgePanel`/`GameLive.TechPanel`
      already receive) — age, science/turn, and the Bronze Working
      projection are all derived from it via `BrokenOaths.Game.Research`
    * `:cities_founded` - `length(Game.player_cities(world, user))`
      (story 904, criterion 7640/7641's own moduledoc: no city is ever
      deleted in this codebase, so a player's live city count already
      IS their lifetime total — no separate counter needed)
    * `:camps_destroyed` - `BrokenOaths.Game.player_stats/2`'s own
      field, a real running total (bumped alongside the destroy-reward
      gold `Game.attack_camp/4` already pays)
    * `:barbarians_killed` - `BrokenOaths.Game.player_stats/2`'s own
      field, same status as `:camps_destroyed` (bumped alongside the
      bounty gold `Game.attack/4` and barbarian-initiated kills already
      pay)
    * `:players_discovered` - `length(Game.known_players(world, user))`
      — the same list `GameLive.KnownPlayersPanel` already renders

  ## Turns-to-Bronze projection

  A forward projection at the player's CURRENT science/turn rate,
  independent of whether Bronze Working happens to be the tech
  currently selected: `ceil((cost - banked) / science_per_turn)`. With
  no science income yet (no city founded), the projection has no
  meaningful answer — rendered as "—" rather than a divide-by-zero
  crash.
  """

  use BrokenOathsWeb, :live_component

  alias BrokenOaths.Game.Research

  @impl true
  def render(assigns) do
    banked_bronze = Research.banked(assigns.player_research, :bronze_working)
    bronze_cost = Research.cost(:bronze_working)

    assigns =
      assigns
      |> assign(:age, Research.age(assigns.player_research))
      |> assign(:banked_bronze, banked_bronze)
      |> assign(:bronze_cost, bronze_cost)
      |> assign(
        :turns_to_bronze,
        turns_to_bronze(banked_bronze, bronze_cost, assigns.player_research.science_per_turn)
      )
      |> assign(:first_city?, assigns.cities_founded > 0)
      |> assign(:first_kill?, assigns.barbarians_killed > 0)
      |> assign(:first_camp?, assigns.camps_destroyed > 0)
      |> assign(:first_discovery?, assigns.players_discovered > 0)

    ~H"""
    <div id={@id} data-test="progress-panel" class="card bg-base-200 shadow-sm w-64">
      <div class="card-body gap-2 p-3">
        <h3 class="card-title text-sm">Progress</h3>

        <div class="text-sm flex justify-between">
          <span class="opacity-70">Age</span>
          <span data-test="progress-age">{age_label(@age)}</span>
        </div>

        <div class="text-sm flex justify-between">
          <span class="opacity-70">Science/turn</span>
          <span data-test="progress-science-per-turn">{@player_research.science_per_turn}</span>
        </div>

        <div class="text-sm flex justify-between">
          <span class="opacity-70">Bronze Working</span>
          <span data-test="progress-bronze-working">{@banked_bronze} / {@bronze_cost}</span>
        </div>

        <div class="text-sm flex justify-between">
          <span class="opacity-70">Turns to Bronze</span>
          <span data-test="progress-turns-to-bronze">{@turns_to_bronze || "—"}</span>
        </div>

        <div class="divider my-0"></div>

        <div class="text-sm flex justify-between">
          <span class="opacity-70">Cities founded</span>
          <span data-test="progress-cities">{@cities_founded}</span>
        </div>

        <div class="text-sm flex justify-between">
          <span class="opacity-70">Camps destroyed</span>
          <span data-test="progress-camps">{@camps_destroyed}</span>
        </div>

        <div class="text-sm flex justify-between">
          <span class="opacity-70">Barbarians killed</span>
          <span data-test="progress-barbarians">{@barbarians_killed}</span>
        </div>

        <div class="divider my-0"></div>

        <.milestone test="milestone-first-city" label="First city founded" achieved?={@first_city?} />
        <.milestone
          test="milestone-first-kill"
          label="First barbarian killed"
          achieved?={@first_kill?}
        />
        <.milestone
          test="milestone-first-camp"
          label="First camp destroyed"
          achieved?={@first_camp?}
        />
        <.milestone
          test="milestone-first-discovery"
          label="First player discovered"
          achieved?={@first_discovery?}
        />
      </div>
    </div>
    """
  end

  attr :test, :string, required: true
  attr :label, :string, required: true
  attr :achieved?, :boolean, required: true

  defp milestone(assigns) do
    ~H"""
    <div data-test={@test} class="text-xs flex justify-between items-center">
      <span class="opacity-70">{@label}</span>
      <span class={milestone_class(@achieved?)}>{milestone_text(@achieved?)}</span>
    </div>
    """
  end

  defp milestone_text(true), do: "Achieved"
  defp milestone_text(false), do: "Not yet"

  defp milestone_class(true), do: "text-success font-semibold"
  defp milestone_class(false), do: "opacity-50"

  defp age_label(:stone_age), do: "Stone Age"
  defp age_label(:bronze_age), do: "Bronze Age"

  # A forward projection at the CURRENT science/turn rate — `nil` (no
  # meaningful answer) with zero science income. `remaining` floors at
  # 0 so a completed (or fully banked) Bronze Working reads 0 turns,
  # never a stale positive number.
  defp turns_to_bronze(_banked, _cost, 0), do: nil

  defp turns_to_bronze(banked, cost, science_per_turn) do
    remaining = max(cost - banked, 0)
    ceil_div(remaining, science_per_turn)
  end

  defp ceil_div(dividend, divisor), do: div(dividend + divisor - 1, divisor)
end
