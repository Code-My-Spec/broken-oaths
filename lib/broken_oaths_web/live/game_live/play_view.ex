defmodule BrokenOathsWeb.GameLive.PlayView do
  @moduledoc """
  Pure view-model helpers for `BrokenOathsWeb.GameLive.Play`.

  Everything here is a plain function: given already-fetched game state
  (never a `socket`), it returns a value — a derived assign, a parsed
  param, a formatted error message. No `Phoenix.LiveView` call, no
  `BrokenOaths.Game` write, no process/PubSub interaction. `Play`'s own
  `mount/3`/`handle_event/3`/`handle_info/2` callbacks (and the few
  socket-touching refresh helpers they share, like `refresh_board/1`)
  call these to keep their own bodies thin — this module is the
  "imperative shell, functional core" split (the LiveView analog of the
  `.code_my_spec/knowledge/genserver_decomposition.md` pragdave pattern)
  applied one layer up from the GenServer/domain-model split: `Play`
  owns sockets and side effects, `PlayView` owns derivation.

  Render-only formatting helpers used by exactly one extracted
  component (`GameLive.BoardOverlays`, `GameLive.FeudalTopBar`,
  `GameLive.Modals`) stay private to that component instead of living
  here, mirroring how `GameLive.UnitPanel`/`GameLive.CityPanel` already
  keep their own local label helpers (`unit_type_label/1`,
  `catalog_label/1`, …) rather than centralizing every formatter —
  this module holds only what `Play`'s own callbacks call directly.
  """

  alias BrokenOaths.Cities.{Improvement, Yields}
  alias BrokenOaths.Combat.{CityDefense, Resolver}
  alias BrokenOaths.Game
  alias BrokenOaths.Technology.Research
  alias BrokenOaths.Units.Actions
  alias BrokenOaths.Worlds.{Globe, Regions, Resources, Terrain}

  # Camera aimed at the centroid of the player's own units at spawn
  # (criterion: returning player resumes with the camera on their
  # civilization). Never recomputed after mount — later refreshes must
  # not yank the view out from under the player.
  def camera_on([], _mesh), do: {0.0, 0.0}

  def camera_on(units, mesh) do
    {sx, sy, sz} =
      units
      |> Enum.map(fn unit -> Globe.tile(mesh, unit.tile_id).center end)
      |> Enum.reduce({0.0, 0.0, 0.0}, fn {x, y, z}, {ax, ay, az} -> {ax + x, ay + y, az + z} end)

    case :math.sqrt(sx * sx + sy * sy + sz * sz) do
      norm when norm > 0.0 ->
        {:math.atan2(sy / norm, sx / norm), :math.asin(clamp(sz / norm))}

      _ ->
        {0.0, 0.0}
    end
  end

  defp clamp(z), do: max(-1.0, min(1.0, z))

  # `TechPanel`'s `phx-value-tech` arrives as a string — `Research`'s
  # own catalog is a fixed, compile-time set of atoms, so
  # `String.to_existing_atom/1` is always safe for a legitimate tech
  # name (same safety argument `WorldServer.player_research_map/1`
  # already makes for `banked_science`'s keys); anything else becomes
  # an atom `Research.set_research/2` is guaranteed to refuse as
  # `:invalid_tech`.
  def parse_tech(tech) when is_atom(tech), do: tech

  def parse_tech(tech) when is_binary(tech) do
    String.to_existing_atom(tech)
  rescue
    ArgumentError -> :invalid_tech
  end

  # Bonus/strategic-resource billboards (stories 905/911) for every
  # currently KNOWN tile — every bonus resource is visible from the
  # first look, unconditionally (criterion 7649), so this reads off
  # the very same `known` set `tile_row/3` already iterates rather
  # than a separate fog-gated `Game` read the way camps/improvements
  # need. Copper (story 911's strategic resource) is the one
  # exception: `visible_resource/3` filters it out of a tile that IS
  # otherwise known until the viewing player has completed Bronze
  # Working (`Research.copper_revealed?/1`) — see that helper's own
  # doc for the full reveal rule.
  def known_resources(known, world, player_research) do
    for tile_id <- known,
        resource = visible_resource(world, tile_id, player_research),
        resource != nil,
        do: %{tile_id: tile_id, kind: resource}
  end

  # Story 911 — the one reveal-tech exception to "resources are visible
  # unconditionally" (criterion 7649): Copper stays invisible to a
  # player until they've completed Bronze Working, mirroring Civ 6's
  # own "Bronze Working reveals Iron" convention. Every OTHER resource
  # kind passes straight through unchanged.
  # `BrokenOaths.Worlds.Resources.at/2` itself places Copper on the map
  # unconditionally (it has no concept of a viewing player) — this is
  # the ONE place that ground truth gets filtered down to what a
  # specific player currently knows, shared by both the `"game:
  # resources"` push (`known_resources/3` above) and the `select_tile`
  # handler's own single-tile read below, so the two surfaces can never
  # disagree about whether a given player has seen Copper yet.
  def visible_resource(world, tile_id, player_research) do
    case Resources.at(world, tile_id) do
      :copper -> if Research.copper_revealed?(player_research), do: :copper, else: nil
      other -> other
    end
  end

  # The board only needs enough to place and label a billboard —
  # territory/queue/food stay in the CityPanel assign, not the client.
  # `hostile: false` — the client's `.Board` hook uses this to decide
  # left-click select-vs-ignore and right-click move-vs-attack (QA
  # issue 56ee521a).
  def city_marker(city),
    do: city |> Map.take([:id, :name, :tile_id, :size]) |> Map.put(:hostile, false)

  # QA issue 56ee521a — the enemy-city sibling of `city_marker/1`,
  # `hostile: true`. `:broken` (QA issue 7f91cff2) rides straight
  # through from `Game.enemy_cities_visible_to/2`'s own `Siege.broken?/1`
  # read — the `.Board` hook's `orderMove/1` needs it to route a
  # right-click at a 0-HP hostile city to `queue_move` (occupy) instead
  # of another `attack`.
  def enemy_city_marker(city),
    do:
      city
      |> Map.take([:id, :name, :tile_id, :size, :hp, :broken])
      |> Map.put(:hostile, true)

  # "Grassland Hills · Woods" — base, then relief when not flat, then
  # feature when present.
  def terrain_label(%Terrain{base: base, relief: relief, feature: feature}) do
    [base, relief != :flat && relief, feature]
    |> Enum.filter(& &1)
    |> Enum.map_join(" · ", &(&1 |> to_string() |> String.capitalize()))
  end

  # Compact row for the client painter:
  # [id, color, decor, tex, cx, cy, cz, corner1x, corner1y, corner1z, ...]
  def tile_row(tile_id, mesh, terrain_map) do
    tile = Globe.tile(mesh, tile_id)
    terrain = Map.get(terrain_map, tile_id)
    {cx, cy, cz} = tile.center
    corners = Enum.flat_map(tile.corners, fn {x, y, z} -> [round4(x), round4(y), round4(z)] end)

    [
      tile.id,
      Terrain.color(terrain),
      Terrain.decor(terrain),
      Terrain.texture(terrain),
      round4(cx),
      round4(cy),
      round4(cz) | corners
    ]
  end

  defp round4(f), do: Float.round(f, 4)

  # Story 927 — the client board painter's own `terrain_map` (`Play`'s
  # `mount/3` assign) is the raw, seed-derived
  # `Generator.generate_terrain_map/2` output; unlike every server-side
  # gameplay read (which calls `Regions.terrain/3` fresh, per tile),
  # this one map is computed ONCE and reused across every `push_board_state/1`
  # call, so the chop overlay has to be applied here instead — a chopped
  # tile's own `%Terrain{}` entry loses its `feature` so `Terrain.color/1`/
  # `decor/1`/`texture/1` (what `tile_row/3` below actually reads) stop
  # rendering it as Woods/Rainforest the instant it's chopped.
  @spec overlay_cleared_features(%{integer() => Terrain.t()}, MapSet.t()) :: %{
          integer() => Terrain.t()
        }
  def overlay_cleared_features(terrain_map, cleared_features) do
    Enum.reduce(cleared_features, terrain_map, fn tile_id, acc ->
      Map.update(acc, tile_id, nil, &%{&1 | feature: nil})
    end)
  end

  # The mesh tile whose center is nearest the given unit-sphere point
  # (max dot product). Linear over the mesh — ~29k tiles at f=54, a few
  # ms once per right-click.
  def nearest_tile(mesh, {x, y, z}) do
    {id, _tile} =
      Enum.max_by(mesh.tiles, fn {_id, tile} ->
        {cx, cy, cz} = tile.center
        cx * x + cy * y + cz * z
      end)

    id
  end

  def order_error_message(:not_owner), do: "You don't control that unit."
  def order_error_message(:occupied), do: "Another unit already holds that tile."
  def order_error_message(:impassable), do: "That terrain can't be crossed."
  def order_error_message(:unreachable), do: "There's no path there."

  # Playtest issue 50a0c866 — `"cancel_move"`'s own refusal when the
  # unit has nothing queued to cancel.
  def order_error_message(:no_order), do: "That unit has no order to cancel."

  def order_error_message(_other), do: "That order can't be queued."

  def combat_error_message(:not_owner), do: "You don't control that unit."
  def combat_error_message(:invalid_target), do: "That target no longer exists."
  def combat_error_message(:out_of_movement), do: "That unit has no movement left to attack."
  def combat_error_message(:not_adjacent), do: "That target is out of range."

  def combat_error_message(:not_hostile),
    do: "Stone Age players cannot fight each other — only barbarians can be attacked."

  def combat_error_message(:own_city), do: "You can't attack your own city."

  def combat_error_message(:not_military),
    do: "Only military units can lay siege to a city — civilians cannot besiege."

  # QA issue 12bed1e4 — the ranged "shoot" surface's own two refusal
  # reasons `attack/4`'s melee gate never produces.
  def combat_error_message(:not_archer), do: "Only an Archer can shoot."
  def combat_error_message(:out_of_range), do: "That target is out of shooting range."

  # Story 920 — the Fortify stance's own refusal reason: only a
  # `:defend`-capable unit (every player-commandable type — never a
  # barbarian) can brace.
  def combat_error_message(:not_fortifiable), do: "That unit can't fortify."

  # Playtest issue 50a0c866 — `"unfortify"`'s own refusal when the unit
  # isn't currently fortified at all.
  def combat_error_message(:not_fortified), do: "That unit isn't fortified."

  def combat_error_message(_other), do: "That attack can't be ordered."

  def parse_agenda("restore"), do: :restore
  def parse_agenda("usurp"), do: :usurp
  def parse_agenda("kingmaker"), do: :kingmaker
  def parse_agenda("merchant_prince"), do: :merchant_prince
  def parse_agenda(_other), do: :invalid

  # `"50"` (a 0-100 percentage string, the tribute-rate control's own
  # scale) -> `0.5` (the `Vassalage.tribute_rate` fraction).
  def parse_percent(percent) when is_binary(percent) do
    case Float.parse(percent) do
      {value, _rest} -> value / 100
      :error -> 0.0
    end
  end

  def parse_percent(percent) when is_number(percent), do: percent / 100

  # `"0.5"` (the pledged-share control's own scale, already a fraction)
  # -> `0.5`.
  def parse_fraction(fraction) when is_binary(fraction) do
    case Float.parse(fraction) do
      {value, _rest} -> value
      :error -> 0.0
    end
  end

  def parse_fraction(fraction) when is_number(fraction), do: fraction

  # Story 919 — `"reparations_gold"`'s own optional scale: blank/missing
  # reads as no reparations at all, never a crash on an empty string.
  def parse_optional_int(nil), do: nil
  def parse_optional_int(""), do: nil
  def parse_optional_int(value) when is_integer(value), do: value

  def parse_optional_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _rest} -> int
      :error -> nil
    end
  end

  # Which improvement kinds a worker could start on the tile it's
  # standing on right now — same terrain gate `WorldServer` enforces
  # (`Regions.tile_class/2` == :land, then `Improvement.allowed?/2`),
  # computed here purely so `UnitPanel` only ever offers legal actions
  # (story 882, criterion 7482: Farm is never offered on hills/forest).
  # The dig under the selected worker's feet, if one is in progress —
  # the unit panel shows it as live progress (issue b5cc4ae9: silent
  # success on Build read as a dead button).
  def worker_current_dig(improvements, %{type: :worker, tile_id: tile_id}),
    do: Enum.find(improvements, &(&1.tile_id == tile_id and &1.status == :building))

  def worker_current_dig(_improvements, _unit), do: nil

  def worker_allowed_improvements(_world, nil, _player_research, _cleared_features), do: []

  # QA issue 12bed1e4's own "consult Units.Actions where it cleanly
  # can" refactor: the coarse "is this unit's TYPE even eligible for
  # `:build_improvement` at all" gate now reads off `Units.Actions.
  # available/1` instead of a bare `type != :worker` guard — behavior-
  # preserving (only `:worker` ever carries `:build_improvement`), but
  # one fewer place that has to independently know which type builds.
  # The REAL, state-aware rule (which improvement KINDS this worker's
  # own tile supports right now) stays right here — `Units.Actions`
  # only answers the type-level question. `cleared_features` (story
  # 927) is `Game.cleared_features/1`'s own set — reading terrain
  # cleared-aware (`Regions.terrain/3`) is what makes a chopped
  # grassland/plains tile Farm-offerable the instant it's chopped.
  def worker_allowed_improvements(world, unit, player_research, cleared_features) do
    if :build_improvement in Actions.available(unit) do
      compute_allowed_improvements(world, unit, player_research, cleared_features)
    else
      []
    end
  end

  defp compute_allowed_improvements(world, %{tile_id: tile_id}, player_research, cleared_features) do
    if Regions.tile_class(world, tile_id) == :land do
      terrain = Regions.terrain(world, tile_id, cleared_features)
      resource = Resources.at(world, tile_id)

      # `:mine` uses the resource-aware gate (QA issue 5a30ad3f — Copper
      # guaranteed near spawn can land off-Hills); Farm stays
      # terrain-only. `:road` stays terrain-wide-open but now ALSO
      # needs The Wheel researched (playtest issue eb5ec4f9) — mirrors
      # `pasture_offered?/3` below, just folded into this same filter
      # instead of appended after it.
      terrain_kinds =
        Enum.filter([:farm, :mine, :road], fn
          :mine -> Improvement.mine_allowed?(terrain, resource)
          :road -> road_enabled?(player_research)
          kind -> Improvement.allowed?(kind, terrain)
        end)

      if pasture_offered?(world, tile_id, player_research) do
        terrain_kinds ++ [:pasture]
      else
        terrain_kinds
      end
    else
      []
    end
  end

  # Pasture (story 905, criterion 7648) only ever renders once the tile
  # carries an animal resource AND the selecting player has researched
  # Animal Husbandry — mirrors the terrain gate above, just sourced from
  # the resource layer + research instead of `Improvement.allowed?/2`.
  defp pasture_offered?(world, tile_id, player_research) do
    Improvement.resource_allowed?(Resources.at(world, tile_id)) and
      pasture_enabled?(player_research)
  end

  defp pasture_enabled?(nil), do: false
  defp pasture_enabled?(player_research), do: Research.pasture_enabled?(player_research)

  # Road (playtest issue eb5ec4f9) only ever renders once the selecting
  # player has researched The Wheel — mirrors `pasture_enabled?/1` just
  # above.
  defp road_enabled?(nil), do: false
  defp road_enabled?(player_research), do: Research.road_enabled?(player_research)

  # Story 927 "Workers chop woods and rainforest" — whether `UnitPanel`
  # should offer a "Chop" button for `unit` right now: `nil` (nothing to
  # offer) unless the worker's own tile carries a Woods/Rainforest
  # feature (cleared-aware — an already-chopped tile has nothing left),
  # the tile sits inside one of `cities` (`Game.player_cities/2`'s own
  # result — always the VIEWER's own, so a foreign unit's panel never
  # offers this), the feature's own tech is researched, and the worker
  # still has a build charge. Mirrors `worker_current_dig/2`'s own
  # "compute the real, state-aware answer here so the button never lies"
  # posture — the one legality check this deliberately leaves to the
  # real `chop/3` command (rather than pre-filtering) is the hostile-
  # co-occupant refusal, the same narrow edge case every other button in
  # this panel leaves to its own command's error toast.
  @spec worker_choppable_feature(map(), map() | nil, [map()], map() | nil, MapSet.t()) ::
          Improvement.chop_feature() | nil
  def worker_choppable_feature(_world, nil, _cities, _player_research, _cleared_features), do: nil

  def worker_choppable_feature(world, unit, cities, player_research, cleared_features) do
    if :chop in Actions.available(unit) and Regions.tile_class(world, unit.tile_id) == :land do
      world
      |> Regions.terrain(unit.tile_id, cleared_features)
      |> Map.fetch!(:feature)
      |> chop_offered(cities, unit, player_research)
    else
      nil
    end
  end

  defp chop_offered(feature, cities, unit, player_research)
       when feature in [:woods, :rainforest] do
    if owns_tile?(cities, unit) and chop_research_enabled?(feature, player_research) and
         Map.get(unit, :charges, 3) > 0 do
      feature
    else
      nil
    end
  end

  defp chop_offered(_feature, _cities, _unit, _player_research), do: nil

  defp owns_tile?(cities, unit),
    do: Enum.any?(cities, &(&1.player_id == unit.player_id and unit.tile_id in &1.territory))

  defp chop_research_enabled?(_feature, nil), do: false
  defp chop_research_enabled?(:woods, pr), do: Research.chop_woods_enabled?(pr)
  defp chop_research_enabled?(:rainforest, pr), do: Research.chop_rainforest_enabled?(pr)

  # Territory tiles `CityPanel` may offer a "Work" action for: not the
  # always-free center, not already worked, and workable terrain — the
  # same gate `WorldServer.validate_assign/3` enforces. `CityPanel` has
  # no world/terrain access of its own (purely presentational), so this
  # is computed here whenever the selected city changes.
  def assignable_tiles(_world, nil), do: []

  def assignable_tiles(world, city) do
    worked = MapSet.new(city.worked_tiles)

    city.territory
    |> Enum.reject(&(&1 == city.tile_id or MapSet.member?(worked, &1)))
    |> Enum.filter(&Yields.workable?(Regions.terrain(world, &1)))
  end

  # Story 921 — the Galley's own `:coastal?` opt, mirroring
  # `assignable_tiles/2`'s own "this component has no world/terrain
  # access of its own" reason for arriving pre-computed:
  # `GameLive.CityPanel` reads this straight off `BrokenOaths.Cities.
  # Production.coastal?/2`'s same rule (at least one adjacent
  # `:coastal_water` tile), just without that module's own full
  # tick-`state` — `Play` only ever has `world` + the selected `city`.
  def coastal?(_world, nil), do: false

  def coastal?(world, city) do
    world
    |> Regions.adjacent_tiles(city.tile_id)
    |> Enum.any?(&(Regions.tile_class(world, &1) == :coastal_water))
  end

  # QA issue 56ee521a — the "surface an attack affordance" half of the
  # fix: enemy cities adjacent to the CURRENTLY SELECTED unit, but only
  # once that unit is a military type (`CityDefense.military?/1` — a
  # civilian can no more attack a city through this button than through
  # `Siege.validate_siege/3` itself would allow). Powers `UnitPanel`'s
  # own per-city button — "Attack" for an intact city, wired to the
  # existing `"attack"`/`target_city_id` handler, or "Move In" once the
  # city is `broken` (QA issue 7f91cff2), wired to `"queue_move"`/
  # `to_tile` instead — the discoverable-button sibling to the
  # right-click gesture the `.Board` hook's own `orderMove/1` already
  # offers (and, since 7f91cff2, already routes the same way).
  def attackable_cities(_world, nil, _enemy_cities), do: []

  def attackable_cities(world, unit, enemy_cities) do
    if CityDefense.military?(unit) do
      adjacent = MapSet.new(Regions.adjacent_tiles(world, unit.tile_id))

      enemy_cities
      |> Enum.filter(&MapSet.member?(adjacent, &1.tile_id))
      |> Enum.map(&Map.take(&1, [:id, :name, :tile_id, :broken]))
    else
      []
    end
  end

  # QA issue 12bed1e4 "Archers don't have a shoot action" — the
  # discoverable "Shoot" affordance's own target list: every barbarian
  # unit, barbarian camp, and (once `Game.feudal_enabled?/0`) hostile
  # INTACT city within `Resolver.shoot_range/0` hexes of a SELECTED
  # Archer right now — `Resolver.in_shoot_range?/3`'s raw mesh-adjacency
  # distance, never a land-path walk (an arrow doesn't path around
  # terrain the way a marching unit does). Mirrors `attackable_cities/3`'s
  # own "compute here, `Play` has the world/fog access `UnitPanel`
  # doesn't" reasoning, widened to the three target kinds `Combat.
  # Resolver.shoot/4`/`Combat.Camps.shoot_camp/4`/`Combat.Siege.
  # shoot_city/4` themselves support. Gated on `:shoot in Units.Actions.
  # available/1` (only an Archer ever carries it) rather than a bare
  # `unit.type == :archer` check — this module's own "consult Units.
  # Actions where it cleanly can" refactor (QA issue 12bed1e4).
  # `units`/`camps`/`enemy_cities` are already fog-filtered board reads
  # (`Game.units_visible_to/2`/`Game.camps_visible_to/2`/`Game.
  # enemy_cities_visible_to/2`) — a target this player can't see never
  # reaches this filter in the first place. A rival PLAYER's own unit
  # is deliberately never offered here (melee's own board affordances
  # don't surface one either — see `Play`'s `.Board` hook's own
  # `orderMove/1`): the narrow war/rebellion/protection-pact PvP
  # exceptions `Resolver.pvp_target_allowed?/3` recognizes stay reachable
  # by pushing `"shoot"`/`target_unit_id` directly, exactly like
  # melee's own `"attack"`/`target_unit_id` today.
  def shoot_targets(_world, nil, _units, _camps, _enemy_cities), do: []

  def shoot_targets(world, unit, units, camps, enemy_cities) do
    if :shoot in Actions.available(unit) do
      unit_targets =
        units
        |> Enum.filter(&(&1.type == :barbarian_warrior and shoot_in_range?(world, unit, &1)))
        |> Enum.map(&%{kind: :unit, id: &1.id, label: "Barbarian Warrior", tile_id: &1.tile_id})

      camp_targets =
        camps
        |> Enum.filter(&shoot_in_range?(world, unit, &1))
        |> Enum.map(&%{kind: :camp, id: &1.id, label: "Camp", tile_id: &1.tile_id})

      city_targets =
        enemy_cities
        |> Enum.filter(&(not &1.broken and shoot_in_range?(world, unit, &1)))
        |> Enum.map(&%{kind: :city, id: &1.id, label: &1.name, tile_id: &1.tile_id})

      unit_targets ++ camp_targets ++ city_targets
    else
      []
    end
  end

  defp shoot_in_range?(world, unit, target),
    do: Resolver.in_shoot_range?(world, unit.tile_id, target.tile_id)

  def parse_id(nil), do: nil
  def parse_id(""), do: nil
  def parse_id(id) when is_integer(id), do: id
  def parse_id(id) when is_binary(id), do: String.to_integer(id)

  # QA issue d403faa6: this player's own units currently standing on
  # `tile_id`, sorted into a stable (by id) order — the "stack"
  # `next_unit_in_stack/2` cycles through on repeat clicks. Reads fresh
  # off `Game.player_units/2` (already scoped to this player's own
  # units, unlike `socket.assigns.units`'s fog-filtered — and
  # ownership-blind — entries) rather than the pushed board state, the
  # same authoritative-read pattern every other command handler in this
  # module already uses.
  def owned_stack_on_tile(world, user, tile_id) do
    world
    |> Game.player_units(user)
    |> Enum.filter(&(&1.tile_id == tile_id))
    |> Enum.sort_by(& &1.id)
  end

  # Pure cycling rule, kept separate from the `Game.player_units/2` read
  # above so it's trivially unit-testable. Repeated clicks on one tile
  # cycle through everything selectable there: each of the player's own
  # units in `owned_stack_on_tile/3` order, THEN (QA issue adc8c79e) the
  # player's own city on that tile — so a unit parked on a city no longer
  # hides it. Given the current selection (`current_unit_id` when a unit
  # is selected, `current_city_id` when a city is, both possibly on a
  # different tile), returns the selection AFTER it, wrapping past the
  # last back to the first. `:none` when the tile has neither an owned
  # stack nor an owned city — the caller then falls back to the plain
  # by-id unit lookup (foreign unit, or a tile_id-less test click),
  # unchanged from before.

  def next_tile_selection([], nil, _current_unit_id, _current_city_id), do: :none

  def next_tile_selection(stack, city, current_unit_id, current_city_id) do
    cycle = Enum.map(stack, &{:unit, &1}) ++ if(city, do: [{:city, city}], else: [])

    idx =
      Enum.find_index(cycle, fn
        {:unit, u} -> u.id == current_unit_id
        {:city, c} -> c.id == current_city_id
      end)

    case idx do
      nil -> List.first(cycle)
      i -> Enum.at(cycle, rem(i + 1, length(cycle)))
    end
  end

  def city_error_message(:not_owner), do: "You don't control that city."
  def city_error_message(:not_settler), do: "Only a settler can found a city."
  def city_error_message(:invalid_terrain), do: "A city can't be founded there."
  def city_error_message(:too_close), do: "Too close to an existing city."
  def city_error_message(:invalid_item), do: "That can't be queued."
  def city_error_message(:size_one), do: "This city needs a second citizen first."
  def city_error_message(:not_found), do: "That item is no longer queued."
  def city_error_message(:invalid_name), do: "Enter a name for the city."
  def city_error_message(:not_worked), do: "That tile isn't currently worked."
  def city_error_message(:invalid_tile), do: "The city center can't be reassigned."
  def city_error_message(:not_territory), do: "That tile isn't part of the city."
  def city_error_message(:already_worked), do: "That tile already has a citizen."
  # Story 911 — the Bronze Spearman's Copper access gate, distinct from
  # the plain `:locked` a missing Bronze Age reports (unchanged, story
  # 903) — mirrors the exact "Requires Copper" wording
  # `GameLive.CityPanel`'s own always-visible requirement note already
  # renders (criterion 7708), so the toast and the production menu
  # never disagree about the reason.
  def city_error_message(:copper_required), do: "Requires Copper."

  def city_error_message(:size_exceeded),
    do: "This city has no idle citizen — unassign a worked tile first."

  def city_error_message(_other), do: "That action can't be completed."

  def improvement_error_message(:not_owner), do: "You don't control that unit."
  def improvement_error_message(:not_worker), do: "Only a worker can build improvements."

  def improvement_error_message(:invalid_improvement),
    do: "That improvement isn't allowed there."

  def improvement_error_message(:invalid_terrain),
    do: "That terrain won't support that improvement."

  def improvement_error_message(:occupied_improvement),
    do: "This tile already has a completed improvement."

  def improvement_error_message(:no_active_build),
    do: "There's no build in progress here to cancel."

  def improvement_error_message(_other), do: "That improvement can't be started."

  # Story 927 "Workers chop woods and rainforest".
  def chop_error_message(:not_owner), do: "You don't control that unit."
  def chop_error_message(:not_worker), do: "Only a worker can chop."
  def chop_error_message(:not_choppable), do: "There's nothing to chop here."
  def chop_error_message(:not_territory), do: "That tile isn't inside your own borders."
  def chop_error_message(:tech_locked), do: "You haven't researched the tech for that yet."
  def chop_error_message(:no_charges), do: "This worker has no build charges left."
  def chop_error_message(:enemy_present), do: "An enemy unit holds this tile."
  def chop_error_message(_other), do: "That can't be chopped."

  # Story 929 "Build road to a destination".
  def road_error_message(:not_owner), do: "You don't control that unit."
  def road_error_message(:not_worker), do: "Only a worker can build roads."
  def road_error_message(:tech_locked), do: "You haven't researched The Wheel yet."
  def road_error_message(:invalid_tile), do: "That's not a valid destination."
  def road_error_message(:not_territory), do: "That tile isn't inside your own borders."
  def road_error_message(:unreachable), do: "There's no route there."
  def road_error_message(_other), do: "That road can't be ordered."

  def bank_error_message(:insufficient_gold), do: "You can't afford that upgrade yet."
  def bank_error_message(_other), do: "The bank refused that action."

  # QA issue bd93cc0a — production-stewardship + emergency-defend error
  # surface, same "transient, connection-only" status `city_error`/
  # `bank_error` already have.
  def steward_error_message(:not_eligible), do: "You aren't eligible to steward them."
  def steward_error_message(:owner_online), do: "They're back online — stewardship has ended."
  def steward_error_message(:not_found), do: "That city isn't theirs to steward."
  def steward_error_message(:not_constructive), do: "That build isn't on the steward whitelist."
  def steward_error_message(:invalid_item), do: "That can't be queued."
  def steward_error_message(:size_one), do: "This city needs a second citizen first."
  def steward_error_message(:already_built), do: "They've already built one."
  def steward_error_message(:locked), do: "They haven't unlocked that yet."
  def steward_error_message(:copper_required), do: "That build requires Copper access."
  def steward_error_message(:not_owner), do: "That unit isn't theirs to command."

  def steward_error_message(:not_under_attack),
    do: "They aren't under attack — there's nothing to defend against right now."

  def steward_error_message(:unreachable), do: "That tile isn't reachable."
  def steward_error_message(:feudal_disabled), do: "Stewardship isn't available right now."
  def steward_error_message(_other), do: "That steward action was refused."
end
