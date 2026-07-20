defmodule BrokenOaths.Game.BarbarianAI do
  @moduledoc """
  Pure barbarian decision core: per-boundary target selection, one-hex
  step planning, and near-camp roaming. No `Repo`, no process state —
  mirrors `BrokenOaths.Game.Combat`/`BrokenOaths.Game.Camps`'s role:
  `BrokenOaths.Game.Turn` is the imperative-adjacent shell that reads a
  camp-spawned barbarian warrior out of its canonical tick-state, calls
  `decide/5` for that warrior, and applies the result (movement,
  `Combat.resolve/3`, pillage) back into the tick.

  ## Decision order (criteria 7551-7555)

  `decide/5` picks exactly one action per barbarian per boundary:

    1. **Attack** — any living player-owned unit standing on an
       adjacent tile is struck immediately (`Combat.resolve/3`
       handles the simultaneous exchange; this module only picks the
       target). A barbarian never targets another barbarian here —
       candidates are filtered to `player_id != nil` — so two
       warriors from the same camp, however close, never fight
       (criterion 7555). Ties (more than one adjacent unit) break on
       the lowest unit id.
    2. **Move toward the nearest target** — otherwise, the nearest of
       every UNDEFENDED player city (no unit garrisoned on the city's
       own tile) and every player unit within `@aggro_range` (5) hexes
       of land-path distance OF THE BARBARIAN'S OWN CURRENT TILE, AND
       within `@leash_range` (5, same as `@aggro_range`) of its home
       camp — a camp-spawned
       warrior only ever operates within a bounded neighborhood of
       where it was born, never chasing indefinitely far from home just
       because it happened to roam within 5 hexes of a passer-by (a
       warrior with no camp — orphaned, story 894 criterion 7561 — has
       no such leash, since it has no home left to bound it against).
       An undefended city in range is preferred over ANY unit in range,
       regardless of relative distance (Three Amigos: "when both a city
       and a unit are candidates, the city wins" — criterion 7554); ties
       within a candidate class break on distance, then lowest id.
       Movement is exactly one hex along a shortest land path toward the
       target's tile (never onto it — city-tile entry is story 895's
       job; a unit's own tile is never entered either, since combat
       happens by adjacency, not occupation). Already adjacent to a
       chosen city (nothing left to attack there yet) is a hold, not a
       walk onto the city.
    3. **Roam** — nothing in (leashed) range: a deterministic, seeded
       step to a land tile within `@roam_radius` (2) hexes of the
       warrior's own camp, or a hold if none reads better than staying.

  Land-path distance (used for both range-checking and roam radius) is
  the same "how many hexes away, over passable land only" notion
  `BrokenOaths.Game.Camps`/`BrokenOaths.Game.WorldServer`'s move
  pathfinding already use — never raw mesh-adjacency ring distance.

  ## Determinism

  The roam choice is seeded from a caller-supplied term (typically
  `{world.seed, turn, barbarian.id}`) via `:rand.seed_s/2` — the same
  functional, non-global pattern `BrokenOaths.Game.Combat` and
  `BrokenOaths.Game.Camps` already use. Two callers deciding the same
  barbarian from the same tick-state always agree.

  ## Pillage and bounty

  This module has no opinion on WHAT happens when a barbarian enters a
  tile with a completed improvement, or WHAT happens when a barbarian
  dies in combat — those are `BrokenOaths.Cities.Improvement.pillage/1`
  and this module's own `bounty_gold/0` constant, applied by the
  caller (`Turn`) once it knows the decision actually resolved that
  way.
  """

  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.World

  @type tile_id :: non_neg_integer()
  @type unit :: %{
          id: term(),
          player_id: term() | nil,
          type: atom(),
          tile_id: tile_id(),
          hp: non_neg_integer(),
          max_hp: pos_integer(),
          movement: non_neg_integer(),
          max_movement: non_neg_integer()
        }
  @type city :: %{optional(atom()) => term(), id: term(), tile_id: tile_id()}
  @type decision :: {:attack, term()} | {:move, tile_id()} | :hold

  @aggro_range 5
  @roam_radius 2
  @leash_range @aggro_range
  @bounty_gold 10

  @doc "Gold paid to a player whenever a barbarian warrior dies in combat against them."
  @spec bounty_gold() :: pos_integer()
  def bounty_gold, do: @bounty_gold

  @doc """
  Decide one barbarian's action this boundary — see this module's doc
  for the full priority order. `camp_tile` is the warrior's OWN camp's
  tile (`nil` roams nowhere and simply holds — a defensive fallback for
  an orphaned camp id, though `Turn` never actually calls this without
  one). `occupied` is every tile currently held by a unit (the
  barbarian's own tile included), used only to keep a step or a roam
  from landing on top of someone.
  """
  @spec decide(World.t(), unit(), tile_id() | nil, [unit()], [city()], keyword()) :: decision()
  def decide(world, barbarian, camp_tile, units, cities, opts \\ []) do
    occupied = Keyword.get(opts, :occupied, MapSet.new())
    seed = Keyword.fetch!(opts, :seed)

    adjacent = Regions.adjacent_tiles(world, barbarian.tile_id)

    case adjacent_target(units, adjacent) do
      %{id: target_id} -> {:attack, target_id}
      nil -> decide_movement(world, barbarian, camp_tile, units, cities, occupied, seed)
    end
  end

  defp adjacent_target(units, adjacent_tile_ids) do
    units
    |> Enum.filter(&(&1.player_id != nil and &1.tile_id in adjacent_tile_ids))
    |> Enum.sort_by(& &1.id)
    |> List.first()
  end

  defp decide_movement(world, barbarian, camp_tile, units, cities, occupied, seed) do
    case nearest_target(world, barbarian.tile_id, camp_tile, units, cities) do
      nil ->
        roam(world, barbarian, camp_tile, occupied, seed)

      {_kind, _id, _tile, distance} when distance <= 1 ->
        :hold

      {_kind, _id, tile, _distance} ->
        case step_toward(world, barbarian.tile_id, tile, occupied) do
          nil -> roam(world, barbarian, camp_tile, occupied, seed)
          next -> {:move, next}
        end
    end
  end

  # -------------------------------------------------------------------
  # Target selection
  # -------------------------------------------------------------------

  # Every undefended city in range beats every unit in range, no matter
  # which is closer — see this module's doc. Within a class, nearest
  # wins; ties break on lowest id for determinism. Candidates are ALSO
  # bounded by `@leash_range` of `camp_tile` (nil — an orphaned warrior,
  # story 894 criterion 7561 — means no leash at all).
  defp nearest_target(world, from, camp_tile, units, cities) do
    distances = land_distances(world, from, @aggro_range)
    leash = camp_tile && land_distances(world, camp_tile, @leash_range)

    case ranked_candidates(:city, undefended_cities(cities, units), distances, leash) do
      [best | _] ->
        best

      [] ->
        candidates = Enum.filter(units, &(&1.player_id != nil))
        ranked_candidates(:unit, candidates, distances, leash) |> List.first()
    end
  end

  defp undefended_cities(cities, units) do
    Enum.reject(cities, fn city -> Enum.any?(units, &(&1.tile_id == city.tile_id)) end)
  end

  defp ranked_candidates(kind, candidates, distances, leash) do
    candidates
    |> Enum.map(&{kind, &1.id, &1.tile_id, Map.get(distances, &1.tile_id)})
    |> Enum.reject(fn {_kind, _id, _tile, distance} -> is_nil(distance) end)
    |> Enum.filter(fn {_kind, _id, tile, _distance} -> within_leash?(leash, tile) end)
    |> Enum.sort_by(fn {_kind, id, _tile, distance} -> {distance, id} end)
  end

  defp within_leash?(nil, _tile), do: true
  defp within_leash?(leash, tile), do: Map.has_key?(leash, tile)

  # -------------------------------------------------------------------
  # Roaming
  # -------------------------------------------------------------------

  defp roam(_world, _barbarian, nil, _occupied, _seed), do: :hold

  defp roam(world, barbarian, camp_tile, occupied, seed) do
    distances_from_camp = land_distances(world, camp_tile, @roam_radius)

    candidates =
      world
      |> Regions.adjacent_tiles(barbarian.tile_id)
      |> Enum.filter(&(Regions.tile_class(world, &1) == :land))
      |> Enum.filter(&Map.has_key?(distances_from_camp, &1))
      |> Enum.reject(&MapSet.member?(occupied, &1))
      |> Enum.uniq()
      |> Enum.sort()

    case seeded_pick([barbarian.tile_id | candidates] |> Enum.uniq(), {seed, :roam}) do
      tile when tile == barbarian.tile_id -> :hold
      tile -> {:move, tile}
    end
  end

  # -------------------------------------------------------------------
  # Pathfinding
  # -------------------------------------------------------------------

  # The first hex of a shortest land path from `from` toward `to`.
  # `occupied` tiles are impassable as intermediate steps; `to` itself
  # may be occupied (approaching a unit or an undefended city tile is
  # legal — the caller never actually lets a barbarian step ONTO `to`,
  # since `nearest_target/4` only reaches here at distance > 1).
  defp step_toward(world, from, to, occupied) do
    case bfs_path(world, from, to, occupied) do
      [] -> nil
      [next | _rest] -> next
    end
  end

  defp bfs_path(world, from, to, occupied) do
    bfs_loop(world, occupied, :queue.from_list([{from, []}]), MapSet.new([from]), to)
  end

  defp bfs_loop(world, occupied, queue, visited, to) do
    case :queue.out(queue) do
      {:empty, _queue} ->
        []

      {{:value, {^to, path}}, _rest} ->
        Enum.reverse(path)

      {{:value, {tile, path}}, rest} ->
        neighbors =
          world
          |> Regions.adjacent_tiles(tile)
          |> Enum.filter(
            &(Regions.tile_class(world, &1) == :land and not MapSet.member?(visited, &1) and
                (&1 == to or not MapSet.member?(occupied, &1)))
          )

        {queue, visited} =
          Enum.reduce(neighbors, {rest, visited}, fn n, {q, v} ->
            {:queue.in({n, [n | path]}, q), MapSet.put(v, n)}
          end)

        bfs_loop(world, occupied, queue, visited, to)
    end
  end

  # Every `:land` tile's hex distance from `start` over passable land
  # only, up to `max_depth` — `start` itself is included at depth 0.
  defp land_distances(world, start, max_depth) do
    grow_distances(world, %{start => 0}, [start], 1, max_depth)
  end

  defp grow_distances(_world, distances, _frontier, depth, max_depth) when depth > max_depth,
    do: distances

  defp grow_distances(_world, distances, [], _depth, _max_depth), do: distances

  defp grow_distances(world, distances, frontier, depth, max_depth) do
    next =
      frontier
      |> Enum.flat_map(&Regions.adjacent_tiles(world, &1))
      |> Enum.uniq()
      |> Enum.filter(&(Regions.tile_class(world, &1) == :land and not Map.has_key?(distances, &1)))

    grow_distances(world, Enum.reduce(next, distances, &Map.put(&2, &1, depth)), next, depth + 1, max_depth)
  end

  # -------------------------------------------------------------------
  # Seeded random selection
  # -------------------------------------------------------------------

  defp seeded_pick([single], _seed), do: single

  defp seeded_pick(candidates, seed) do
    state = :rand.seed_s(:exsss, seed_tuple(seed))
    {roll, _state} = :rand.uniform_s(length(candidates), state)
    Enum.at(candidates, roll - 1)
  end

  defp seed_tuple(term) do
    h = :erlang.phash2(term, 1_000_000_000)
    {h, h * 7 + 13, h * 31 + 97}
  end
end
