defmodule BrokenOaths.Simulation.Turn.RoadBuilder do
  @moduledoc """
  Story 929 "Build road to a destination" — the per-tick resolution
  phase for a `:road_to` order (`Units.Unit.build_road_to/4`'s own
  queue-time validation/persistence; this module is the tick-time
  half). Genuinely cross-cutting — it walks `Units.Unit`'s own worker
  and reads collision off `state.units` the same way `Turn.Movement`
  does — with no single owning domain model, the same "gets its own
  `Turn.*` submodule" status `Turn.Movement`/`Turn.BarbarianPhase`/
  `Turn.HeirSuccession` already have. `Turn.tick/1` calls `resolve/1`
  once per tick, on the FAST layer (every tick, unconditional, never
  economy-gated — a road-to worker's WALK should feel as responsive as
  an ordinary move order, even though the BUILD it triggers only
  actually progresses on an economy tick, `Cities.Improvement.
  advance/1`), placed AFTER `Turn.BarbarianPhase.resolve/3` so this
  same tick's own barbarian damage (if any) is already reflected in
  `state.units` by the time the "attacked mid-build" check below runs.

  ## Pure core, impure shell (a brand-new road needs a real INSERT)

  `resolve/1` itself never touches `Repo` — same "no processes, no
  Repo calls" contract every other `Turn.*` phase honors (`Turn`'s own
  moduledoc). RESUMING an improvement that already has a row (this
  order started it in an earlier tick, or anyone else did —
  improvements aren't owned) is a plain in-memory `state.roads` write,
  exactly like `Cities.Improvement.advance/1`'s own progress
  increments — the generic diff in `WorldServer.persist_tick/2`
  (`persist_improvement_changes/3`) picks it up afterward same as any
  other improvement change. But that generic diff only ever `UPDATE`s
  a row that already exists in the DB (see its own body — no `kind`
  scoped to a fresh `INSERT` anywhere) — the exact same reason a
  freshly-completed production item can't allocate its own real unit
  id from inside pure `Turn.tick/1` either (`Cities.Production.
  resolve_completions/1`'s own `{:unit_spawned, spawn_event}` events,
  materialized afterward by `WorldServer.materialize_spawns/2`). A
  BRAND NEW road (no `state.roads` entry at all yet) is the same
  shape: `resolve/1` leaves `state.roads` untouched and returns a
  `{:road_start_needed, tile_id, unit_id}` event instead;
  `WorldServer.run_tick/1`'s own `materialize_road_starts/2` (mirroring
  `materialize_spawns/2`) is what actually calls `Cities.Improvement.
  ensure_building/3` (the one real `Repo.insert`) and patches
  `state.roads` with the result, AFTER `Turn.tick/1` has already
  returned.

  ## The walk-vs-build state machine (PM decision, story 929)

  A `:road_to` order's own `path` (see `Units.Order`'s moduledoc) is
  the FULL cheapest owned-territory route from the worker's tile at
  issue time through the destination — immutable, never shrunk as the
  worker advances (unlike a `:move` order's own `path`, which shrinks
  head-first as `Turn.Movement` consumes it). Every tick, for each unit
  currently holding one:

    1. Find the first tile on the route, scanning FORWARD from the
       worker's own current position, that does NOT yet carry a
       `:complete` road (`active_segment/3`) — already-roaded tiles
       (built by this order in an earlier tick, or by anything else —
       improvements aren't owned) are simply skipped for BUILDING
       purposes (the worker still physically walks across them, see
       step 3). `nil` (nothing left, forward of the worker, needs a
       road) means the whole route INCLUDING the destination is
       roaded — the order is done; it's removed.
    2. If the worker is STANDING on that tile: ensure a Road
       improvement is building there — resume in-memory if a row
       already exists, else emit `{:road_start_needed, ...}` (see
       above) — and let the ordinary economy-gated `Improvement.
       advance/1` progress it exactly like any other road; this phase
       never banks progress itself.
    3. Otherwise: advance the worker ONE step — the very next tile in
       its own immutable route past its current position (never a
       fresh pathfind; the route already encodes every intermediate
       hex the worker must physically cross, roaded-and-passed or
       not) — UNLESS that next tile is occupied by another unit right
       now, in which case the ENTIRE order is CANCELLED (PM decision:
       "interruption = cancel," no auto-reroute, no resume — the
       player must re-issue it; whatever road progress already banked
       on earlier segments is untouched, since it lives on the TILE,
       not the order). This is a deliberately SIMPLER collision rule
       than `Turn.Movement`'s own `blocked?/6` (no garrison-room,
       broken-city, or field-stack exceptions carried over) — any
       occupant at all blocks a road-to step.

  ## Attacked mid-build cancels (PM decision)

  A `:road_to` order also carries `hp_at_issue` (`Units.Order`'s own
  moduledoc) — the worker's HP the instant the order was issued.
  Before doing anything else for a unit's order this tick, `resolve/1`
  compares its CURRENT hp against that baseline: any drop cancels the
  order outright (a dead unit's order is already moot by construction
  — `state.units` no longer names it, so `resolve_one/3` below drops
  the order without even reaching the hp comparison). This single
  hp-vs-baseline check, run on the FAST layer every tick — and, thanks
  to this phase's own placement after `Turn.BarbarianPhase`, always
  checked again before `Unit.heal_all/2` (which runs LATER still in
  `Turn.tick/1`'s own pipeline) ever gets a chance to mask a hit with
  regen — catches damage from BOTH an immediate, out-of-tick attack (a
  rival player's own `:attack`/`:attack_camp`/`:shoot`/... command,
  resolved the instant it's issued, long before the next tick
  boundary) and a same-tick barbarian AI strike, with one check and no
  need to thread a cancellation hook through every individual combat
  call site.
  """

  @type event :: {:road_start_needed, non_neg_integer(), term()}

  @doc """
  Resolve every `:road_to` order one segment (build-or-walk, or
  cancel) forward, once per tick. Returns `{new_state, events}` — the
  SAME "state plus a list of things the impure shell still needs to
  materialize" shape `Cities.Production.resolve_completions/1` already
  returns (see this module's own moduledoc, "Pure core, impure shell").
  """
  @spec resolve(map()) :: {map(), [event()]}
  def resolve(state) do
    road_orders = for {unit_id, %{kind: :road_to} = order} <- state.orders, do: {unit_id, order}

    Enum.reduce(road_orders, {state, []}, fn {unit_id, order}, {acc_state, events} ->
      {new_state, new_events} = resolve_one(acc_state, unit_id, order)
      {new_state, events ++ new_events}
    end)
  end

  defp resolve_one(state, unit_id, order) do
    case Map.get(state.units, unit_id) do
      # Died this same tick (barbarian combat, resolved earlier in the
      # pipeline) — nothing left to walk or build for it.
      nil ->
        {drop_order(state, unit_id), []}

      unit ->
        if damaged?(unit, order) do
          {drop_order(state, unit_id), []}
        else
          advance(state, unit, order)
        end
    end
  end

  # `hp_at_issue` is only ever set on a `:road_to` order (see
  # `Units.Order`'s own moduledoc) — `is_integer/1` guards a
  # hand-built test order map that omits it, treating that as "never
  # damaged" rather than crashing.
  defp damaged?(unit, %{hp_at_issue: hp_at_issue}),
    do: is_integer(hp_at_issue) and unit.hp < hp_at_issue

  defp advance(state, unit, order) do
    case active_segment(state, unit, order.path) do
      nil ->
        {drop_order(state, unit.id), []}

      segment when segment == unit.tile_id ->
        build_here(state, unit)

      _segment ->
        {step(state, unit, order), []}
    end
  end

  # The worker is standing on the tile that still needs a road.
  # Resuming an EXISTING row is a pure in-memory write (same status
  # `Improvement.advance/1`'s own progress increments already have);
  # starting a BRAND NEW one needs a real `Repo.insert` this pure phase
  # may never make itself — see this module's own moduledoc.
  defp build_here(state, unit) do
    case Map.get(state.roads, unit.tile_id) do
      nil ->
        {state, [{:road_start_needed, unit.tile_id, unit.id}]}

      existing ->
        roads = Map.put(state.roads, unit.tile_id, %{existing | builder_unit_id: unit.id})
        {%{state | roads: roads}, []}
    end
  end

  # The first tile on `path`, scanning forward from `unit`'s own
  # current position (its own index in `path`, or -1 — "before the
  # route even starts" — if it hasn't reached the route yet), without
  # a `:complete` road. `nil` means every tile from here on is already
  # roaded, the destination included.
  defp active_segment(state, unit, path) do
    start_index = Enum.find_index(path, &(&1 == unit.tile_id)) || -1

    path
    |> Enum.with_index()
    |> Enum.find_value(fn {tile_id, idx} ->
      if idx >= start_index and not roaded?(state, tile_id), do: tile_id
    end)
  end

  defp roaded?(state, tile_id), do: match?(%{status: :complete}, Map.get(state.roads, tile_id))

  # One step along the worker's own immutable route: the tile
  # immediately after its current position (or the very first tile, if
  # it hasn't left its starting tile yet). Never a fresh pathfind —
  # `order.path` already encodes every hex the worker must physically
  # cross, in order, roaded or not.
  defp step(state, unit, order) do
    next_tile =
      case Enum.find_index(order.path, &(&1 == unit.tile_id)) do
        nil -> List.first(order.path)
        idx -> Enum.at(order.path, idx + 1)
      end

    cond do
      # Shouldn't happen — `active_segment/3` already found something
      # forward of the worker's own position — but a defensive cancel
      # beats a crash if the route and the worker's position ever
      # disagree.
      is_nil(next_tile) ->
        drop_order(state, unit.id)

      occupied?(state, next_tile, unit.id) ->
        drop_order(state, unit.id)

      true ->
        move_to(state, unit, next_tile)
    end
  end

  defp occupied?(state, tile_id, mover_id) do
    Enum.any?(state.units, fn {id, u} -> id != mover_id and u.tile_id == tile_id end)
  end

  defp move_to(state, unit, next_tile) do
    cost =
      BrokenOaths.Units.Unit.entry_cost(
        state.world,
        Map.get(state, :roads, %{}),
        next_tile,
        Map.get(state, :cleared_features, MapSet.new()),
        unit.type
      )

    new_unit = %{unit | tile_id: next_tile, movement: max(unit.movement - cost, 0)}
    %{state | units: Map.put(state.units, unit.id, new_unit)}
  end

  defp drop_order(state, unit_id), do: %{state | orders: Map.delete(state.orders, unit_id)}
end
