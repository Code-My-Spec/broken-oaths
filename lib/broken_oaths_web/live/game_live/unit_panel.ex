defmodule BrokenOathsWeb.GameLive.UnitPanel do
  @moduledoc """
  Selected unit details (type, HP, movement remaining), its queued
  order, and its city-loop actions: Found City for a settler, Build
  Improvement for a worker, Shoot for an Archer (QA issue 12bed1e4).

  A presentational component mounted by `BrokenOathsWeb.GameLive.Play`,
  which owns unit selection, order state, and command dispatch — every
  button here pushes a plain event with no `phx-target`, so it bubbles
  to `Play` exactly like unit selection already does. This component
  never reads from `BrokenOaths.Game` itself — it only renders the
  assigns it's given:

    * `:id` - the DOM id for this component instance
    * `:unit` - the selected unit, or `nil` when nothing is selected.
      Expected to carry `:id`, `:type` (`:lord` | `:settler` | `:worker`
      | `:warrior` | `:barbarian_warrior` | `:bronze_spearman` |
      `:archer`), `:hp`, `:max_hp`, `:movement`, `:max_movement`,
      `:charges` (story 882 playtest update, issue 1caa87e9 — a
      worker's remaining build charges; every other unit type carries
      the same field but this panel only ever renders it for `:worker`),
      `:fortified_turns` (story 920, ramped to match Civ 6 — the
      Fortify defensive stance's own turns-held counter: `0` not
      fortified, `1` the instant `fortify/3` fires (partial bonus),
      `2`+ once it survives a whole turn boundary held (full bonus);
      every unit type carries the field, only a `:defend`-capable one
      is ever offered the button that sets it)
    * `:order` - the unit's queued order, or `nil`. Expected to carry
      `:target_tile` and `:status` (`:pending` | `:interrupted`)
    * `:allowed_improvements` - improvement kinds (`:farm` | `:mine` |
      `:road` | `:pasture`) legal on the worker's own tile right now —
      `Play` computes this (it needs world/terrain/resource access this
      component doesn't have) so only legal Build actions ever render
      (story 882, criterion 7482: Farm is never offered on hills/
      forest; story 905, criterion 7648: Pasture only once Animal
      Husbandry is researched, and only on a Cattle/Sheep tile)
    * `:attackable_cities` - `[%{id:, name:, tile_id:, broken:}]` (QA
      issue 56ee521a): hostile cities adjacent to `:unit` right now,
      only ever non-empty for a military unit while
      `Game.feudal_enabled?/0` — `Play` computes this too
      (`attackable_cities/2`, same "needs world/fog access this
      component doesn't have" reason). Each renders as its own
      discoverable button, wired straight to the same command the
      board's own right-click gesture already dispatches: "Attack
      <name>" (`"attack"`/`target_city_id`) for an intact city, or
      "Move In <name>" (`"queue_move"`/`to_tile`) once `broken` is true
      (QA issue 7f91cff2) — a 0-HP city is captured by walking a unit
      onto its tile, not by attacking it again.
    * `:shoot_targets` - `[%{kind:, id:, label:, tile_id:}]` (QA issue
      12bed1e4), `kind` one of `:unit` | `:camp` | `:city`: every
      barbarian unit, barbarian camp, and hostile intact city within
      shooting range of a selected Archer right now — `Play` computes
      this too (`PlayView.shoot_targets/5`, same "needs world/fog
      access this component doesn't have" reason). Each renders as its
      own discoverable "Shoot <label>" button, dispatching `"shoot"`
      with whichever `target_*_id` key matches `kind`.

  Per-unit-TYPE action gating (which of the buttons above even CAN
  appear for this unit) is delegated to `BrokenOaths.Units.Actions.
  available/1` — a `unit.type == :settler`-style check in the template
  would otherwise have to independently agree with every OTHER place
  that already knows which type does what; `@actions` (computed once
  per render) is that same catalog, consulted here instead of
  duplicating it.
  """

  use BrokenOathsWeb, :live_component

  alias BrokenOaths.Units.Actions

  def render(%{unit: nil} = assigns) do
    ~H"""
    <div id={@id}></div>
    """
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:allowed_improvements, fn -> [] end)
      |> assign_new(:current_dig, fn -> nil end)
      |> assign_new(:choppable_feature, fn -> nil end)
      |> assign_new(:attackable_cities, fn -> [] end)
      |> assign_new(:shoot_targets, fn -> [] end)
      |> assign_new(:unit_id, fn -> Map.get(assigns.unit, :id) end)
      |> assign(:actions, Actions.available(assigns.unit))
      # Story 920 — same `Map.get/3` default the `:charges` readout
      # already uses: a hand-built unit map (a test fixture, an older
      # cached assign) may predate the `fortified_turns` field.
      |> assign(:fortified_turns, Map.get(assigns.unit, :fortified_turns, 0))
      # Owner readout (playtest: "can't tell whose unit this is"). Reads
      # the same owner fields the board's rings do (`Visibility.
      # format_unit/3`): `own` for the viewer's own, `player_id` for a
      # rival, null for barbarians. No email — a short "Player #<id>"
      # label until the display-name story lands globally.
      |> assign(:owner_label, owner_label(assigns.unit))

    ~H"""
    <div id={@id} data-test="unit-panel" class="card bg-base-200 shadow-sm w-64 relative">
      <%!-- QA issue e51a31be — same dismiss affordance as `CityPanel`,
           bubbling to `Play`'s own "clear_selection" handler. --%>
      <button
        type="button"
        phx-click="clear_selection"
        data-test="close-unit-panel"
        class="btn btn-ghost btn-xs btn-circle absolute top-1 right-1"
      >
        <.icon name="hero-x-mark" class="w-4 h-4" />
      </button>
      <div class="card-body gap-2">
        <h3 data-test="unit-type" class="card-title text-base pr-6">
          {unit_type_label(@unit.type)}
          <span :if={@unit.type == :lord} data-test="unit-crown">
            <.icon name="hero-trophy-solid" class="size-4 text-warning" />
          </span>
        </h3>
        <p data-test="unit-owner" class="text-sm text-base-content/70">
          {@owner_label}
        </p>
        <p data-test="unit-hp" class="text-sm">
          HP {@unit.hp}/{@unit.max_hp}
        </p>
        <p data-test="unit-movement" class="text-sm">
          Movement {@unit.movement}/{@unit.max_movement}
        </p>
        <p :if={@unit.type == :worker} data-test="unit-charges" class="text-sm">
          {Map.get(@unit, :charges, 3)} charges
        </p>
        <%!-- Story 920 — the Fortify stance's own status readout: a
             fortified unit always shows this badge, whoever's looking
             (the counter is public, see `Visibility.format_unit/3`),
             same "always visible, never a secret" status `unit-crown`
             has. The label itself tracks the Civ 6 ramp — "Fortifying"
             at the partial (1) level, "Fortified" once it's ramped to
             the full (2+) one — but `data-test="unit-fortified"` stays
             present at either level, so nothing downstream has to know
             which. --%>
        <div
          :if={@fortified_turns > 0}
          data-test="unit-fortified"
          class="badge badge-info gap-1 w-fit"
        >
          <.icon name="hero-shield-check" class="size-3" /> {fortify_label(@fortified_turns)}
        </div>
        <.order_summary order={@order} />

        <button
          :if={:found_city in @actions}
          type="button"
          data-test="found-city"
          phx-click="found_city"
          phx-value-unit_id={@unit_id}
          class="btn btn-sm btn-primary"
        >
          Found City
        </button>

        <%!-- Story 920 — the discoverable Fortify affordance: any
             `:defend`-capable unit not already braced gets the button;
             once it IS braced, the badge above stands in for it (never
             both at once). Applies immediately — no confirmation, no
             movement spent. --%>
        <button
          :if={:defend in @actions and @fortified_turns == 0}
          type="button"
          data-test="fortify"
          phx-click="fortify"
          phx-value-unit_id={@unit_id}
          class="btn btn-sm btn-outline"
        >
          Fortify
        </button>

        <div :if={:build_improvement in @actions} class="flex flex-col gap-1">
          <%!-- A dig in progress on the worker's tile is the loudest
               thing in the panel — silent success on Build reads as a
               dead button (issue b5cc4ae9). --%>
          <div
            :if={@current_dig}
            class="badge badge-info gap-1 whitespace-nowrap"
            data-test="dig-progress"
          >
            Digging {improvement_label(@current_dig.kind)} — {@current_dig.progress}/{BrokenOaths.Cities.Improvement.duration(
              @current_dig.kind
            )} turns
          </div>
          <button
            :if={@current_dig}
            type="button"
            data-test="cancel-build"
            phx-click="cancel_improvement"
            phx-value-unit_id={@unit_id}
            class="btn btn-sm btn-outline btn-error"
          >
            Cancel Build
          </button>
          <.build_button
            :for={kind <- @allowed_improvements}
            :if={is_nil(@current_dig)}
            kind={kind}
            unit_id={@unit_id}
          />
        </div>

        <%!-- Story 927 "Workers chop woods and rainforest" — the
             discoverable "Chop" affordance: `Play` precomputes
             `@choppable_feature` (`nil` unless the worker's own tile is
             legally choppable right now — feature present, in-borders,
             tech researched, a charge left), so this button never
             offers an illegal chop the way `allowed_improvements`
             already keeps Build honest. Resolves immediately — no
             progress badge, unlike a multi-turn Build dig. --%>
        <button
          :if={:chop in @actions and @choppable_feature}
          type="button"
          data-test={"chop-#{@choppable_feature}"}
          phx-click="chop"
          phx-value-unit_id={@unit_id}
          class="btn btn-sm btn-outline"
        >
          Chop {improvement_label(@choppable_feature)}
        </button>

        <%!-- QA issue 56ee521a — the discoverable "Attack" affordance:
             one button per hostile city `Play`'s own `attackable_cities/2`
             found adjacent to this unit right now. QA issue 7f91cff2 —
             once a given city is `broken` (0 HP), its own button swaps
             to "Move In" and dispatches `queue_move` instead. --%>
        <.attack_city_button
          :for={city <- @attackable_cities}
          city={city}
          unit_id={@unit_id}
        />

        <%!-- QA issue 12bed1e4 "Archers don't have a shoot action" — the
             discoverable "Shoot" affordance: one button per target
             `Play`'s own `PlayView.shoot_targets/5` found in range of
             this Archer right now (barbarian unit, camp, or hostile
             intact city — never a rival player's own unit, matching the
             board's own melee affordances). Gated on `:shoot in @actions`
             too — belt-and-suspenders alongside `shoot_targets` already
             being empty for any non-Archer. --%>
        <.shoot_button
          :for={target <- @shoot_targets}
          :if={:shoot in @actions}
          target={target}
          unit_id={@unit_id}
        />

        <%!-- Issue f7cd10db "still no way to shoot with archer": the live
             "Shoot X" buttons above only exist when a target is in range, so
             a selected Archer with nothing in range showed no shoot
             affordance at all and read as "can't shoot." Always surface the
             capability — a disabled hint when there's nothing to fire at,
             telling the player how ranged attack works. --%>
        <button
          :if={:shoot in @actions and @shoot_targets == []}
          type="button"
          data-test="shoot-no-targets"
          disabled
          class="btn btn-sm btn-outline btn-disabled"
          title="Ranged attack: move within 2 tiles of a barbarian, camp, or hostile city, then a Shoot button appears here."
        >
          Shoot (no target in range)
        </button>
      </div>
    </div>
    """
  end

  attr :kind, :atom, required: true
  attr :unit_id, :any, required: true

  defp build_button(assigns) do
    ~H"""
    <button
      type="button"
      data-test={"build-#{@kind}"}
      phx-click="start_improvement"
      phx-value-unit_id={@unit_id}
      phx-value-kind={@kind}
      class="btn btn-sm btn-outline"
    >
      Build {improvement_label(@kind)}
    </button>
    """
  end

  attr :city, :map, required: true
  attr :unit_id, :any, required: true

  # QA issue 7f91cff2 — once the target city is broken (0 HP, not yet
  # captured), the discoverable button must MOVE the unit onto its
  # tile to occupy it, not re-issue another (now harmless, floor-
  # clamped) attack. Mirrors the `.Board` hook's own `orderMove/1`
  # branch: broken -> `queue_move`, intact -> `attack`.
  defp attack_city_button(%{city: %{broken: true}} = assigns) do
    ~H"""
    <button
      type="button"
      data-test={"move-in-city-#{@city.id}"}
      phx-click="queue_move"
      phx-value-unit_id={@unit_id}
      phx-value-to_tile={@city.tile_id}
      class="btn btn-sm btn-warning"
    >
      Move In {@city.name}
    </button>
    """
  end

  defp attack_city_button(assigns) do
    ~H"""
    <button
      type="button"
      data-test={"attack-city-#{@city.id}"}
      phx-click="attack"
      phx-value-unit_id={@unit_id}
      phx-value-target_city_id={@city.id}
      class="btn btn-sm btn-error"
    >
      Attack {@city.name}
    </button>
    """
  end

  attr :target, :map, required: true
  attr :unit_id, :any, required: true

  # QA issue 12bed1e4 — one button per `PlayView.shoot_targets/5` entry,
  # `phx-value-target_*_id` keyed off `target.kind` so the SAME `"shoot"`
  # event `Play`'s own three-clause dispatch (mirroring `"attack"`'s own
  # `target_unit_id`/`target_camp_id`/`target_city_id` clauses) already
  # expects lands on the right one.
  defp shoot_button(%{target: %{kind: :unit}} = assigns) do
    ~H"""
    <button
      type="button"
      data-test={"shoot-unit-#{@target.id}"}
      phx-click="shoot"
      phx-value-unit_id={@unit_id}
      phx-value-target_unit_id={@target.id}
      class="btn btn-sm btn-error btn-outline"
    >
      Shoot {@target.label}
    </button>
    """
  end

  defp shoot_button(%{target: %{kind: :camp}} = assigns) do
    ~H"""
    <button
      type="button"
      data-test={"shoot-camp-#{@target.id}"}
      phx-click="shoot"
      phx-value-unit_id={@unit_id}
      phx-value-target_camp_id={@target.id}
      class="btn btn-sm btn-error btn-outline"
    >
      Shoot {@target.label}
    </button>
    """
  end

  defp shoot_button(%{target: %{kind: :city}} = assigns) do
    ~H"""
    <button
      type="button"
      data-test={"shoot-city-#{@target.id}"}
      phx-click="shoot"
      phx-value-unit_id={@unit_id}
      phx-value-target_city_id={@target.id}
      class="btn btn-sm btn-error btn-outline"
    >
      Shoot {@target.label}
    </button>
    """
  end

  defp improvement_label(:farm), do: "Farm"
  defp improvement_label(:mine), do: "Mine"
  defp improvement_label(:road), do: "Road"
  defp improvement_label(:pasture), do: "Pasture"
  # Story 927 — `@choppable_feature`'s own two labels, reusing this same
  # helper for the "Chop {label}" button above.
  defp improvement_label(:woods), do: "Woods"
  defp improvement_label(:rainforest), do: "Rainforest"

  # Story 920 — the Fortify badge's own ramp-aware label: 1 is the
  # partial bonus, still "digging in"; 2+ (capped there, see
  # `Simulation.Turn.Movement.advance_fortify/1`) is the full one.
  defp fortify_label(1), do: "Fortifying"
  defp fortify_label(_), do: "Fortified"

  attr :order, :map, default: nil

  defp order_summary(%{order: nil} = assigns) do
    ~H"""
    <p data-test="unit-order" class="text-sm text-base-content/60">
      No orders queued
    </p>
    """
  end

  defp order_summary(%{order: %{status: :interrupted}} = assigns) do
    ~H"""
    <p data-test="unit-order" class="text-sm">
      Moving to tile {@order.target_tile}
      <span data-test="order-interrupted" class="badge badge-warning badge-sm ml-1">
        Interrupted
      </span>
    </p>
    """
  end

  defp order_summary(assigns) do
    ~H"""
    <p data-test="unit-order" class="text-sm">
      Moving to tile {@order.target_tile}
    </p>
    """
  end

  # Owner readout label. A null `player_id` is a barbarian (see
  # `Units.Unit`'s moduledoc — barbarians alone carry no owner); `own`
  # is the viewer's own unit (defaulting true covers the one non-map
  # input path, `Play.apply_unit_panel/3`'s owned-stack `%Unit{}`, which
  # is always the viewer's). Everything else is a rival, shown as a
  # short "Player #<id>" — no email, matching the board rings' rule.
  defp owner_label(unit) do
    cond do
      is_nil(Map.get(unit, :player_id)) -> "Barbarians"
      Map.get(unit, :own, true) -> "You"
      true -> "Player ##{Map.get(unit, :player_id)}"
    end
  end

  defp unit_type_label(:lord), do: "Lord"
  defp unit_type_label(:settler), do: "Settler"
  defp unit_type_label(:worker), do: "Worker"
  defp unit_type_label(:warrior), do: "Warrior"
  # Story 903's Bronze Age melee unit (issue b8f4ce10 — selecting one
  # crashed this component with a FunctionClauseError; a garrisoned
  # bronze_spearman also blocked left-clicking the city under it).
  defp unit_type_label(:bronze_spearman), do: "Bronze Spearman"
  # QA issue da39e50b — the Archery-gated unit; see `BrokenOaths.Cities.
  # Production`'s own moduledoc, "The Archer", and (QA issue 12bed1e4)
  # `BrokenOaths.Combat.Resolver`'s own "Ranged" doc for its `:shoot`.
  defp unit_type_label(:archer), do: "Archer"
  # Enemy units are selectable too — the panel doubles as the threat
  # readout (stats, HP), with every action already type/owner-gated.
  defp unit_type_label(:barbarian_warrior), do: "Barbarian Warrior"
  # Any future unit type degrades to a readable label instead of
  # crashing the LiveView the way :bronze_spearman did before this fix.
  defp unit_type_label(type), do: type |> to_string() |> String.capitalize()
end
