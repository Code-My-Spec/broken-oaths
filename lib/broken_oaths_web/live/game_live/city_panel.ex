defmodule BrokenOathsWeb.GameLive.CityPanel do
  @moduledoc """
  Selected city details: name (renameable), size, food-to-growth
  progress, the current build's progress, the production catalog, and
  worked-tile assignment.

  A presentational component mounted by `BrokenOathsWeb.GameLive.Play`,
  which owns city selection, command dispatch, and error state — this
  component never reads from `BrokenOaths.Game` itself and defines no
  `handle_event/3` of its own. Every interactive element pushes a plain
  DOM event with no `phx-target`, so it bubbles to `Play` exactly like
  `GameLive.UnitPanel`'s pattern (none of Play's board doctrine changes:
  no tile DOM, no component-owned state).

  Assigns:

    * `:id` - the DOM id for this component instance
    * `:city` - the selected city, or `nil` when nothing is selected.
      Shape: `id`, `name`, `tile_id`, `size`, `food`, `food_threshold`
      (`nil` at the Stone Age cap), `production` (per-turn rate),
      `queue` (`[%{id:, type:, banked:, cost:}]`, head = current),
      `territory` (`[tile_id]`), `worked_tiles` (`[tile_id]`, excludes
      the always-free center), `hp` (story 895, capped at
      `Game.CityDefense.max_hp/0`), `defense` (`Game.CityDefense.
      defensive_strength/2` — base + size + garrison), `has_granary`
      (story 902's Pottery-gated Granary buildable — QA issue
      `1c47edff`: this flag reached `Game.player_cities/2`'s map late,
      after the Granary itself already shipped, which is exactly why a
      built one had no way to show up here before this fix), `status`
      (story 906 — `:free | :broken | :occupied`, `Game.Siege.status/1`)
    * `:assignable_tiles` - territory tiles Play has already filtered
      to "not the center, not already worked, workable terrain" — this
      component has no world/terrain access to compute that itself
    * `:player_research` - the city owner's research state (`Game.
      player_research/2`'s shape), used ONLY to gate the Build
      catalog — `Research.granary_enabled?/1` (story 902) and
      `Research.age/1 == :bronze_age` (story 903). `nil`/missing reads
      as "nothing unlocked yet", the same posture a fresh player's
      `Research.new/0` would produce.
    * `:copper_access?` - story 911: whether `city` itself currently has
      Copper access (a Copper tile anywhere in its own `territory`,
      worked or not) — Play computes this from `world` + `city.
      territory` (`BrokenOaths.Worlds.Resources.at/2`), since this
      component has no world access of its own, the same reason
      `assignable_tiles` arrives pre-computed. Defaults to `false` when
      omitted (no city selected yet), the same "missing reads as not
      unlocked" posture `player_research` already has.

  The production catalog is dynamic, not a fixed compile-time list
  (QA issue 846e0c96 — Bronze Spearman never appeared in the Build UI
  because the catalog was hardcoded to Settler/Worker/Warrior and
  never extended): `Production.available_items/1` decides which TYPES
  are worth offering at all, reading the identical `opts`
  (`granary_available?`, `bronze_age?`) `Production.can_queue?/3`
  itself reads, so this component can never offer — or hide — a
  buildable the `queue_production` command would disagree with. Each
  offered type's cost and its remaining `disabled?` state (the size-1
  Settler guard, an already-built Granary, or — story 911 — a Bronze
  Age city with no Copper access) are still read straight from
  `BrokenOaths.Cities.Production` (a pure, dependency-free core module)
  rather than duplicated here — one source of truth for what's
  buildable and what it costs. `Research` is likewise read directly
  (also pure/dependency-free) to resolve `player_research` into those
  `opts` — this stays within the "reads pure core modules directly"
  latitude `Production`/`CityDefense` already establish; the
  component still never round-trips through the stateful
  `BrokenOaths.Game` context itself.

  ## The Bronze Spearman's Copper requirement (story 911)

  Whenever `:bronze_spearman` is offered (only once Bronze Working is
  done — `Production.available_items/1`), its own catalog row ALSO
  renders `[data-test="production-requirement-bronze_spearman"]`
  unconditionally — "Requires Copper", plus a `data-copper-met`
  attribute and a checkmark once `copper_access?` is true — so the
  requirement is legible in the production menu whether or not it is
  currently met (criterion 7708), not only in its disabled state. When
  `copper_access?` is false, `can_queue?/3` returns
  `{:error, :copper_required}` and the button itself renders `disabled`
  (`data-disabled="true"`, the same `[data-test="production-option-
  bronze_spearman"]` hook story 903 already established) alongside
  that same requirement note — no separate "reason" paragraph is
  needed, unlike the Settler's size-1 guard, since the requirement note
  already carries the reason text.
  """

  use BrokenOathsWeb, :live_component

  alias BrokenOaths.Game.CityDefense
  alias BrokenOaths.Cities.Production
  alias BrokenOaths.Technology.Research
  alias BrokenOaths.Cities.Yields

  def render(%{city: nil} = assigns) do
    ~H"""
    <div id={@id}></div>
    """
  end

  def render(assigns) do
    production_opts =
      production_opts(
        Map.get(assigns, :player_research),
        Map.get(assigns, :copper_access?, false)
      )

    assigns =
      assigns
      |> assign(:assignable_tiles, Map.get(assigns, :assignable_tiles, []))
      |> assign(:production_opts, production_opts)
      |> assign(:catalog, Production.available_items(production_opts))

    ~H"""
    <div id={@id} data-test="city-panel" class="card bg-base-200 shadow-sm w-72 relative">
      <%!-- QA issue e51a31be — every selection panel gets its own
           dismiss affordance; this bubbles "clear_selection" to `Play`
           exactly like every other button here (no `phx-target`). --%>
      <button
        type="button"
        phx-click="clear_selection"
        data-test="close-city-panel"
        class="btn btn-ghost btn-xs btn-circle absolute top-1 right-1"
      >
        <.icon name="hero-x-mark" class="w-4 h-4" />
      </button>
      <div class="card-body gap-3">
        <.name_header city={@city} />

        <div class="flex items-center gap-3 text-sm">
          <span class="badge badge-neutral" data-test="city-size">{@city.size}</span>
          <span data-test="city-food">
            <.icon name="hero-cake" class="w-3 h-3" /> {@city.food}/{food_label(@city.food_threshold)}
          </span>
          <span class="opacity-60">+{@city.production}/turn</span>
        </div>

        <div class="flex items-center gap-3 text-sm">
          <span class="badge badge-error badge-outline" data-test="city-hp">
            {@city.hp}/{CityDefense.max_hp()}
          </span>
          <span class="badge badge-outline" data-test="city-defense">{@city.defense}</span>
          <%!-- Story 906 — `@city.status` (`Siege.status/1`, computed by
               `Game.player_cities/2`) is `:free` in the ordinary healthy
               case, rendered as no badge at all (criterion 7664 relies
               on that absence as its own anchor). --%>
          <span
            :if={Map.get(@city, :status, :free) != :free}
            class="badge badge-warning badge-outline"
            data-test="city-status"
          >
            {@city.status}
          </span>
        </div>

        <%!-- QA issue 1c47edff "Granary confusion" — a built Granary
             had no visible trace anywhere in the city UI. Only ever
             renders once `has_granary` is true; the real bonus is read
             straight from `Yields.granary_food_bonus/0`, never a copy
             hardcoded here that could drift from what `accrue_food/3`
             actually banks. --%>
        <div
          :if={Map.get(@city, :has_granary, false)}
          data-test="city-granary"
          class="badge badge-success badge-outline gap-1 text-xs"
        >
          <.icon name="hero-check-circle" class="size-3" />
          Granary (+{Yields.granary_food_bonus()} food/turn)
        </div>

        <.current_production queue={@city.queue} city_id={@city.id} />

        <div class="divider my-0 text-xs opacity-60">Build</div>
        <div class="flex flex-col gap-1">
          <.catalog_option
            :for={type <- @catalog}
            type={type}
            city={@city}
            production_opts={@production_opts}
          />
        </div>

        <div :if={length(@city.queue) > 1} class="divider my-0 text-xs opacity-60">Queue</div>
        <.queue_item :for={item <- Enum.drop(@city.queue, 1)} item={item} city_id={@city.id} />

        <div class="divider my-0 text-xs opacity-60">Worked Tiles</div>
        <div class="flex flex-col gap-1 text-sm">
          <div
            data-test={"city-worked-tile-#{@city.tile_id}"}
            class="flex items-center justify-between opacity-70"
          >
            <span>Tile {@city.tile_id} (center)</span>
            <span class="badge badge-ghost badge-sm">Free</span>
          </div>

          <.worked_tile :for={tile_id <- @city.worked_tiles} tile_id={tile_id} city_id={@city.id} />

          <.assignable_tile :for={tile_id <- @assignable_tiles} tile_id={tile_id} city_id={@city.id} />
        </div>
      </div>
    </div>
    """
  end

  attr :city, :map, required: true

  defp name_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-2">
      <h3 data-test="city-name" class="card-title text-base">{@city.name}</h3>
    </div>

    <form data-test="city-name-form" phx-submit="rename_city" class="flex gap-1">
      <input
        type="text"
        name="city[name]"
        value={@city.name}
        class="input input-xs input-bordered flex-1"
      />
      <button type="submit" class="btn btn-xs">Rename</button>
    </form>
    """
  end

  attr :queue, :list, required: true
  attr :city_id, :any, required: true

  defp current_production(%{queue: []} = assigns) do
    ~H"""
    <div data-test="city-production-current" class="text-sm opacity-60">
      Nothing queued
    </div>
    """
  end

  defp current_production(assigns) do
    assigns = assign(assigns, :current, hd(assigns.queue))

    ~H"""
    <div class="flex flex-col gap-1">
      <div class="flex items-center justify-between">
        <div data-test="city-production-current" class="text-sm font-medium">
          {catalog_label(@current.type)} {@current.banked}/{@current.cost}
        </div>
        <%!-- Abandoning mid-build is a real choice (story 879: it
             forfeits the invested production), so it gets a real
             button — QA issue e5c751b4. --%>
        <button
          type="button"
          data-test="cancel-current-production"
          phx-click="cancel_production_item"
          phx-value-city_id={@city_id}
          phx-value-item_id={@current.id}
          class="btn btn-ghost btn-xs text-error"
        >
          Abandon
        </button>
      </div>
      <progress
        data-test="city-production-progress"
        class="progress progress-primary w-full"
        value={@current.banked}
        max={@current.cost}
      >
      </progress>
    </div>
    """
  end

  attr :type, :atom, required: true
  attr :city, :map, required: true
  attr :production_opts, :list, required: true

  defp catalog_option(assigns) do
    result = Production.can_queue?(assigns.city, assigns.type, assigns.production_opts)
    disabled? = result != :ok
    copper_access? = Keyword.get(assigns.production_opts, :copper_access?, false)

    assigns =
      assign(assigns,
        disabled?: disabled?,
        cost: Production.cost(assigns.type),
        copper_access?: copper_access?
      )

    ~H"""
    <div>
      <button
        type="button"
        data-test={"production-option-#{@type}"}
        data-disabled={to_string(@disabled?)}
        disabled={@disabled?}
        phx-click="queue_production"
        phx-value-city_id={@city.id}
        phx-value-item={@type}
        class="btn btn-sm btn-outline justify-between w-full"
      >
        <span>{catalog_label(@type)}</span>
        <span>{@cost}</span>
      </button>
      <p
        :if={@disabled? and @type == :settler}
        data-test="production-disabled-reason-settler"
        class="text-xs text-warning"
      >
        Needs a second citizen to spare
      </p>
      <%!-- Story 911, criterion 7708 — the Copper requirement is
           legible whether or not it's currently met: this renders
           whenever Bronze Spearman is offered at all (only once
           Bronze Working is done), with `data-copper-met` and a
           checkmark once `copper_access?` is true, and doubles as the
           disabled-reason note when it isn't (the button itself is
           already `disabled` above via `can_queue?/3`'s
           `{:error, :copper_required}`). --%>
      <p
        :if={@type == :bronze_spearman}
        data-test="production-requirement-bronze_spearman"
        data-copper-met={to_string(@copper_access?)}
        class={["text-xs", if(@copper_access?, do: "text-success", else: "text-warning")]}
      >
        Requires Copper{if @copper_access?, do: " ✓", else: ""}
      </p>
    </div>
    """
  end

  attr :item, :map, required: true
  attr :city_id, :any, required: true

  defp queue_item(assigns) do
    ~H"""
    <div data-test={"queue-item-#{@item.id}"} class="flex items-center justify-between text-sm">
      <span>{catalog_label(@item.type)} ({@item.cost})</span>
      <div class="flex items-center gap-1">
        <%!-- Free reordering (story 879) — one slot toward the head
             per click; progress stays with the item. --%>
        <button
          type="button"
          data-test={"queue-move-up-#{@item.id}"}
          phx-click="reorder_production_item"
          phx-value-city_id={@city_id}
          phx-value-item_id={@item.id}
          class="btn btn-ghost btn-xs"
          title="Move up"
        >
          ↑
        </button>
        <button
          type="button"
          data-test={"queue-cancel-#{@item.id}"}
          phx-click="cancel_production_item"
          phx-value-city_id={@city_id}
          phx-value-item_id={@item.id}
          class="btn btn-ghost btn-xs"
        >
          Cancel
        </button>
      </div>
    </div>
    """
  end

  attr :tile_id, :any, required: true
  attr :city_id, :any, required: true

  defp worked_tile(assigns) do
    ~H"""
    <div data-test={"city-worked-tile-#{@tile_id}"} class="flex items-center justify-between">
      <span>Tile {@tile_id}</span>
      <button
        type="button"
        phx-click="assign_worked_tile"
        phx-value-city_id={@city_id}
        phx-value-from_tile_id={@tile_id}
        class="btn btn-ghost btn-xs"
      >
        Unwork
      </button>
    </div>
    """
  end

  attr :tile_id, :any, required: true
  attr :city_id, :any, required: true

  defp assignable_tile(assigns) do
    ~H"""
    <div
      data-test={"city-assignable-tile-#{@tile_id}"}
      class="flex items-center justify-between opacity-70"
    >
      <span>Tile {@tile_id}</span>
      <button
        type="button"
        phx-click="assign_worked_tile"
        phx-value-city_id={@city_id}
        phx-value-to_tile_id={@tile_id}
        class="btn btn-ghost btn-xs"
      >
        Work
      </button>
    </div>
    """
  end

  defp food_label(nil), do: "Capped"
  defp food_label(threshold), do: threshold

  # Resolves `player_research` + `copper_access?` into the `opts` both
  # `Production.available_items/1` (which types to OFFER) and
  # `Production.can_queue?/3` (whether an offered type is currently
  # `disabled?`) read — `nil`/missing `player_research` reads as
  # "nothing unlocked", same as a fresh `Research.new/0` player.
  # `copper_access?` (story 911) is passed straight through regardless
  # of `player_research`'s own presence — `Production.can_queue?/3`
  # already refuses `:bronze_spearman` on `bronze_age?` alone whenever
  # research is unknown, so a stray `copper_access?: true` with no
  # research can never enable it early.
  defp production_opts(nil, copper_access?), do: [copper_access?: copper_access?]

  defp production_opts(player_research, copper_access?) do
    [
      granary_available?: Research.granary_enabled?(player_research),
      bronze_age?: Research.age(player_research) == :bronze_age,
      copper_access?: copper_access?,
      archery?: Research.archery_enabled?(player_research)
    ]
  end

  defp catalog_label(:settler), do: "Settler"
  defp catalog_label(:worker), do: "Worker"
  defp catalog_label(:warrior), do: "Warrior"
  defp catalog_label(:granary), do: "Granary"
  defp catalog_label(:bronze_spearman), do: "Bronze Spearman"
  # QA issue da39e50b — see `BrokenOaths.Cities.Production`'s own
  # moduledoc, "The Archer".
  defp catalog_label(:archer), do: "Archer"
end
