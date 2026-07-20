defmodule BrokenOaths.Combat.Camps do
  @moduledoc """
  Pure barbarian-camp core: first-founding wilderness placement and the
  per-camp spawn cadence. No `Repo`, no process state — mirrors
  `BrokenOaths.Simulation.Spawner`'s role for camps: `BrokenOaths.Simulation.Turn`
  and `BrokenOaths.Simulation.WorldServer` are the imperative shells that read
  camps out of the canonical tick-state, call into this module, and
  write the result back.

  ## Placement (first founding only — criterion 7543)

  `place_wilderness/6` picks two clusters of tiles, both pure functions
  of a caller-supplied `seed` term (see the determinism note below):

    * 1-2 tiles already inside the founding player's own claimed
      region — "near" camps, immediately known to the player because
      they're on home turf (no fog-of-war roll needed for them; see
      `BrokenOaths.Simulation.WorldServer`'s camp-visibility filter).
    * 4-5 tiles 8-15 hexes out (raw mesh-adjacency distance from the
      founding city), outside the claimed region and not already
      explored — "far" camps, the region-boundary bias.

  Every candidate pool prefers land reachable on foot from the founding
  city (over `BrokenOaths.Worlds.Regions.tile_class/2 == :land` mesh
  adjacency — the same graph `WorldServer`'s move pathfinding walks),
  then any other `:land` tile, then any tile class at all — each tier
  a fallback for the one before, since neither "walkable" nor "land at
  all" tiles are guaranteed to exist in every ring/region (a solo,
  land-locked region can have nothing but ocean immediately beyond its
  own border; a far ring can land entirely on a mountain-locked pocket
  or a separate island). The walkable preference matters because
  criterion 7545 marches a unit to a camp's doorstep — a camp only
  reachable by boat would be undiscoverable by design. Camps from
  different foundings (different players, or a future story) are
  never spaced apart from one another — "pile-up between neighbors is
  allowed" (Three Amigos notes, story 892) — that rule is unchanged.

  ## Spacing (v0.2.1 playtest balance pass — issue 04931763)

  Camps from the SAME founding, though, no longer land on top of one
  another: every near/far pick greedily skips any candidate within
  `@min_camp_spacing` (3) raw mesh hexes of an already-picked camp
  from this same `place_wilderness/6` call (near-to-near, far-to-far,
  AND near-to-far, since both pools can reach close to the shared
  8-15 ring boundary). This directly answers the playtest report
  ("camps too close together") without touching the ring band itself
  (already tuned once, QA issue ebe8abf1) or the per-camp cadence/cap
  (already tuned once, "spawn counter holds at cap"). If spacing alone
  can't fill the requested count — a small/crowded candidate pool —
  the remainder fills WITHOUT the spacing constraint from whatever's
  left, the same "never come up short" guarantee the land/walkable/
  fallback tiers above already give every other shortfall case.

  `@far_count` also narrowed from `4..6` to `4..5` in the same pass —
  a modest, one-camp-average reduction in peak simultaneous wilderness
  pressure (5-7 camps per founding now, was 5-8), addressing the
  "spawn too quickly, or too strong" half of the same report without
  touching the per-camp cadence (still every 3 turns) or the barbarian
  warrior's own combat strength (still 15) — both load-bearing
  elsewhere (criteria 7547/7548, 891/893's own strength-band specs).

  ## Spawn cadence (criteria 7547/7548/7549)

  `advance/2` ticks a camp's `spawn_counter` forward by one and reports
  whether it's `ready?` — cadence reached (every 3 turns) AND the camp
  currently holds fewer than 2 living warriors. The caller places the
  actual warrior (a real `Game.Unit`, `player_id: nil`, tagged with
  this camp's id — see `BrokenOaths.Simulation.Turn`'s "camp spawn loop"
  phase) and only then calls `spawned/1` to reset the counter; a
  `ready?` camp that can't find a free landing tile keeps its counter
  climbing so it fires again as soon as a tile is free.

  ## Camp assault (story 894, pragdave decomposition slice 4)

  `attack_camp/4` and `resolve_camp_attack/3` are the pragdave-pattern
  "domain model" home (`.code_my_spec/knowledge/genserver_decomposition.md`)
  for the unit-vs-camp "attack_camp" flow `BrokenOaths.Simulation.WorldServer`
  used to bury inline: they take the WorldServer's own tick-`state` (see
  `BrokenOaths.Simulation.Turn`'s moduledoc for that shape) plus plain args and
  return either a reply tuple or an updated `state` — no `GenServer`, no
  `handle_*`, no process awareness. `WorldServer`'s own `:attack_camp`
  `handle_call` is a thin delegation into `attack_camp/4`, mirroring
  `BrokenOaths.Combat.Resolver`'s own "Attack orchestration" section for
  unit-vs-unit combat. Coordinates its siblings directly, per the north
  star's "cross-cutting operations are orchestrated by their OWNING
  domain model calling its siblings" rule: `BrokenOaths.Combat.Resolver` for
  the flat camp-damage math and adjacency/target-legality validation,
  `BrokenOaths.Diplomacy.Cooperation` for the per-player damage ledger and
  proportional bounty split once a camp falls.

  ## Determinism

  Placement rolls are seeded from a caller-supplied term (typically
  `{world.seed, city_tile_id}`) via `:rand.seed_s/2` — the same
  functional, non-global pattern `BrokenOaths.Combat.Resolver` and
  `BrokenOaths.Worlds.Noise` already use. The same seed always yields
  the same placement.
  """

  alias BrokenOaths.Combat.Resolver
  alias BrokenOaths.Diplomacy.Cooperation
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.World

  @type tile_id :: non_neg_integer()
  @type camp :: %{
          id: term(),
          tile_id: tile_id(),
          hp: non_neg_integer(),
          spawn_counter: non_neg_integer(),
          destroyed_at: term() | nil
        }
  @type attack_outcome :: %{damage_dealt: non_neg_integer(), damage_taken: non_neg_integer()}

  @spawn_cadence 3
  @max_warriors 2
  @near_count 1..2
  # Narrowed 4..6 -> 4..5 (v0.2.1 playtest balance pass, issue
  # 04931763): one fewer far camp on average, easing peak simultaneous
  # wilderness pressure. See this module's own doc for the numbers.
  @far_count 4..5
  @ring_min 8
  @ring_max 15
  @destroy_reward 30
  # Minimum raw mesh-adjacency distance (hexes) a newly-picked camp
  # must keep from every OTHER camp already picked in this same
  # `place_wilderness/6` call (near-to-near, far-to-far, and
  # near-to-far) — the direct fix for the "camps too close together"
  # half of the v0.2.1 playtest report (issue 04931763). Deliberately
  # small relative to the 8-15 ring band's own size: enough to break
  # up literal clustering without starving placement in a tight
  # region/ring intersection.
  @min_camp_spacing 3

  @doc "Gold paid to the destroying player when a camp is reduced to 0 HP (story 894)."
  @spec destroy_reward() :: pos_integer()
  def destroy_reward, do: @destroy_reward

  # -------------------------------------------------------------------
  # Placement
  # -------------------------------------------------------------------

  @doc """
  First-founding wilderness placement: see this module's doc. Returns a
  flat list of tile ids (1-2 near, 4-5 far — 5-7 total), no two of them
  within `@min_camp_spacing` hexes of one another. `occupied_tiles`
  (current unit positions) is excluded from every candidate pool so a
  camp never lands under a player's own Lord.
  """
  @spec place_wilderness(
          World.t(),
          tile_id(),
          MapSet.t(tile_id()),
          MapSet.t(tile_id()),
          MapSet.t(tile_id()),
          term()
        ) :: [tile_id()]
  def place_wilderness(world, city_tile_id, home_region_tiles, explored_tiles, occupied_tiles, seed) do
    reachable = land_reachable_tiles(world, city_tile_id)

    {near, taken} =
      pick_near(world, city_tile_id, home_region_tiles, occupied_tiles, reachable, seed)

    {far, _taken} =
      pick_far(
        world,
        city_tile_id,
        home_region_tiles,
        explored_tiles,
        occupied_tiles,
        reachable,
        seed,
        taken
      )

    near ++ far
  end

  defp pick_near(world, city_tile_id, home_region_tiles, occupied_tiles, reachable, seed) do
    # In-region camps obey the same 8-15 hex distance band as the far
    # ones (story 892 rule; QA issue ebe8abf1 — without the band a camp
    # could land on the founding city's doorstep and make the early
    # game unsurvivable). Regions too small to reach the full band fall
    # back to 4+ hexes: outside the founding ring, never adjacent.
    candidates = near_candidates(world, city_tile_id, home_region_tiles, occupied_tiles, @ring_min)

    candidates =
      if candidates == [],
        do: near_candidates(world, city_tile_id, home_region_tiles, occupied_tiles, 4),
        else: candidates

    count = seeded_int({seed, :near_count}, @near_count)
    seeded_pick_preferring_land(candidates, count, world, reachable, {seed, :near_pick}, MapSet.new())
  end

  defp near_candidates(world, city_tile_id, home_region_tiles, occupied_tiles, min_ring) do
    band = world |> ring_band(city_tile_id, min_ring, @ring_max) |> MapSet.new()

    home_region_tiles
    |> MapSet.delete(city_tile_id)
    |> Enum.filter(&MapSet.member?(band, &1))
    |> Enum.reject(&MapSet.member?(occupied_tiles, &1))
    |> Enum.sort()
  end

  defp pick_far(world, city_tile_id, home_region_tiles, explored_tiles, occupied_tiles, reachable, seed, taken) do
    candidates =
      world
      |> ring_band(city_tile_id, @ring_min, @ring_max)
      |> Enum.reject(&MapSet.member?(home_region_tiles, &1))
      |> Enum.reject(&MapSet.member?(explored_tiles, &1))
      |> Enum.reject(&MapSet.member?(occupied_tiles, &1))
      |> Enum.sort()

    count = seeded_int({seed, :far_count}, @far_count)
    seeded_pick_preferring_land(candidates, count, world, reachable, {seed, :far_pick}, taken)
  end

  # Every `:land` tile walkable from `start` without leaving land —
  # the same graph `WorldServer`'s BFS move pathfinding traverses
  # (`Regions.tile_class/2 == :land`, mountains and water impassable).
  # A single flood-fill from the founding city, reused for both the
  # near and far candidate pools.
  defp land_reachable_tiles(world, start) do
    grow_land(world, MapSet.new([start]), [start])
  end

  defp grow_land(_world, seen, []), do: seen

  defp grow_land(world, seen, frontier) do
    next =
      frontier
      |> Enum.flat_map(&Regions.adjacent_tiles(world, &1))
      |> Enum.uniq()
      |> Enum.filter(&(Regions.tile_class(world, &1) == :land and not MapSet.member?(seen, &1)))

    grow_land(world, MapSet.union(seen, MapSet.new(next)), next)
  end

  # Tiles whose raw mesh-adjacency distance from `start` is in
  # `min_depth..max_depth` (inclusive) — the annulus between the
  # `min_depth - 1` ring and the `max_depth` ring.
  defp ring_band(world, start, min_depth, max_depth) do
    inner = grow_ring(world, start, min_depth - 1)
    outer = grow_ring(world, start, max_depth)
    MapSet.difference(outer, inner)
  end

  defp grow_ring(_world, start, 0), do: MapSet.new([start])

  defp grow_ring(world, start, depth) do
    {_frontier, seen} =
      Enum.reduce(1..depth, {[start], MapSet.new([start])}, fn _, {frontier, seen} ->
        next =
          frontier
          |> Enum.flat_map(&Regions.adjacent_tiles(world, &1))
          |> Enum.uniq()
          |> Enum.reject(&MapSet.member?(seen, &1))

        {next, MapSet.union(seen, MapSet.new(next))}
      end)

    seen
  end

  # -------------------------------------------------------------------
  # Spawn cadence
  # -------------------------------------------------------------------

  @doc """
  Advance a camp's spawn counter by one tick. Returns `{camp, ready?}` —
  `ready?` is true once the 3-turn cadence is reached AND `alive_count`
  is below the 2-warrior cap. `resolve_spawns/2` below finds a landing tile and calls
  `spawned/1` once a warrior is actually placed; a camp that stays `ready?` without a free tile, or above cap,
  simply keeps counting. A destroyed camp is never ready.
  """
  @spec advance(camp(), non_neg_integer()) :: {camp(), boolean()}
  def advance(%{destroyed_at: destroyed_at} = camp, _alive_count) when not is_nil(destroyed_at) do
    {camp, false}
  end

  def advance(camp, alive_count) when alive_count >= @max_warriors do
    # At cap the counter HOLDS at zero instead of climbing: the rule is
    # "re-spawning one every 3 turns only while below the cap", so a
    # kill buys attackers a full 3-turn grace before the replacement.
    # The climbing-counter version made camps unclearable in practice —
    # a freed slot refilled on the very next tick (QA issue: reaching a
    # camp cost 25+ units because guards respawned instantly).
    {%{camp | spawn_counter: 0}, false}
  end

  def advance(camp, _alive_count) do
    counter = camp.spawn_counter + 1
    {%{camp | spawn_counter: counter}, counter >= @spawn_cadence}
  end

  @doc "Reset a camp's spawn counter after a warrior has actually been placed."
  @spec spawned(camp()) :: camp()
  def spawned(camp), do: %{camp | spawn_counter: 0}

  # -------------------------------------------------------------------
  # Tick-loop spawn resolution (story 892 — moved from `BrokenOaths.Game.
  # Turn`'s own private `resolve_camp_spawns/2`, the tick-decomposition
  # pass, see `.code_my_spec/knowledge/genserver_decomposition.md`)
  # -------------------------------------------------------------------

  @doc """
  Advance every camp's spawn cadence for one tick and place a warrior
  for any camp that comes ready with a free landing tile (its own tile,
  else an adjacent land tile, mirroring `BrokenOaths.Cities.Production`'s
  own city landing-tile pick). Reuses `occupied` — the SAME occupied-
  tile thread `BrokenOaths.Cities.Production.resolve_completions/1`
  builds — so a camp spawn can't land on a tile a city completion
  claimed this same tick, and vice versa. The updated set is returned
  too, for the barbarian-AI phase that follows: a warrior placed THIS
  tick by either loop (not yet in `state.units`) still reserves its
  tile against an already-existing barbarian roaming or hunting onto
  it. `state` is the canonical tick-state described in
  `BrokenOaths.Simulation.Turn`.

  Returns `{new_state, spawn_events, occupied}`.
  """
  @spec resolve_spawns(map(), map()) :: {map(), [map()], map()}
  def resolve_spawns(state, occupied) do
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
  # `BrokenOaths.Simulation.Turn`'s own `pending_heirs` reads unfamiliar keys
  # elsewhere in the canonical tick-state.
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
    {advanced, ready?} = advance(camp, alive_count)

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
        spawned_camp = spawned(camp)
        {Map.put(camps, camp.id, spawned_camp), [event | events], Map.put(occupied, tile, true)}
    end
  end

  # A camp's own tile first, then its adjacent land tiles (sorted for
  # determinism) — mirrors `BrokenOaths.Cities.Production`'s own city
  # landing-tile pick, so a second warrior lands beside the first
  # rather than failing to spawn.
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
  # Camp assault (story 894) — moved home from `BrokenOaths.Game.
  # WorldServer`'s own `do_attack_camp/4`/`resolve_camp_attack/3`; see
  # this module's own "Camp assault" moduledoc section above.
  # -------------------------------------------------------------------

  @doc """
  Resolve an immediate "attack_camp" request: `user`'s own `unit_id`
  strikes `camp_id` right now, against whatever movement the attacker
  has left — flat damage, no counter-attack (`Resolver.camp_damage/2`),
  resolving immediately like `Resolver.attack/4` rather than queuing. An
  already-destroyed (or nonexistent) camp is refused the same way an
  already-dead unit target is. `WorldServer`'s own `:attack_camp`
  `handle_call` wraps this with persistence and the broadcast.
  """
  @spec attack_camp(map(), map(), term(), term()) ::
          {:ok, attack_outcome(), map()} | {:error, term()}
  def attack_camp(state, user, unit_id, camp_id) do
    player = find_player(state, user.id)
    attacker = Map.get(state.units, unit_id)
    camp = Map.get(state.camps, camp_id)

    cond do
      is_nil(player) or is_nil(attacker) or attacker.player_id != player.id ->
        {:error, :not_owner}

      is_nil(camp) or not is_nil(camp.destroyed_at) ->
        {:error, :invalid_target}

      true ->
        adjacent_tile_ids = Regions.adjacent_tiles(state.world, attacker.tile_id)

        case Resolver.validate_camp_attack(attacker, camp, adjacent_tile_ids) do
          :ok ->
            {result, new_state} = resolve_camp_attack(state, attacker, camp)
            {:ok, result, new_state}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Resolve a single already-validated camp exchange: `attack_camp/4`'s
  own post-`Resolver.validate_camp_attack/3` step.
  """
  @spec resolve_camp_attack(map(), map(), camp()) :: {attack_outcome(), map()}
  def resolve_camp_attack(state, attacker, camp) do
    dealt = Resolver.camp_damage(attacker, lord_adjacent?(state, attacker))
    new_camp = %{camp | hp: max(camp.hp - dealt, 0)}
    new_attacker = %{attacker | movement: 0}

    state =
      %{state | units: Map.put(state.units, attacker.id, new_attacker)}
      |> record_camp_damage(camp.id, attacker.player_id, dealt)
      |> apply_camp_damage(new_camp)

    {%{damage_dealt: dealt, damage_taken: 0}, state}
  end

  # Story 901: every hit against a camp — from ANY player, not just
  # whoever eventually lands the killing blow — accumulates in the
  # in-memory damage ledger `apply_camp_damage/2`'s own `Cooperation.
  # split_bounty/3` call reads once the camp falls. Kept only in memory
  # (`state.camp_contributions`), never persisted — same known, narrow
  # limitation `WorldServer`'s own `pending_heirs` doc calls out for
  # equally ephemeral cross-tick bookkeeping: a restart mid-siege loses
  # the running tally (the camp's own HP, being a real persisted
  # column, is unaffected).
  defp record_camp_damage(state, camp_id, player_id, dealt) do
    contributions =
      Cooperation.record_damage(camp_contributions(state), camp_id, player_id, dealt)

    Map.put(state, :camp_contributions, contributions)
  end

  defp camp_contributions(state), do: Map.get(state, :camp_contributions, %{})

  # Story 894/901, criterion 7560/7614/7615: 0 HP destroys the camp —
  # `destroyed_at` stops `advance/2` from ever spawning again and drops
  # it from `WorldServer`'s fog-filtered `visible_camps/2` surface.
  # `destroy_reward/0` splits proportionally across every player who
  # ever struck THIS camp (`Cooperation.split_bounty/3`, reading the
  # ledger `record_camp_damage/3` built above) — a sole attacker's own
  # 100% share is still the WHOLE reward, never a smaller "default" cut
  # (criterion 7615). The ledger entry is forgotten immediately after: a
  # camp is destroyed exactly once, and nothing else ever reads its
  # history. Orphaned warriors are untouched — they're separate `Unit`
  # rows, not nested under the camp in `state.units` (criterion 7561).
  defp apply_camp_damage(state, %{hp: 0} = camp) do
    destroyed = %{camp | destroyed_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)}
    shares = Cooperation.split_bounty(camp_contributions(state), camp.id, destroy_reward())

    %{state | camps: Map.put(state.camps, camp.id, destroyed)}
    |> pay_shares(shares)
    |> Map.put(:camp_contributions, Cooperation.forget(camp_contributions(state), camp.id))
  end

  defp apply_camp_damage(state, camp) do
    %{state | camps: Map.put(state.camps, camp.id, camp)}
  end

  # Story 904: every contributor paid a reward share also gets their
  # own `camps_destroyed` career total bumped — the same "credit
  # everyone who struck it, not just the killing blow" philosophy
  # `Cooperation.split_bounty/3` already applies to the gold itself.
  defp pay_shares(state, shares) do
    Enum.reduce(shares, state, fn {player_id, gold}, acc ->
      acc = update_in(acc.players[player_id].gold, &(&1 + gold))
      update_in(acc.players[player_id].camps_destroyed, &(&1 + 1))
    end)
  end

  # A living unit of the SAME player standing next door — dead units
  # are already gone from `state.units`, so presence alone means
  # living, and a lord's own tile is never its own neighbor, so this
  # never accidentally self-buffs the lord. Duplicated (not shared)
  # into `BrokenOaths.Combat.Resolver`/`WorldServer` per this codebase's own
  # established "small pure state-accessor helpers live wherever
  # they're needed" convention (see e.g. `Combat`'s own
  # `lord_adjacent?/2`).
  defp lord_adjacent?(state, unit) do
    adjacent_tile_ids = Regions.adjacent_tiles(state.world, unit.tile_id)

    state.units
    |> Map.values()
    |> Enum.any?(
      &(&1.type == :lord and &1.player_id == unit.player_id and &1.tile_id in adjacent_tile_ids)
    )
  end

  defp find_player(state, user_id) do
    state.players |> Map.values() |> Enum.find(&(&1.user_id == user_id))
  end

  # -------------------------------------------------------------------
  # Seeded random selection
  # -------------------------------------------------------------------

  # Three-tier fallback — see this module's doc: walkable land first,
  # then any other land, then anything at all. Each tier only reaches
  # into the next if the one before can't fill `count`. `taken` is this
  # founding's own running "already placed a camp here" accumulator
  # (near AND far share it — see `place_wilderness/6`), threaded
  # through and returned so every subsequent pick, in either pool,
  # keeps its distance from every camp already placed.
  defp seeded_pick_preferring_land(candidates, count, world, reachable, seed, taken) do
    {land, rest} = Enum.split_with(candidates, &(Regions.tile_class(world, &1) == :land))
    {walkable, stranded} = Enum.split_with(land, &MapSet.member?(reachable, &1))

    {picked1, taken1} = seeded_pick_spaced(walkable, count, world, {seed, :walkable}, taken)

    {picked2, taken2} =
      seeded_pick_spaced(stranded, count - length(picked1), world, {seed, :stranded}, taken1)

    {picked3, taken3} =
      seeded_pick_spaced(rest, count - length(picked1) - length(picked2), world, {seed, :fallback}, taken2)

    {picked1 ++ picked2 ++ picked3, taken3}
  end

  # Picks up to `count` tiles, keeping every pick at least
  # `@min_camp_spacing` hexes from every tile in `taken` (this
  # founding's own already-placed camps, near and far alike) AND from
  # each other. Candidates are ranked by the same seeded roll
  # `seeded_pick/3` always used, so which tiles WOULD have won without
  # spacing stays deterministic; spacing only skips over a candidate
  # that lands too close, same greedy shape a Civ-style "minimum
  # distance between X" rule always takes. If spacing alone can't fill
  # `count` (a small/crowded candidate pool near the founding), the
  # remainder fills from whatever candidates are left, WITHOUT the
  # spacing constraint, in that same ranked order — the placement
  # count guarantee (`place_wilderness/6`'s own moduledoc) never
  # comes up short over a cosmetic spacing preference.
  defp seeded_pick_spaced(candidates, count, world, seed, taken) when count > 0 do
    ranked = ranked_candidates(candidates, seed)
    {spaced, taken1} = greedy_take_spaced(world, ranked, count, taken, [])

    if length(spaced) == count do
      {spaced, taken1}
    else
      leftover = ranked -- spaced
      extra = Enum.take(leftover, count - length(spaced))
      {spaced ++ extra, MapSet.union(taken1, MapSet.new(extra))}
    end
  end

  defp seeded_pick_spaced(_candidates, _count, _world, _seed, taken), do: {[], taken}

  defp greedy_take_spaced(_world, _candidates, count, taken, acc) when count <= 0,
    do: {Enum.reverse(acc), taken}

  defp greedy_take_spaced(_world, [], _count, taken, acc), do: {Enum.reverse(acc), taken}

  defp greedy_take_spaced(world, [tile | rest], count, taken, acc) do
    if far_from_taken?(world, tile, taken) do
      greedy_take_spaced(world, rest, count - 1, MapSet.put(taken, tile), [tile | acc])
    else
      greedy_take_spaced(world, rest, count, taken, acc)
    end
  end

  defp far_from_taken?(world, tile, taken) do
    exclusion_radius = @min_camp_spacing - 1

    not Enum.any?(taken, fn already ->
      MapSet.member?(grow_ring(world, already, exclusion_radius), tile)
    end)
  end

  # Deterministic seeded ranking — every candidate gets one seeded roll,
  # sorted ascending, so which tiles WOULD win a plain top-`count` take
  # stays fully seed-derived; `seeded_pick_spaced/5` layers the spacing
  # walk on top of this same order.
  defp ranked_candidates(candidates, seed) do
    state = :rand.seed_s(:exsss, seed_tuple(seed))

    {keyed, _state} =
      Enum.map_reduce(candidates, state, fn tile, st ->
        {roll, next_st} = :rand.uniform_s(st)
        {{roll, tile}, next_st}
      end)

    keyed |> Enum.sort() |> Enum.map(&elem(&1, 1))
  end

  defp seeded_int(seed, min..max//_) do
    state = :rand.seed_s(:exsss, seed_tuple(seed))
    {roll, _state} = :rand.uniform_s(max - min + 1, state)
    min + roll - 1
  end

  defp seed_tuple(term) do
    h = :erlang.phash2(term, 1_000_000_000)
    {h, h * 7 + 13, h * 31 + 97}
  end
end
