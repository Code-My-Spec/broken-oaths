defmodule BrokenOaths.Game.Turn do
  @moduledoc """
  Pure turn pipeline — `tick/1` resolves every queued move order
  simultaneously and advances the turn counter. No processes, no `Repo`
  calls: this is the functional core the `WorldServer` (the imperative
  shell) holds in memory and drives once per turn boundary.

  ## Canonical tick-state contract

  This is the shape `WorldServer` must hold and pass to `tick/1`; every
  other functional-core module (`Spawner`, `Visibility`, `Yields`,
  `Production`) is written against the same shape.

      state :: %{
        world: %Worlds.World{},
        turn: non_neg_integer(),
        units: %{unit_id => %{
          id: unit_id,
          player_id: player_id,
          type: :lord | :settler | :warrior | :worker,
          tile_id: tile_id,
          hp: non_neg_integer(),
          max_hp: pos_integer(),
          movement: non_neg_integer(),
          max_movement: non_neg_integer(),
          charges: non_neg_integer()
        }},
        orders: %{unit_id => %{
          kind: :move,
          path: [tile_id],
          status: :pending | :interrupted
        }},
        players: %{player_id => %{
          id: player_id,
          user_id: term(),
          region_id: term(),
          gold: non_neg_integer()
        }},
        explored: %{player_id => MapSet.t(tile_id)},
        cities: %{city_id => %{
          id: city_id,
          player_id: player_id,
          tile_id: tile_id,
          name: String.t(),
          size: pos_integer(),
          food: non_neg_integer(),
          hp: non_neg_integer(),
          territory: [tile_id],
          worked_tiles: [tile_id],
          queue: [%{id: term(), type: :settler | :worker | :warrior,
                    banked: non_neg_integer(), cost: pos_integer()}]
        }},
        improvements: %{tile_id => %{
          tile_id: tile_id,
          kind: :farm | :mine | :road,
          progress: non_neg_integer(),
          status: :building | :complete,
          builder_unit_id: unit_id | nil
        }},
        pending_heirs: %{player_id => non_neg_integer()},
        camps: %{camp_id => %{
          id: camp_id,
          tile_id: tile_id,
          hp: non_neg_integer(),
          spawn_counter: non_neg_integer(),
          destroyed_at: term() | nil
        }}
      }

  `charges` (story 882 playtest update, issue 1caa87e9) is read
  defensively via `Map.get(unit, :charges, 3)` everywhere this module
  reads it — most of this module's own pre-existing unit tests build a
  hand-written unit map with no `:charges` key at all, and a unit that
  predates the charges migration would likewise have none in a raw
  hand-built map, so the same "3, same as a freshly spawned worker"
  default the DB migration itself uses applies here too.

  `pending_heirs` (story 896) is read defensively via
  `Map.get(state, :pending_heirs, %{})` — a scheduled-heir arrival turn
  per player, written by `WorldServer`'s combat handler on a lord's
  death, resolved by this module's own "heir succession" tick phase.
  It's the one field in this contract every other functional-core
  module (and most of this module's own tests, built before it
  existed) can safely omit; nothing breaks if it's absent.

  `camps` (story 892) is read the same defensive way, via
  `Map.get(state, :camps, %{})` — every barbarian camp on the board,
  written once at a player's first founding (`WorldServer`, not this
  module) and advanced every tick by this module's own "camp spawn
  loop" phase. A unit belonging to a camp (a barbarian warrior) carries
  the camp's id as `camp_id` in its own map, read the same defensive
  way (`Map.get(unit, :camp_id)`) since ordinary player units never set
  it.

  `player_research` (story 902) is read the same defensive way, via
  `Map.get(state, :player_research, %{})` — one
  `BrokenOaths.Game.Research.player_research()` map per player, created
  at join (`WorldServer`, not this module) and advanced every tick by
  this module's own "science accrual" phase (below). A player with no
  entry is treated as `BrokenOaths.Game.Research.new/0` for that tick
  only — most of this module's own tests build a state map without
  this key.

  `unit_id`, `player_id`, and `city_id` are opaque keys (Ecto primary
  keys in production); `tile_id` is a `Worlds.Globe` mesh tile id.

  ## Movement resolution

  At the start of a tick every unit's `movement` resets to its
  `max_movement`. Orders with `status: :pending` then resolve in lockstep
  rounds: one step per round per still-active mover, movers processed in
  ascending unit id each round for determinism. A step is blocked when its
  destination is occupied at that instant — either by a unit that never
  moves this round or by a unit that claimed the tile earlier in the same
  round. A blocked mover halts for the rest of the tick: its order becomes
  `:interrupted` and its remaining path (including the blocked step) is
  preserved untouched. `:interrupted` orders are not retried until
  something re-queues them — that is outside this module. A path fully
  consumed within the tick is an arrival: the order is removed entirely.

  ## City loop phases

  After movement resolves, `tick/1` runs the city-loop phases in a
  fixed order, each a thin pass over `state.cities`/`state.improvements`
  delegating the real math to `Yields` and `Production`:

    1. improvement progress -- ticks `Improvement.duration/1` forward
       for any improvement whose declared builder is still standing on
       its tile. A completion of a Farm or Mine spends the builder's
       build charge (story 882 playtest update, issue 1caa87e9); a
       worker that spends its last charge is expended and removed from
       `state.units` in this same phase. Roads (and, pending a PM call,
       Pasture) are charge-exempt.
    2. production accrual -- `Production.accrue/3` (flat base plus
       worked-tile production) into each city's current queue item, EXCEPT
       a pillaged city still serving its `CityDefense.production_halted?/2`
       freeze (story 895) -- that city's queue simply doesn't move this
       boundary; its banked progress is untouched, not lost.
    3. completions/spawn placement -- `Production.complete/3`; a
       completed item with nowhere to land simply waits. Successful
       spawns come back as `{:unit_spawned, spawn_event}` events --
       this module never allocates a real unit id itself. A settler
       completion here already docks its city's population
       (`Production.apply_pop_cost/3`) -- `resolve_completions/1`
       tracks every city id that paid that cost THIS tick so phase 5
       (growth, below) can skip it (issue 63300098).
    3b. camp spawn loop (story 892) -- `Camps.advance/2` per camp,
       threading the SAME "claimed this tick" occupied-tile set city
       completions just built (a camp spawn can't land on a tile a
       city completion claimed this same tick, and vice versa). A
       ready camp below its 2-warrior cap with a free landing tile
       (its own tile, else an adjacent land tile) spawns one barbarian
       warrior -- also a `{:unit_spawned, spawn_event}` event, now
       carrying `camp_id` -- and resets its counter via
       `Camps.spawned/1`; blocked or above-cap camps just keep
       counting.
    3c. barbarian AI loop (story 893) -- every EXISTING camp-spawned
       warrior (`Map.get(unit, :camp_id)` set; a warrior spawned earlier
       THIS SAME tick by phase 3b is not in `state.units` yet and
       simply waits for the next boundary) gets exactly one decision
       from `BarbarianAI.decide/6`: attack an adjacent player unit
       (`Combat.resolve/3`, same simultaneous-exchange math a player's
       own attack uses -- a barbarian dying pays its killer's owner
       `BarbarianAI.bounty_gold/0`, and a lord dying schedules an heir
       exactly like `WorldServer`'s own combat handler does), step one
       hex toward the nearest in-range target, or roam near its camp.
       `BarbarianAI.decide/6` itself never targets a city directly --
       "adjacent to a city, nothing else to attack" is still reported
       as `:hold` (see that module's own doc and its own committed unit
       test) -- so THIS phase is what turns a `:hold` next to a city
       into a real assault (story 895): `CityDefense.resolve_attack/4`
       against that city, applied through `CityDefense.take_damage/3`
       (folding in `CityDefense.pillage/2` the instant HP hits 0), with
       every city a barbarian actually struck THIS tick tracked so
       phase 3d below knows to skip its regen. A true hold (nothing
       adjacent at all) is unchanged. Entering a tile with a `:complete`
       improvement pillages it (`Improvement.pillage/1`). Warriors
       resolve in ascending unit id order, threading the tick's
       occupied-tile set so two barbarians never collide.
    3d. city regeneration (story 895) -- every city NOT struck by
       phase 3c's own barbarian-AI assault this tick regains
       `CityDefense.regen_per_boundary/0` HP, capped at
       `CityDefense.max_hp/0`. A city hit through `WorldServer`'s
       immediate, out-of-tick "attack" surface (this story's own spec
       convention of a stand-in real player) never suppresses this --
       only an attack that's part of THIS tick's own AI phase does, so
       the very next boundary after an out-of-band hit still regens.
    4. food accrual -- `Yields.accrue_food/3`.
    5. growth -- `Yields.grow/3`, at most once per city per tick, and
       never for a city that already paid a settler's population cost
       in phase 3 THIS SAME tick (issue 63300098) -- otherwise a
       well-fed city crossing its (now one-lower, post-pop-cost) next
       growth threshold in the very same boundary silently refunds the
       settler's cost, and `game_cities.size` never visibly drops.
    6. healing -- a unit that spent no movement this tick heals: 15 HP
       garrisoned on its own city's tile, 10 HP anywhere else in its
       owner's territory, 0 outside it.
    7. heir succession -- any player whose lord died (scheduled by
       `BrokenOaths.Game.WorldServer`'s combat handler into
       `state.pending_heirs`, `%{player_id => arrival_turn}`, not part
       of this module's own canonical state contract above — read
       defensively via `Map.get(state, :pending_heirs, %{})` since most
       of this module's own tests build a state map without that key)
       whose `arrival_turn` has now passed gets a fresh Lord at their
       capital (their oldest city, by id) this tick, plus a
       `{:lineage_continued, user_id, message}` event so only that
       player is notified (story 896, criterion 7573). A player with no
       surviving city simply never gets their heir back — an edge case
       no story covers.
    8. science accrual (story 902) -- every player's science income
       this tick (`Research.science_per_turn/1`, `2 * size` summed over
       every city they own, size being the SAME field growth/production
       already treat as population) banks toward their
       `current_research` (`Research.accrue_and_complete/2`). A tech
       that reaches its cost completes automatically: it moves into
       `completed_techs`, `current_research` clears (the player must
       pick a next tech themselves), and a
       `{:tech_completed, user_id, tech}` event fires so only that
       player is notified. A player with `current_research: nil` simply
       banks nothing this tick — the same no-op
       `Research.accrue/2` already documents.

  Cities are always processed in ascending id order within a phase, so
  contested outcomes (two cities eligible for the same growth tile, two
  production completions racing for a tile) resolve deterministically.
  """

  alias BrokenOaths.Game.BarbarianAI
  alias BrokenOaths.Game.Camps
  alias BrokenOaths.Game.CityDefense
  alias BrokenOaths.Game.Combat
  alias BrokenOaths.Game.Improvement
  alias BrokenOaths.Game.Production
  alias BrokenOaths.Game.Research
  alias BrokenOaths.Game.Visibility
  alias BrokenOaths.Game.Yields
  alias BrokenOaths.Worlds.Regions

  @type unit_id :: term()
  @type player_id :: term()
  @type city_id :: term()
  @type tile_id :: non_neg_integer()

  @type unit :: %{
          optional(:charges) => non_neg_integer(),
          id: unit_id(),
          player_id: player_id(),
          type: :lord | :settler | :warrior | :worker,
          tile_id: tile_id(),
          hp: non_neg_integer(),
          max_hp: pos_integer(),
          movement: non_neg_integer(),
          max_movement: non_neg_integer()
        }

  @type order :: %{kind: :move, path: [tile_id()], status: :pending | :interrupted}

  @type player :: %{id: player_id(), user_id: term(), region_id: term(), gold: non_neg_integer()}

  @type city :: Production.city()
  @type improvement :: %{
          optional(:duration) => pos_integer() | nil,
          tile_id: tile_id(),
          kind: Improvement.kind(),
          progress: non_neg_integer(),
          status: Improvement.status(),
          builder_unit_id: unit_id() | nil
        }

  @type camp_id :: term()
  @type camp :: Camps.camp()

  @type state :: %{
          world: BrokenOaths.Worlds.World.t(),
          turn: non_neg_integer(),
          units: %{unit_id() => unit()},
          orders: %{unit_id() => order()},
          players: %{player_id() => player()},
          explored: %{player_id() => MapSet.t(tile_id())},
          cities: %{city_id() => city()},
          improvements: %{tile_id() => improvement()},
          camps: %{camp_id() => camp()}
        }

  @type event ::
          {:turn_advanced, non_neg_integer()}
          | {:unit_spawned, Production.spawn_event()}
          | {:lineage_continued, term(), String.t()}

  @doc """
  Advance the world by one turn: reset movement, resolve every pending
  move order simultaneously, run the city-loop phases (see this
  module's "City loop phases" doc above), refresh each player's
  explored set, and bump the turn counter.

  Returns `{new_state, events}`; `events` always includes
  `{:turn_advanced, new_turn}`, plus one `{:unit_spawned, spawn_event}`
  per completed production item that found a landing tile this tick —
  `new_state.units` does NOT yet contain those units, since only the
  caller (`WorldServer`) can allocate a real, persisted unit id.
  """
  @spec tick(state()) :: {state(), [event()]}
  def tick(state) do
    new_turn = state.turn + 1

    state =
      state
      |> reset_movement()
      |> resolve_orders()
      |> advance_improvements()
      |> accrue_production()

    {state, spawn_events, occupied, settled_this_tick} = resolve_completions(state)
    {state, camp_events, occupied} = resolve_camp_spawns(state, occupied)
    {state, attacked_cities} = resolve_barbarian_ai(state, occupied, new_turn)
    {state, heir_events} = resolve_heirs(state, new_turn)
    {state, tech_events} = accrue_science(state)

    new_state =
      state
      |> clear_orphaned_builders()
      |> regen_cities(attacked_cities)
      |> accrue_food()
      |> grow_cities(settled_this_tick)
      |> heal_units()
      |> refresh_explored()
      |> Map.put(:turn, new_turn)

    events =
      [
        {:turn_advanced, new_turn}
        | Enum.map(spawn_events ++ camp_events, &{:unit_spawned, &1})
      ] ++ heir_events ++ tech_events

    {new_state, events}
  end

  @doc """
  Immediate movement: spend `unit_id`'s remaining points on its pending
  order right now. Orders execute as they're issued — the turn boundary
  only recharges movement and continues whatever path remains. Same
  collision semantics as the tick: a step into an occupied tile
  interrupts the order in place.
  """
  @spec move_now(state(), term()) :: state()
  def move_now(state, unit_id) do
    case Map.get(state.orders, unit_id) do
      %{kind: :move, status: :pending, path: path} when path != [] ->
        unit = Map.fetch!(state.units, unit_id)

        movers = %{
          unit_id => %{
            tile_id: unit.tile_id,
            path: path,
            status: :pending,
            movement_left: unit.movement
          }
        }

        positions = Map.new(state.units, fn {id, u} -> {id, u.tile_id} end)

        {movers, positions} =
          run_rounds(
            movers,
            positions,
            state.units,
            garrisonable_tiles(state.cities),
            broken_city_tiles(state.cities)
          )

        %{
          state
          | units: apply_positions(state.units, movers, positions),
            orders: apply_orders(state.orders, movers)
        }
        |> refresh_explored()

      _ ->
        state
    end
  end

  # -------------------------------------------------------------------
  # Movement point reset
  # -------------------------------------------------------------------

  defp reset_movement(state) do
    units = Map.new(state.units, fn {id, unit} -> {id, %{unit | movement: unit.max_movement}} end)
    %{state | units: units}
  end

  # -------------------------------------------------------------------
  # Simultaneous move resolution
  # -------------------------------------------------------------------

  defp resolve_orders(state) do
    movers =
      for {unit_id, %{kind: :move, status: :pending, path: path}} <- state.orders,
          path != [],
          into: %{} do
        unit = Map.fetch!(state.units, unit_id)

        {unit_id,
         %{tile_id: unit.tile_id, path: path, status: :pending, movement_left: unit.movement}}
      end

    positions = Map.new(state.units, fn {id, unit} -> {id, unit.tile_id} end)

    {movers, positions} =
      run_rounds(
        movers,
        positions,
        state.units,
        garrisonable_tiles(state.cities),
        broken_city_tiles(state.cities)
      )

    %{
      state
      | units: apply_positions(state.units, movers, positions),
        orders: apply_orders(state.orders, movers)
    }
  end

  # `units` is the pre-round snapshot of every unit's `type`/`player_id`
  # (stable for the round — only `positions` changes as movers claim
  # tiles); `garrisonable` is `player_id => MapSet.t(their own cities'
  # tile_ids)`, precomputed once via `garrisonable_tiles/1`; `broken_cities`
  # is `tile_id => owner_player_id`, precomputed once via
  # `broken_city_tiles/1`. All three are read-only context for
  # `attempt_step/5`'s story-895 garrison exception and story-906 broken-
  # city exception below.
  defp run_rounds(movers, positions, units, garrisonable, broken_cities) do
    case active_movers(movers) do
      [] ->
        {movers, positions}

      ids ->
        {movers, positions} =
          Enum.reduce(
            ids,
            {movers, positions},
            &attempt_step(&1, &2, units, garrisonable, broken_cities)
          )

        run_rounds(movers, positions, units, garrisonable, broken_cities)
    end
  end

  defp active_movers(movers) do
    movers
    |> Enum.filter(fn {_id, m} ->
      m.status == :pending and m.path != [] and m.movement_left > 0
    end)
    |> Enum.map(fn {id, _m} -> id end)
    |> Enum.sort()
  end

  # `player_id => MapSet.t(tile_id)` of that player's own cities' own
  # tiles — the only tiles `blocked?/6`'s garrison exception ever
  # applies to.
  defp garrisonable_tiles(cities) do
    cities
    |> Map.values()
    |> Enum.group_by(& &1.player_id)
    |> Map.new(fn {player_id, owned} ->
      {player_id, MapSet.new(Enum.map(owned, & &1.tile_id))}
    end)
  end

  # `tile_id => owner_player_id` of every BROKEN (0 HP), still-free city
  # — story 906's own movement exception (`BrokenOaths.Game.Siege.
  # enterable_despite_garrison?/2`): once a city's walls are down, any
  # OTHER player's unit may step onto its own tile even past a fallen
  # (still-alive, not-yet-resolved) garrison. A healthy or already-
  # captured city (`occupied_by_player_id` set) is never in this map, so
  # this never loosens collision for either case — see `Siege.broken?/1`.
  defp broken_city_tiles(cities) do
    cities
    |> Map.values()
    |> Enum.filter(&(Map.get(&1, :hp) == 0 and is_nil(Map.get(&1, :occupied_by_player_id))))
    |> Map.new(&{&1.tile_id, &1.player_id})
  end

  defp attempt_step(unit_id, {movers, positions}, units, garrisonable, broken_cities) do
    mover = Map.fetch!(movers, unit_id)
    [target | rest] = mover.path
    mover_unit = Map.fetch!(units, unit_id)

    # A step onto the mover's OWN current-in-round tile is degenerate,
    # not a same-tile arrival to silently drop: `blocked?/6` always
    # excludes the mover itself from `positions`-derived occupants (a
    # unit never blocks its own vacated tile), so without this guard
    # such a step would "succeed" into an empty path, `apply_orders/2`
    # would read that as arrival, and the order would vanish instead of
    # halting the mover with `:interrupted` as a blocked step should.
    if target == mover.tile_id or
         blocked?(target, positions, units, mover_unit, garrisonable, broken_cities) do
      {Map.put(movers, unit_id, %{mover | status: :interrupted}), positions}
    else
      moved = %{mover | tile_id: target, path: rest, movement_left: mover.movement_left - 1}
      {Map.put(movers, unit_id, moved), Map.put(positions, unit_id, target)}
    end
  end

  # A tile with no occupants at all is never blocked. Otherwise blocked
  # UNLESS `target` is `mover_unit`'s own city's own tile with garrison
  # room for it (story 895 — `CityDefense.garrison_room?/2`), OR `target`
  # is another player's BROKEN city (story 906 — `Siege.
  # enterable_despite_garrison?/2`, the fallen-garrison walk-in), OR
  # `target` holds exactly one of the mover's own units of the OTHER
  # combat class (v0.2.1 playtest issue 5df5de88 — a civilian may stack
  # with a combat escort, either direction, out in the open field —
  # `entering_field_stack_with_room?/2`); every other occupied tile,
  # city or not, mine or another player's, keeps the original
  # all-or-nothing rule.
  defp blocked?(target, positions, units, mover_unit, garrisonable, broken_cities) do
    occupants =
      for {id, tile} <- positions, tile == target, id != mover_unit.id, do: Map.fetch!(units, id)

    case occupants do
      [] ->
        false

      _ ->
        not (entering_own_garrison_with_room?(target, occupants, mover_unit, garrisonable) or
               entering_broken_enemy_city?(target, mover_unit, broken_cities) or
               entering_field_stack_with_room?(occupants, mover_unit))
    end
  end

  # Mirrors `WorldServer.field_stack_room?/2`'s queue-time allowance for
  # the dynamic, tick-time check: exactly one existing occupant, owned
  # by the SAME player as `mover_unit`, of the OTHER combat class
  # (`CityDefense.military?/1` — the same combat/civilian split story
  # 895's own garrison rule uses). Two or more occupants, a foreign
  # occupant, or a same-class occupant all stay blocked.
  defp entering_field_stack_with_room?([only], mover_unit) do
    only.player_id == mover_unit.player_id and
      CityDefense.military?(only) != CityDefense.military?(mover_unit)
  end

  defp entering_field_stack_with_room?(_occupants, _mover_unit), do: false

  defp entering_own_garrison_with_room?(target, occupants, mover_unit, garrisonable) do
    MapSet.member?(Map.get(garrisonable, mover_unit.player_id, MapSet.new()), target) and
      CityDefense.garrison_room?(mover_unit, occupants)
  end

  defp entering_broken_enemy_city?(target, mover_unit, broken_cities) do
    case Map.get(broken_cities, target) do
      nil -> false
      owner_player_id -> owner_player_id != mover_unit.player_id
    end
  end

  defp apply_positions(units, movers, positions) do
    Map.new(units, fn {id, unit} ->
      case Map.fetch(movers, id) do
        {:ok, mover} ->
          {id, %{unit | tile_id: Map.fetch!(positions, id), movement: mover.movement_left}}

        :error ->
          {id, unit}
      end
    end)
  end

  # Orders whose path emptied this tick (arrival) are dropped entirely.
  defp apply_orders(orders, movers) do
    orders
    |> Enum.map(fn {id, order} ->
      case Map.fetch(movers, id) do
        {:ok, mover} -> {id, %{order | path: mover.path, status: mover.status}}
        :error -> {id, order}
      end
    end)
    |> Enum.reject(fn {_id, order} -> order.path == [] end)
    |> Map.new()
  end

  # -------------------------------------------------------------------
  # Improvement progress
  # -------------------------------------------------------------------

  # Only an improvement whose declared builder is STILL standing on its
  # tile advances — "one unit per hex" means at most one candidate
  # builder can ever be present, so there's no concurrent-builder case
  # to arbitrate. Anyone else (owner or not — improvements aren't
  # owned) who later starts the same kind on this tile reattaches and
  # resumes from whatever `progress` was frozen at.
  #
  # Threads `state.units` through alongside `state.improvements`
  # (story 882 playtest update, issue 1caa87e9 — worker build charges):
  # a completion can spend the builder's charge and, on its last one,
  # remove the unit outright, so this phase now owns both maps instead
  # of only the improvement side.
  defp advance_improvements(state) do
    {improvements, units} =
      Enum.map_reduce(state.improvements, state.units, fn {tile_id, improvement}, units ->
        {new_improvement, new_units} = advance_improvement(improvement, units)
        {{tile_id, new_improvement}, new_units}
      end)

    %{state | improvements: Map.new(improvements), units: units}
  end

  defp advance_improvement(%{status: :complete} = improvement, units), do: {improvement, units}
  defp advance_improvement(%{builder_unit_id: nil} = improvement, units), do: {improvement, units}

  defp advance_improvement(improvement, units) do
    case Map.get(units, improvement.builder_unit_id) do
      %{tile_id: tile_id} when tile_id == improvement.tile_id ->
        finish_or_progress(improvement, units)

      _still_present ->
        {%{improvement | builder_unit_id: nil}, units}
    end
  end

  # Story 902, criterion 7628 — `improvement.duration` (set once, at
  # build-start, by `WorldServer.persist_start_improvement!/3` — see
  # `Improvement`'s own moduledoc) overrides the kind's hardcoded base
  # when present; a hand-built tick-state map with no `:duration` key
  # at all (most of this module's own unit tests, and any improvement
  # kind that never gets a research-gated override) falls back to
  # `Improvement.duration/1` exactly as before this story.
  defp finish_or_progress(improvement, units) do
    progress = improvement.progress + 1
    duration = Map.get(improvement, :duration) || Improvement.duration(improvement.kind)

    if progress >= duration do
      completed = %{improvement | progress: duration, status: :complete, builder_unit_id: nil}
      {completed, spend_charge(units, improvement.builder_unit_id, improvement.kind)}
    else
      {%{improvement | progress: progress}, units}
    end
  end

  # Story 882 playtest update (issue 1caa87e9 — worker build charges,
  # Civ 6 Builder convention): a worker spends exactly one build charge
  # per COMPLETED Farm or Mine (charges are only ever consumed on
  # COMPLETION, never on starting or abandoning a build — an abandoned
  # dig never reaches `finish_or_progress/2`'s completion branch at
  # all, so it costs nothing by construction). Roads are charge-exempt
  # (matching Civ 6, where Builders never spend a charge on a road) and
  # so is Pasture here — story 905 postdates this charges shaping and
  # names only Farm/Mine in its rule text, so Pasture is left
  # charge-exempt pending an explicit PM call. A worker with no charges
  # left after this decrement is expended: removed from `state.units`
  # outright, in the SAME tick its last charge is spent — the same
  # removal path `BrokenOaths.Game.WorldServer.persist_unit_changes/2`
  # already sweeps a combat death through (diffs `state.units`, deletes
  # whatever's missing).
  defp spend_charge(units, unit_id, kind) when kind in [:farm, :mine] do
    case Map.get(units, unit_id) do
      nil ->
        units

      unit ->
        case Map.get(unit, :charges, 3) - 1 do
          remaining when remaining <= 0 -> Map.delete(units, unit_id)
          remaining -> Map.put(units, unit_id, Map.put(unit, :charges, remaining))
        end
    end
  end

  defp spend_charge(units, _unit_id, _kind), do: units

  # `advance_improvements/1` (above) already clears a builder that's
  # gone or walked away — but only as of the START of this tick. Combat
  # (story 893's barbarian AI loop, or a player's own "attack") can
  # kill a unit LATER in this SAME tick, after `advance_improvements`
  # already ran; if that unit was mid-build, its improvement still
  # carries a `builder_unit_id` pointing at a row `persist_unit_changes`
  # is about to delete, and the FIRST subsequent write to that
  # improvement (progress banked this same tick, say) would violate the
  # `game_improvements` table's own foreign key. A final sweep right
  # before persistence — cheap, only ever a no-op unless combat just
  # happened — keeps this consistent regardless of which combat path
  # did the killing.
  defp clear_orphaned_builders(state) do
    improvements =
      Map.new(state.improvements, fn
        {tile_id, %{builder_unit_id: id} = improvement} when not is_nil(id) ->
          if Map.has_key?(state.units, id) do
            {tile_id, improvement}
          else
            {tile_id, %{improvement | builder_unit_id: nil}}
          end

        {tile_id, improvement} ->
          {tile_id, improvement}
      end)

    %{state | improvements: improvements}
  end

  # -------------------------------------------------------------------
  # Production: accrual, completion, spawn placement
  # -------------------------------------------------------------------

  defp accrue_production(state) do
    cities =
      Map.new(state.cities, fn {id, city} ->
        {id, accrue_or_skip(city, state)}
      end)

    %{state | cities: cities}
  end

  # A pillaged city's queue simply doesn't move while
  # `CityDefense.production_halted?/2` holds — see that function's doc
  # for exactly which boundaries that covers.
  defp accrue_or_skip(city, state) do
    if CityDefense.production_halted?(city, state.turn) do
      city
    else
      Production.accrue(city, state.world, state.improvements)
    end
  end

  # Threads a running "occupied tiles" set through cities in ascending
  # id order, so a spawn from one city in this same tick correctly
  # blocks a landing tile for the next city's completion — before
  # either lands in `state.units`, which only the caller can update
  # (see `tick/1`'s doc on `{:unit_spawned, _}` events). Also threads a
  # `MapSet` of city ids whose queue completed a `:settler` THIS tick
  # (`Production.apply_pop_cost/3` already docked their population the
  # instant the spawn event was built, above) — `grow_cities/2` reads
  # this to skip those cities' own growth this same tick (issue
  # 63300098: growth resolving in the same tick otherwise silently
  # refunds the settler's population cost the instant a well-fed city
  # crosses its next threshold).
  defp resolve_completions(state) do
    occupied = Map.new(state.units, fn {_id, unit} -> {unit.tile_id, true} end)
    ids = state.cities |> Map.keys() |> Enum.sort()

    {cities, events, occupied, settled_this_tick} =
      Enum.reduce(
        ids,
        {state.cities, [], occupied, MapSet.new()},
        &resolve_city_completion(state.world, &1, &2)
      )

    {%{state | cities: cities}, events, occupied, settled_this_tick}
  end

  defp resolve_city_completion(world, id, {cities, events, occupied, settled_this_tick}) do
    city = Map.fetch!(cities, id)
    {new_city, city_events} = Production.complete(city, occupied, world)
    newly_occupied = Map.new(city_events, fn event -> {event.tile_id, true} end)

    settled_this_tick =
      if Enum.any?(city_events, &(&1.type == :settler)) do
        MapSet.put(settled_this_tick, id)
      else
        settled_this_tick
      end

    {
      Map.put(cities, id, new_city),
      events ++ city_events,
      Map.merge(occupied, newly_occupied),
      settled_this_tick
    }
  end

  # -------------------------------------------------------------------
  # Camp spawn loop (story 892)
  # -------------------------------------------------------------------

  # Reuses the SAME occupied-tile thread `resolve_completions/1` just
  # built (see that function's doc) so a camp spawn can't land on a
  # tile a city completion claimed this same tick, and vice versa. The
  # updated set is returned too — `resolve_barbarian_ai/3` starts from
  # it, so a warrior placed THIS tick by either loop (not yet in
  # `state.units` — see `tick/1`'s doc) still reserves its tile against
  # an already-existing barbarian roaming or hunting onto it.
  defp resolve_camp_spawns(state, occupied) do
    state = Map.put_new(state, :camps, %{})
    ids = state.camps |> Map.keys() |> Enum.sort()
    alive = camp_alive_counts(state.units)

    {camps, events, occupied} =
      Enum.reduce(ids, {state.camps, [], occupied}, fn id, acc ->
        resolve_camp_spawn(state.world, id, Map.get(alive, id, 0), acc)
      end)

    {%{state | camps: camps}, events, occupied}
  end

  # Ordinary units never set :camp_id — read defensively, the same way
  # `pending_heirs` reads unfamiliar keys elsewhere in this module.
  defp camp_alive_counts(units) do
    Enum.reduce(units, %{}, fn {_id, unit}, counts ->
      case Map.get(unit, :camp_id) do
        nil -> counts
        camp_id -> Map.update(counts, camp_id, 1, &(&1 + 1))
      end
    end)
  end

  defp resolve_camp_spawn(world, id, alive_count, {camps, events, occupied}) do
    camp = Map.fetch!(camps, id)
    {advanced, ready?} = Camps.advance(camp, alive_count)

    if ready? do
      place_camp_warrior(world, advanced, camps, events, occupied)
    else
      {Map.put(camps, id, advanced), events, occupied}
    end
  end

  defp place_camp_warrior(world, camp, camps, events, occupied) do
    case camp_landing_tile(world, camp, occupied) do
      nil ->
        {Map.put(camps, camp.id, camp), events, occupied}

      tile ->
        event = %{player_id: nil, type: :barbarian_warrior, tile_id: tile, camp_id: camp.id}
        spawned = Camps.spawned(camp)
        {Map.put(camps, camp.id, spawned), [event | events], Map.put(occupied, tile, true)}
    end
  end

  # A camp's own tile first, then its adjacent land tiles (sorted for
  # determinism) — mirrors `Production`'s city landing-tile pick, so a
  # second warrior lands beside the first rather than failing to spawn.
  defp camp_landing_tile(world, camp, occupied) do
    candidates =
      [
        camp.tile_id
        | world
          |> Regions.adjacent_tiles(camp.tile_id)
          |> Enum.filter(&land?(world, &1))
          |> Enum.sort()
      ]

    Enum.find(candidates, &(not Map.has_key?(occupied, &1)))
  end

  defp land?(world, tile_id), do: Regions.tile_class(world, tile_id) == :land

  # -------------------------------------------------------------------
  # Barbarian AI loop (story 893)
  # -------------------------------------------------------------------

  # Every EXISTING camp-spawned warrior gets one `BarbarianAI.decide/6`
  # call, resolved in ascending unit id order (same determinism rule as
  # every other phase in this module) while threading the occupied-tile
  # set so two barbarians in the same tick never step on each other. A
  # warrior this SAME tick's camp-spawn phase just placed isn't in
  # `state.units` yet (see `tick/1`'s doc) and is silently skipped — it
  # gets its first decision next boundary — but `spawn_occupied` (that
  # same phase's own occupied-tile thread) still reserves its tile, so
  # an already-existing barbarian can't roam or hunt onto it either.
  #
  # Returns `{state, attacked_city_ids}` — the second element (story
  # 895) is every city THIS phase itself struck, ascending-id order
  # threaded the same way `occupied` is; `regen_cities/2` reads it to
  # skip that city's own regen this boundary (see `tick/1`'s doc).
  defp resolve_barbarian_ai(state, spawn_occupied, new_turn) do
    ids = for {id, unit} <- state.units, Map.get(unit, :camp_id), do: id
    occupied = MapSet.new(Map.keys(spawn_occupied))

    {state, _occupied, attacked_cities} =
      Enum.reduce(
        Enum.sort(ids),
        {state, occupied, MapSet.new()},
        &resolve_barbarian(&1, new_turn, &2)
      )

    {state, attacked_cities}
  end

  defp resolve_barbarian(id, new_turn, {state, occupied, attacked_cities}) do
    case Map.get(state.units, id) do
      nil ->
        {state, occupied, attacked_cities}

      barbarian ->
        camp_tile = camp_tile_for(state.camps, Map.get(barbarian, :camp_id))
        seed = {state.world.seed, state.turn, id}

        decision =
          BarbarianAI.decide(
            state.world,
            barbarian,
            camp_tile,
            Map.values(state.units),
            Map.values(state.cities),
            occupied: occupied,
            seed: seed
          )

        apply_barbarian_decision(decision, state, occupied, attacked_cities, barbarian, new_turn)
    end
  end

  defp camp_tile_for(_camps, nil), do: nil
  defp camp_tile_for(camps, camp_id), do: camps |> Map.get(camp_id) |> then(&(&1 && &1.tile_id))

  # Defensive: `BarbarianAI.decide/6` is handed `occupied` precisely to
  # keep it from choosing a currently-held tile, but a second, unrelated
  # player's own queued order can still claim a tile between when a
  # barbarian's decision was computed and when it's applied here (both
  # read the SAME pre-phase snapshot). Re-checking right before writing
  # the position is the one place this can be caught for certain — the
  # DB's own unique index on `(world_id, tile_id)` would otherwise raise
  # mid-transaction. A blocked barbarian simply holds this boundary.
  defp apply_barbarian_decision(
         {:move, tile},
         state,
         occupied,
         attacked_cities,
         barbarian,
         _new_turn
       ) do
    if MapSet.member?(occupied, tile) do
      {state, occupied, attacked_cities}
    else
      moved = %{barbarian | tile_id: tile, movement: 0}

      new_state = %{
        state
        | units: Map.put(state.units, barbarian.id, moved),
          improvements: maybe_pillage(state.improvements, tile)
      }

      new_occupied = occupied |> MapSet.delete(barbarian.tile_id) |> MapSet.put(tile)
      {new_state, new_occupied, attacked_cities}
    end
  end

  # Story 895: `BarbarianAI.decide/6` reports `:hold` both for a true
  # "nothing anywhere near" hold AND for "already adjacent to a city,
  # nothing else to attack there yet" (that module's own doc/tests
  # never resolve the city fight itself — see this module's own doc).
  # This is where that second case becomes a real assault; a true hold
  # (no adjacent city either) is unchanged.
  defp apply_barbarian_decision(:hold, state, occupied, attacked_cities, barbarian, _new_turn) do
    case adjacent_city(state, barbarian) do
      nil ->
        {state, occupied, attacked_cities}

      city ->
        new_state = resolve_barbarian_city_attack(state, barbarian, city)
        {new_state, occupied, MapSet.put(attacked_cities, city.id)}
    end
  end

  defp apply_barbarian_decision(
         {:attack, target_id},
         state,
         occupied,
         attacked_cities,
         barbarian,
         new_turn
       ) do
    case Map.get(state.units, target_id) do
      nil ->
        {state, occupied, attacked_cities}

      target ->
        new_state = resolve_barbarian_attack(state, barbarian, target, new_turn)

        new_occupied =
          occupied
          |> vacate_if_gone(barbarian.tile_id, barbarian.id, new_state.units)
          |> vacate_if_gone(target.tile_id, target.id, new_state.units)

        {new_state, new_occupied, attacked_cities}
    end
  end

  defp adjacent_city(state, barbarian) do
    adjacent_tile_ids = Regions.adjacent_tiles(state.world, barbarian.tile_id)
    Enum.find(Map.values(state.cities), &(&1.tile_id in adjacent_tile_ids))
  end

  # Same math `WorldServer.resolve_city_attack/3` uses for a stand-in
  # real player's immediate "attack" — see `CityDefense.resolve_attack/4`'s
  # doc. A barbarian that dies here (killed by the garrison's
  # counter-blow) pays its killer's owner the bounty.
  defp resolve_barbarian_city_attack(state, barbarian, city) do
    seed = {state.world.seed, state.turn, barbarian.id, city.id}
    units = Map.values(state.units)

    %{damage_to_city: dealt, damage_to_barbarian: taken} =
      CityDefense.resolve_attack(city, units, barbarian,
        seed: seed,
        attacker_aura?: lord_adjacent?(state, barbarian)
      )

    new_city = CityDefense.take_damage(city, dealt, state.turn)
    new_barbarian = %{barbarian | hp: max(barbarian.hp - taken, 0), movement: 0}

    %{
      state
      | units: apply_combat_unit(state.units, barbarian.id, new_barbarian),
        cities: Map.put(state.cities, city.id, new_city)
    }
    |> pay_bounty_if_barbarian_fell(new_barbarian, %{player_id: city.player_id})
  end

  defp vacate_if_gone(occupied, tile_id, unit_id, units) do
    if Map.has_key?(units, unit_id), do: occupied, else: MapSet.delete(occupied, tile_id)
  end

  defp maybe_pillage(improvements, tile_id) do
    case Map.get(improvements, tile_id) do
      nil -> improvements
      improvement -> Map.put(improvements, tile_id, Improvement.pillage(improvement))
    end
  end

  # Simultaneous exchange, same math a player's own attack uses
  # (`WorldServer.resolve_attack/3`) — a dying defender still lands its
  # counter-blow. A barbarian that dies here pays its killer's owner
  # the bounty; a lord that dies here schedules an heir exactly like a
  # player-initiated kill would. `defender_garrisoned?` (story 895):
  # a player unit standing on its own city's tile fights back at +50%
  # here too, same as when it's the one striking out.
  defp resolve_barbarian_attack(state, barbarian, target, new_turn) do
    seed = {state.world.seed, state.turn, barbarian.id, target.id}

    %{damage_to_defender: dealt, damage_to_attacker: taken} =
      Combat.resolve(barbarian, target,
        seed: seed,
        defender_aura?: lord_adjacent?(state, target),
        defender_garrisoned?: CityDefense.garrisoned?(target, Map.values(state.cities))
      )

    new_barbarian = %{barbarian | hp: max(barbarian.hp - taken, 0), movement: 0}
    new_target = %{target | hp: max(target.hp - dealt, 0)}

    units =
      state.units
      |> apply_combat_unit(barbarian.id, new_barbarian)
      |> apply_combat_unit(target.id, new_target)

    %{state | units: units}
    |> schedule_heir_if_lord_fell(target, new_target, new_turn)
    |> pay_bounty_if_barbarian_fell(new_barbarian, target)
  end

  defp apply_combat_unit(units, id, %{hp: 0}), do: Map.delete(units, id)
  defp apply_combat_unit(units, id, unit), do: Map.put(units, id, unit)

  # Story 904: same career-total bump `WorldServer.pay_bounty_if_barbarian_fell/3`
  # applies for a player-initiated kill — a barbarian-initiated exchange
  # resolved here (this AI loop's own attack, felled by the defender's
  # counter-blow) counts toward the progress panel's "Total barbarians
  # killed" figure exactly the same way.
  defp pay_bounty_if_barbarian_fell(state, %{hp: 0}, %{player_id: payee_id})
       when not is_nil(payee_id) do
    state = update_in(state.players[payee_id].gold, &(&1 + BarbarianAI.bounty_gold()))
    update_in(state.players[payee_id].barbarians_killed, &(&1 + 1))
  end

  defp pay_bounty_if_barbarian_fell(state, _barbarian, _target), do: state

  defp schedule_heir_if_lord_fell(state, %{type: :lord, player_id: player_id}, %{hp: 0}, new_turn) do
    pending_heirs = state |> Map.get(:pending_heirs, %{}) |> Map.put(player_id, new_turn + 10)
    Map.put(state, :pending_heirs, pending_heirs)
  end

  defp schedule_heir_if_lord_fell(state, _original, _new, _new_turn), do: state

  # A living unit of the SAME player standing next door — mirrors
  # `WorldServer.lord_adjacent?/2` (dead units are already gone from
  # `state.units`, so presence alone means living).
  defp lord_adjacent?(state, unit) do
    adjacent_tile_ids = Regions.adjacent_tiles(state.world, unit.tile_id)

    state.units
    |> Map.values()
    |> Enum.any?(
      &(&1.type == :lord and &1.player_id == unit.player_id and &1.tile_id in adjacent_tile_ids)
    )
  end

  # -------------------------------------------------------------------
  # City regeneration (story 895)
  # -------------------------------------------------------------------

  # Every city NOT in `attacked_cities` (this tick's own barbarian-AI
  # assaults — see `resolve_barbarian_ai/3`'s doc) regens; a struck one
  # is left exactly as the assault left it this boundary.
  defp regen_cities(state, attacked_cities) do
    cities =
      Map.new(state.cities, fn {id, city} ->
        if MapSet.member?(attacked_cities, id) do
          {id, city}
        else
          {id, CityDefense.regen(city)}
        end
      end)

    %{state | cities: cities}
  end

  # -------------------------------------------------------------------
  # Food accrual and growth
  # -------------------------------------------------------------------

  defp accrue_food(state) do
    cities =
      Map.new(state.cities, fn {id, city} ->
        {id, Yields.accrue_food(city, state.world, state.improvements)}
      end)

    %{state | cities: cities}
  end

  # Each city grows against the CURRENT territory of every city
  # (including siblings already grown earlier in this same reduce), so
  # two cities eligible for the same tile in one tick resolve by
  # ascending city id — the same determinism rule the doc promises.
  # Story 903: the size cap (4 Stone Age / 6 Bronze Age) is the city
  # OWNER's own age (`Research.age/1`, read off this SAME tick's
  # `state.player_research` — already advanced by `accrue_science/1`
  # earlier in `tick/1`, so a Bronze Working completion lifts the cap
  # the instant it lands, same turn), never the city's own state.
  #
  # `settled_this_tick` (issue 63300098) is `resolve_completions/1`'s
  # own set of city ids that completed a `:settler` THIS tick — a city
  # in that set never grows this same tick, even if its banked food
  # already clears the (now one-lower, post-pop-cost) next threshold.
  # Without this, a well-fed city's settler pop cost and growth cancel
  # out invisibly in the same boundary, defeating story 883's "a
  # settler costs the city one population" intent. The city's CURRENT
  # (already pop-cost-adjusted) state still threads through to its
  # siblings' own territory checks below — only ITS OWN growth is
  # skipped, nothing else about this tick's bookkeeping changes.
  defp grow_cities(state, settled_this_tick) do
    ids = state.cities |> Map.keys() |> Enum.sort()
    player_research = Map.get(state, :player_research, %{})

    cities =
      Enum.reduce(ids, state.cities, fn id, cities ->
        city = Map.fetch!(cities, id)

        if MapSet.member?(settled_this_tick, id) do
          cities
        else
          pr = Map.get(player_research, city.player_id, Research.new())
          grown = Yields.grow(city, Map.values(cities), state.world, Research.age(pr))
          Map.put(cities, id, grown)
        end
      end)

    %{state | cities: cities}
  end

  # -------------------------------------------------------------------
  # Healing
  # -------------------------------------------------------------------

  # "Unmoved" is read straight off this tick's movement ledger: a unit
  # that spent zero movement points still holds `movement == max_movement`
  # after `resolve_orders`, whether that's because it had no order or
  # because its order was blocked before its first step.
  defp heal_units(state) do
    units = Map.new(state.units, fn {id, unit} -> {id, heal(unit, state.cities)} end)
    %{state | units: units}
  end

  defp heal(%{hp: hp, max_hp: max_hp} = unit, _cities) when hp >= max_hp, do: unit

  defp heal(unit, cities) do
    if unit.movement == unit.max_movement do
      %{unit | hp: min(unit.max_hp, unit.hp + heal_rate(unit, cities))}
    else
      unit
    end
  end

  defp heal_rate(unit, cities) do
    owned = for {_id, city} <- cities, city.player_id == unit.player_id, do: city

    cond do
      Enum.any?(owned, &(&1.tile_id == unit.tile_id)) -> 15
      Enum.any?(owned, &(unit.tile_id in &1.territory)) -> 10
      true -> 0
    end
  end

  # -------------------------------------------------------------------
  # Heir succession
  # -------------------------------------------------------------------

  defp resolve_heirs(state, new_turn) do
    state = Map.put_new(state, :pending_heirs, %{})

    due =
      for {player_id, arrival_turn} <- state.pending_heirs, new_turn >= arrival_turn do
        player_id
      end

    Enum.reduce(due, {state, []}, &resolve_heir/2)
  end

  defp resolve_heir(player_id, {state, events}) do
    state = %{state | pending_heirs: Map.delete(state.pending_heirs, player_id)}

    case capital_city(state.cities, player_id) do
      nil ->
        {state, events}

      city ->
        spawn_event = %{player_id: player_id, type: :lord, tile_id: city.tile_id}
        user_id = Map.fetch!(state.players, player_id).user_id
        message = "Your lord has fallen, but the line endures — a new lord takes the throne."

        {state, events ++ [{:unit_spawned, spawn_event}, {:lineage_continued, user_id, message}]}
    end
  end

  defp capital_city(cities, player_id) do
    cities
    |> Map.values()
    |> Enum.filter(&(&1.player_id == player_id))
    |> Enum.min_by(& &1.id, fn -> nil end)
  end

  # -------------------------------------------------------------------
  # Science accrual (story 902)
  # -------------------------------------------------------------------

  # Every player banks `Research.science_per_turn/1` (their OWN cities'
  # `2 * size`) toward their `current_research`, auto-completing it via
  # `Research.accrue_and_complete/2` the instant it reaches cost. A
  # player missing from `state.player_research` (most of this module's
  # own tests, and any player row created before this state key
  # existed) is treated as `Research.new/0` for this tick only — a
  # player with `current_research: nil` simply banks nothing, same
  # no-op `Research.accrue/2` documents.
  defp accrue_science(state) do
    player_research = Map.get(state, :player_research, %{})
    cities_by_player = Enum.group_by(Map.values(state.cities), & &1.player_id)

    {new_player_research, events} =
      Enum.reduce(state.players, {player_research, []}, fn {player_id, _player}, {acc, events} ->
        accrue_one_player(state, player_id, cities_by_player, acc, events)
      end)

    {Map.put(state, :player_research, new_player_research), Enum.reverse(events)}
  end

  defp accrue_one_player(state, player_id, cities_by_player, acc, events) do
    pr = Map.get(acc, player_id, Research.new())
    income = Research.science_per_turn(Map.get(cities_by_player, player_id, []))
    {new_pr, completed_tech} = Research.accrue_and_complete(pr, income)
    acc = Map.put(acc, player_id, new_pr)

    case completed_tech do
      nil ->
        {acc, events}

      tech ->
        user_id = Map.fetch!(state.players, player_id).user_id
        {acc, [{:tech_completed, user_id, tech} | events]}
    end
  end

  # -------------------------------------------------------------------
  # Exploration
  # -------------------------------------------------------------------

  defp refresh_explored(state) do
    explored =
      Map.new(state.players, fn {player_id, _player} ->
        units = for {_id, unit} <- state.units, unit.player_id == player_id, do: unit
        newly_visible = Visibility.visible_tiles(state.world, units)
        prior = Map.get(state.explored, player_id, MapSet.new())
        {player_id, MapSet.union(prior, newly_visible)}
      end)

    %{state | explored: explored}
  end
end
