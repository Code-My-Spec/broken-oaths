defmodule BrokenOaths.Game.Camps do
  @moduledoc """
  Pure barbarian-camp core: first-founding wilderness placement and the
  per-camp spawn cadence. No `Repo`, no process state — mirrors
  `BrokenOaths.Game.Spawner`'s role for camps: `BrokenOaths.Game.Turn`
  and `BrokenOaths.Game.WorldServer` are the imperative shells that read
  camps out of the canonical tick-state, call into this module, and
  write the result back.

  ## Placement (first founding only — criterion 7543)

  `place_wilderness/6` picks two clusters of tiles, both pure functions
  of a caller-supplied `seed` term (see the determinism note below):

    * 1-2 tiles already inside the founding player's own claimed
      region — "near" camps, immediately known to the player because
      they're on home turf (no fog-of-war roll needed for them; see
      `BrokenOaths.Game.WorldServer`'s camp-visibility filter).
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
  this camp's id — see `BrokenOaths.Game.Turn`'s "camp spawn loop"
  phase) and only then calls `spawned/1` to reset the counter; a
  `ready?` camp that can't find a free landing tile keeps its counter
  climbing so it fires again as soon as a tile is free.

  ## Determinism

  Placement rolls are seeded from a caller-supplied term (typically
  `{world.seed, city_tile_id}`) via `:rand.seed_s/2` — the same
  functional, non-global pattern `BrokenOaths.Game.Combat` and
  `BrokenOaths.Worlds.Noise` already use. The same seed always yields
  the same placement.
  """

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
  is below the 2-warrior cap. The caller (`BrokenOaths.Game.Turn`) finds
  a landing tile and calls `spawned/1` once a warrior is actually
  placed; a camp that stays `ready?` without a free tile, or above cap,
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
