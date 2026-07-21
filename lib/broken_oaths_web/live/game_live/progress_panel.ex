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
      projection are all derived from it via `BrokenOaths.Technology.Research`
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
    * `:gold_per_turn` - `BrokenOaths.Game.gold_per_turn/2`'s own
      `%{income:, upkeep:, net:}` (stories 922/923's gold-maintenance
      economy — every unit's/building's own upkeep,
      `BrokenOaths.Feudal.Bank.maintenance_by_player/1`, netted against
      gross city income) — rendered as the one figure that matters to a
      player, "Gold/turn: +N"/"Gold/turn: -N", so it's legible WHY gold
      isn't climbing even before the flag ever turns the actual sweep
      on (`BrokenOaths.Game.gold_per_turn/2`'s own doc: a pure read,
      never gated on `Game.feudal_enabled?/0`).

  ## Turns-to-Bronze projection

  A forward projection at the player's CURRENT science/turn rate,
  independent of whether Bronze Working happens to be the tech
  currently selected: `ceil((cost - banked) / science_per_turn)`. With
  no science income yet (no city founded), the projection has no
  meaningful answer — rendered as "—" rather than a divide-by-zero
  crash.
  """

  use BrokenOathsWeb, :live_component

  alias BrokenOaths.Technology.Research

  @impl true
  def render(assigns) do
    bronze_cost = Research.cost(:bronze_working)
    # Cap the displayed banked science at the cost: an already-completed (or
    # over-banked) Bronze Working reads "100 / 100", not "108 / 100" (issue
    # cae519c3). turns_to_bronze already floors remaining at 0, so this is the
    # same clamp applied to the raw banked/cost row.
    banked_bronze = min(Research.banked(assigns.player_research, :bronze_working), bronze_cost)

    assigns =
      assigns
      |> assign(:age, Research.age(assigns.player_research))
      |> assign(:banked_bronze, banked_bronze)
      |> assign(:bronze_cost, bronze_cost)
      |> assign(
        :turns_to_bronze,
        turns_remaining(banked_bronze, bronze_cost, assigns.player_research.science_per_turn)
      )
      |> assign(
        :current_research_line,
        current_research_line(assigns.player_research)
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

        <%!-- Playtest issue 3 — current research + progress, without
             opening the tech menu: whatever `current_research` is right
             now (any of the eleven techs, not just Bronze Working —
             `progress-bronze-working`/`progress-turns-to-bronze` below
             stay put as their own always-visible milestone rows). --%>
        <div class="text-sm flex justify-between gap-2">
          <span class="opacity-70">Researching</span>
          <span data-test="progress-current-research" class="text-right">
            {@current_research_line}
          </span>
        </div>

        <div class="text-sm flex justify-between">
          <span class="opacity-70">Bronze Working</span>
          <span data-test="progress-bronze-working">{@banked_bronze} / {@bronze_cost}</span>
        </div>

        <div class="text-sm flex justify-between">
          <span class="opacity-70">Turns to Bronze</span>
          <span data-test="progress-turns-to-bronze">{@turns_to_bronze || "—"}</span>
        </div>

        <div class="text-sm flex justify-between">
          <span class="opacity-70">Gold/turn</span>
          <span data-test="progress-gold-per-turn" class={gold_per_turn_class(@gold_per_turn.net)}>
            {gold_per_turn_text(@gold_per_turn.net)}
          </span>
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

  # Stories 922/923 — the one figure that makes the gold-maintenance
  # drain legible: a signed "+N"/"-N" (never a bare "N", so a surplus
  # and a deficit are never confused at a glance), colored the same
  # success/error pair `milestone_class/1` above already uses.
  defp gold_per_turn_text(net) when net >= 0, do: "+#{net}"
  defp gold_per_turn_text(net), do: "#{net}"

  defp gold_per_turn_class(net) when net >= 0, do: "text-success font-semibold"
  defp gold_per_turn_class(_net), do: "text-error font-semibold"

  # A forward projection at the CURRENT science/turn rate — `nil` (no
  # meaningful answer) with zero science income. `remaining` floors at
  # 0 so a completed (or fully banked) tech reads 0 turns, never a
  # stale positive number. Shared by the Bronze Working row above and
  # `current_research_line/1` below — both are the same "banked, cost,
  # rate -> turns" math, just for a different tech.
  defp turns_remaining(_banked, _cost, 0), do: nil

  defp turns_remaining(banked, cost, science_per_turn) do
    remaining = max(cost - banked, 0)
    ceil_div(remaining, science_per_turn)
  end

  defp ceil_div(dividend, divisor), do: div(dividend + divisor - 1, divisor)

  # Playtest issue 3 — "Researching: nothing" with no `current_research`
  # selected, else "Researching: <Tech> — <banked>/<cost> (<n> turns)"
  # (`turns_remaining/3`'s own "—" fallback with no science income yet).
  defp current_research_line(%{current_research: nil}), do: "Researching: nothing"

  defp current_research_line(%{current_research: tech} = player_research) do
    cost = Research.cost(tech)
    banked = Research.banked(player_research, tech)
    turns = turns_remaining(banked, cost, player_research.science_per_turn)

    "Researching: #{Research.tech_label(tech)} — #{banked}/#{cost} (#{turns || "—"} turns)"
  end
end
