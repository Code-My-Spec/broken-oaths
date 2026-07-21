defmodule BrokenOathsWeb.GameLive.BoardOverlays do
  @moduledoc """
  The board's own absolutely-positioned overlay chrome — mounted by
  `BrokenOathsWeb.GameLive.Play` as a sibling of the canvas viewport
  div (which stays in `Play` itself since its `phx-hook=".Board"` must
  compile in the SAME module as the colocated `<script :type={
  Phoenix.LiveView.ColocatedHook} name=".Board">` hook body — `phx-hook`'s
  leading-dot name is rewritten to `"\#{inspect(caller.module)}.Board"` at
  compile time, so splitting the hook trigger element from its script
  tag across two modules would change the hook's own name and, with
  it, the rendered DOM).

  Four corners: the durable Known Players/Chat/Alliance stack
  (top-right), the transient order/combat/city/improvement/steward
  error toasts (top-left), the durable Progress panel (bottom-left),
  and the selection detail pane — tile, camp, unit, or city, whichever
  is currently selected (bottom-right). A purely presentational
  function component: `Play` owns selection state and command
  dispatch, this only ever renders the assigns it's given, the same
  "no `BrokenOaths.Game` read of its own" posture `GameLive.UnitPanel`/
  `GameLive.CityPanel` already establish.
  """

  use BrokenOathsWeb, :html

  alias BrokenOaths.Combat.Camp

  attr :chat_open, :boolean, required: true
  attr :known_players, :list, required: true
  attr :world, :map, required: true
  attr :user, :map, required: true
  attr :chat_target_user_id, :any, required: true
  attr :order_error, :any, required: true
  attr :combat_error, :any, required: true
  attr :city_error, :any, required: true
  attr :improvement_error, :any, required: true
  # Story 927 "Workers chop woods and rainforest" — the Chop command's
  # own transient error toast, same status `improvement_error` above
  # already has.
  attr :chop_error, :any, required: true
  attr :steward_error, :any, required: true
  attr :player_research, :any, required: true
  attr :cities, :list, required: true
  attr :player_stats, :map, required: true
  # Stories 922/923 — `GameLive.ProgressPanel`'s own "Gold/turn" line
  # (`%{income:, upkeep:, net:}`, `BrokenOaths.Game.gold_per_turn/2`),
  # the same "computed by `Play`, only rendered here" status
  # `player_stats` above already has.
  attr :gold_per_turn, :map, required: true
  attr :selected_tile, :any, required: true
  attr :selected_camp, :any, required: true
  attr :selected_unit, :any, required: true
  attr :selected_order, :any, required: true
  attr :allowed_improvements, :list, required: true
  attr :current_dig, :any, required: true
  # Story 927 — `Play`'s own precomputed Chop legality for the selected
  # unit (`nil | :woods | :rainforest`), same "computed by `Play`, only
  # rendered here" status `current_dig` above already has.
  attr :choppable_feature, :any, required: true
  attr :attackable_cities, :list, required: true
  # QA issue 12bed1e4 — the "Shoot" affordance's own target list for a
  # selected Archer, the same "computed by `Play`, only rendered here"
  # status `attackable_cities` above already has.
  attr :shoot_targets, :list, required: true
  attr :selected_city, :any, required: true
  attr :assignable_tiles, :list, required: true
  attr :copper_access?, :boolean, required: true
  # Story 921 (the Galley) — see `GameLive.CityPanel`'s own moduledoc.
  attr :coastal?, :boolean, required: true
  # Story 933 (the Pyramids/Hanging Gardens wonders) — see
  # `GameLive.CityPanel`'s own moduledoc.
  attr :wonders_claimed, :map, required: true

  def overlays(assigns) do
    ~H"""
    <%!-- Story 899/900/901: the durable Known Players roster +
             discovery toast affordance, the chat button/panel beside it,
             and the alliance button/panel beside that. `KnownPlayersPanel`
             is hidden while `ChatPanel` is open — its own contact list
             reuses the same "known-player-ID" row shape, so only one of
             the two is ever on the page at once (the same "one side panel
             at a time" rule Play already applies to unit/city selection).
             `AlliancePanel` uses its own distinct "ally-candidate-ID"/
             "alliance-ID" naming (see its own moduledoc), so it never
             needs that same exclusion — both button rows stay reachable
             together.

             QA issue 3525f2ba: below `md` (a phone) the always-on w-64
             Known Players card, stacked against the Progress panel and
             the top status bar, left no room for the board at all. The
             SAME single `KnownPlayersPanel` mount below just gets a
             `hidden md:block` wrapper — one instance, never duplicated
             (a second copy would collide on `known-player-ID`, breaking
             the very one-match-per-selector contract the `ChatPanel`
             exclusion above already depends on) — collapsed behind a
             small `md:hidden` toggle button that shows/hides it and
             closes the Progress drawer in turn (`toggle_mobile_panel/1`),
             so a phone never has both durable panels open together.
             `md:` and up ignores all of this — the toggle button itself
             never renders there, and `md:block` always wins regardless
             of the toggle's last mobile-only state. --%>
    <div class="absolute top-4 right-4 flex flex-col gap-2 items-end">
      <button
        :if={!@chat_open}
        type="button"
        phx-click={toggle_mobile_panel("mobile-known-players")}
        class="btn btn-sm btn-circle btn-ghost bg-base-200 shadow-sm md:hidden"
        data-test="mobile-known-players-toggle"
        aria-label="Known Players"
      >
        <.icon name="hero-users" class="w-4 h-4" />
      </button>

      <div id="mobile-known-players" class="hidden md:block">
        <.live_component
          :if={!@chat_open}
          module={BrokenOathsWeb.GameLive.KnownPlayersPanel}
          id="known-players-panel"
          known_players={@known_players}
        />
      </div>

      <div class="flex gap-2">
        <.live_component
          module={BrokenOathsWeb.GameLive.ChatPanel}
          id="chat-panel"
          world={@world}
          user={@user}
          chat_target_user_id={@chat_target_user_id}
        />

        <.live_component
          module={BrokenOathsWeb.GameLive.AlliancePanel}
          id="alliance-panel"
          world={@world}
          user={@user}
          known_players={@known_players}
        />
      </div>
    </div>

    <div class="absolute top-4 left-4 flex flex-col gap-2 items-start">
      <div :if={@order_error} class="alert alert-error w-auto shadow-lg" data-test="order-error">
        <.icon name="hero-exclamation-triangle" class="w-4 h-4" /> {@order_error}
      </div>

      <div
        :if={@combat_error}
        class="alert alert-error w-auto shadow-lg"
        data-test="combat-error"
      >
        <.icon name="hero-exclamation-triangle" class="w-4 h-4" /> {@combat_error}
      </div>

      <div :if={@city_error} class="alert alert-error w-auto shadow-lg" data-test="city-error">
        <.icon name="hero-exclamation-triangle" class="w-4 h-4" /> {@city_error}
      </div>

      <div
        :if={@improvement_error}
        class="alert alert-error w-auto shadow-lg"
        data-test="improvement-error"
      >
        <.icon name="hero-exclamation-triangle" class="w-4 h-4" /> {@improvement_error}
      </div>

      <%!-- Story 927 "Workers chop woods and rainforest" — same toast
               pattern as `improvement-error` above. --%>
      <div :if={@chop_error} class="alert alert-error w-auto shadow-lg" data-test="chop-error">
        <.icon name="hero-exclamation-triangle" class="w-4 h-4" /> {@chop_error}
      </div>

      <%!-- QA issue bd93cc0a: production-stewardship + emergency-
               defend refusal surface, same toast pattern as every other
               error above. --%>
      <div
        :if={@steward_error}
        class="alert alert-error w-auto shadow-lg"
        data-test="steward-error"
      >
        <.icon name="hero-exclamation-triangle" class="w-4 h-4" /> {@steward_error}
      </div>
    </div>

    <%!-- Story 904: the Stone Age progress panel — always visible,
             unrelated to unit/city selection, same "durable, not a
             selection-triggered side panel" status `KnownPlayersPanel`
             already has (see that component's own moduledoc).

             QA issue 3525f2ba: the same mobile-drawer treatment as the
             Known Players panel above — one `ProgressPanel` mount,
             `hidden md:block`, collapsed behind a `md:hidden` toggle
             that closes the Known Players drawer in turn. --%>
    <div class="absolute bottom-4 left-4 flex flex-col gap-2 items-start">
      <button
        type="button"
        phx-click={toggle_mobile_panel("mobile-progress-panel")}
        class="btn btn-sm btn-circle btn-ghost bg-base-200 shadow-sm md:hidden"
        data-test="mobile-progress-toggle"
        aria-label="Progress"
      >
        <.icon name="hero-chart-bar" class="w-4 h-4" />
      </button>

      <div id="mobile-progress-panel" class="hidden md:block">
        <.live_component
          module={BrokenOathsWeb.GameLive.ProgressPanel}
          id="progress-panel"
          player_research={@player_research}
          cities_founded={length(@cities)}
          camps_destroyed={@player_stats.camps_destroyed}
          barbarians_killed={@player_stats.barbarians_killed}
          players_discovered={length(@known_players)}
          gold_per_turn={@gold_per_turn}
        />
      </div>
    </div>

    <%!-- QA issue e51a31be "UI issues" — the selection detail pane
             (tile/unit/city/camp): absolutely positioned so it never
             stretches to the board's full height or crowds board-viewport
             out of the flex row (the original bug — a plain flow child
             under a `relative` container with no `items-start` stretched
             to 100% height and sat directly under the top-right corner
             overlays), sized to its own content, anchored to the one
             free corner (top-right is Known Players/Chat/Alliance,
             bottom-left is Progress), and capped/scrollable so even a
             tall panel never covers the whole board. Every panel gets
             its own close (X), routed through the shared
             "clear_selection" handler. --%>
    <div
      :if={@selected_tile || @selected_unit || @selected_city || @selected_camp}
      data-test="detail-pane"
      class="absolute bottom-4 right-4 z-20 max-h-[70vh] overflow-y-auto flex flex-col gap-2"
    >
      <div
        :if={@selected_tile}
        class="card bg-base-200/95 shadow-xl w-64 relative"
        data-test="tile-panel"
      >
        <button
          type="button"
          phx-click="clear_selection"
          data-test="close-tile-panel"
          class="btn btn-ghost btn-xs btn-circle absolute top-1 right-1"
        >
          <.icon name="hero-x-mark" class="w-4 h-4" />
        </button>
        <div class="card-body p-4 gap-1">
          <h3 class="card-title text-sm pr-6" data-test="tile-terrain">
            {@selected_tile.terrain}
          </h3>
          <p class="text-xs opacity-80" data-test="tile-yields">
            +{@selected_tile.food} food · +{@selected_tile.production} production
          </p>
          <p :if={@selected_tile.improvement} class="text-xs" data-test="tile-improvement">
            {improvement_summary(@selected_tile.improvement)}
          </p>
          <p :if={@selected_tile.resource} class="text-xs" data-test="tile-resource">
            {resource_label(@selected_tile.resource)}
          </p>
        </div>
      </div>

      <%!-- QA issue 748348fe "barbarian camp issues" — a camp under
               siege now shows its own HP, the same "watch it drop"
               readout `city-hp` already gives a besieged city. --%>
      <div
        :if={@selected_camp}
        class="card bg-base-200/95 shadow-xl w-64 relative"
        data-test="camp-panel"
      >
        <button
          type="button"
          phx-click="clear_selection"
          data-test="close-camp-panel"
          class="btn btn-ghost btn-xs btn-circle absolute top-1 right-1"
        >
          <.icon name="hero-x-mark" class="w-4 h-4" />
        </button>
        <div class="card-body p-4 gap-1">
          <h3 class="card-title text-sm pr-6" data-test="camp-name">Barbarian Camp</h3>
          <span class="badge badge-error badge-outline w-fit" data-test="camp-hp">
            {@selected_camp.hp}/{Camp.max_hp()}
          </span>
        </div>
      </div>

      <.live_component
        :if={@selected_unit}
        module={BrokenOathsWeb.GameLive.UnitPanel}
        id="unit-panel"
        unit={@selected_unit}
        order={@selected_order}
        allowed_improvements={@allowed_improvements}
        current_dig={@current_dig}
        choppable_feature={@choppable_feature}
        attackable_cities={@attackable_cities}
        shoot_targets={@shoot_targets}
      />

      <.live_component
        :if={@selected_city}
        module={BrokenOathsWeb.GameLive.CityPanel}
        id="city-panel"
        city={@selected_city}
        assignable_tiles={@assignable_tiles}
        player_research={@player_research}
        copper_access?={@copper_access?}
        coastal?={@coastal?}
        wonders_claimed={@wonders_claimed}
      />
    </div>
    """
  end

  # QA issue 3525f2ba — the mobile drawer toggle for the Known Players/
  # Progress panels (see their own wrappers above): pure client
  # `Phoenix.LiveView.JS`, no server round trip, since neither panel's
  # OWN state changes — only which one is visible. Opening either closes
  # the other, so a phone never has both durable panels open at once
  # (criterion: "Mobile can only support a single contextual menu").
  # `md:` and up never calls this at all — the toggle buttons that
  # invoke it are themselves `md:hidden`.
  defp toggle_mobile_panel(id) do
    other =
      if id == "mobile-known-players", do: "mobile-progress-panel", else: "mobile-known-players"

    %JS{}
    |> JS.toggle(to: "##{id}")
    |> JS.hide(to: "##{other}")
  end

  defp improvement_summary(%{kind: kind, status: :complete}),
    do: "#{kind |> to_string() |> String.capitalize()} (complete)"

  defp improvement_summary(%{kind: kind, status: :pillaged}),
    do: "#{kind |> to_string() |> String.capitalize()} (pillaged — a worker repairs it in 1 turn)"

  defp improvement_summary(%{kind: kind, status: :building, progress: progress}),
    do: "#{kind |> to_string() |> String.capitalize()} under construction (#{progress} banked)"

  defp resource_label(:cattle), do: "Cattle"
  defp resource_label(:sheep), do: "Sheep"
  defp resource_label(:wheat), do: "Wheat"
  defp resource_label(:stone), do: "Stone"
  defp resource_label(:copper), do: "Copper"
end
