defmodule BrokenOaths.Game.Production do
  @moduledoc """
  Pure production core: the Stone Age buildable catalog (Settler 100,
  Worker 60, Warrior 40, Granary 60 — Monument is still out of scope,
  see story 879's own criteria) with per-type unit stats, per-turn
  production accrual, queue completion with overflow carry-over,
  completed-unit spawn placement, the settler population cost and
  size-1 guard, and city-founding validation (terrain, 4-hex spacing).
  No `Repo`: `complete/3` returns spawn intents as data (`spawn_event`)
  rather than inserting units itself — `BrokenOaths.Game.WorldServer`
  is the only place real unit ids get allocated.

  ## The flat production base

  Every city banks a flat 5 production per turn regardless of size or
  terrain (story 879), on top of its worked tiles' production —
  deliberately NOT the city center's own terrain-based production
  (that stays folded into the flat base; see
  `BrokenOaths.Game.Yields`'s moduledoc). Food has no such override:
  the center's food floor accrues separately via
  `BrokenOaths.Game.Yields.accrue_food/3`.

  ## Queue completion

  `complete/3` is a loop, not a single check: an overflow big enough to
  finish the next queued item too keeps cascading, and a fully blocked
  city (no free landing tile) simply stops with its current item's
  `banked` intact — nothing is lost, it just keeps growing next turn
  until a tile frees up (story 879, criterion 7472).

  ## The Granary (story 902, criterion 7629)

  Unlike every other buildable, `:granary` is a BUILDING, not a unit:
  it needs no landing tile (`spawnable?/2`'s free-tile gate never
  applies to it) and its completion never produces a `spawn_event` —
  instead it flips `has_granary: true` directly on the completing city
  (read back by `BrokenOaths.Game.Yields.accrue_food/3` for its +2
  food/turn bonus, the same "unlock flips a flag, read back on demand"
  pattern `BrokenOaths.Game.Research` already documents for its own
  unlocks). Gated on the city's OWNER having completed Pottery
  (`can_queue?/3`'s `granary_available?` option — `Production` itself
  never touches `BrokenOaths.Game.Research`, so the caller, `WorldServer`,
  resolves that flag and passes it in) and on the city not already
  having one (`:already_built` — a Granary is built once, ever).
  """

  alias BrokenOaths.Game.Yields
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.World

  @type tile_id :: non_neg_integer()
  @type unit_buildable :: :settler | :worker | :warrior | :bronze_spearman
  @type buildable :: unit_buildable() | :granary
  @type unit_type :: :lord | :settler | :warrior | :worker | :barbarian_warrior | :bronze_spearman

  @type queue_item :: %{
          optional(:id) => term(),
          type: buildable(),
          banked: non_neg_integer(),
          cost: pos_integer()
        }

  @type city :: %{
          required(:player_id) => term(),
          required(:tile_id) => tile_id(),
          required(:size) => pos_integer(),
          required(:territory) => [tile_id()],
          required(:worked_tiles) => [tile_id()],
          required(:queue) => [queue_item()],
          optional(:has_granary) => boolean(),
          optional(atom()) => term()
        }

  @type spawn_event :: %{player_id: term(), type: unit_buildable(), tile_id: tile_id()}
  @type can_queue_error :: :size_one | :locked | :already_built

  @flat_production 5
  @min_founding_spacing 4

  @catalog %{settler: 100, worker: 60, warrior: 40, granary: 60, bronze_spearman: 60}

  @unit_stats %{
    lord: %{hp: 150, movement: 2},
    settler: %{hp: 50, movement: 2},
    warrior: %{hp: 100, movement: 1},
    worker: %{hp: 10, movement: 2},
    barbarian_warrior: %{hp: 120, movement: 1},
    # Story 903 — `.code_my_spec/knowledge/civ6_tech_tree.md` §5.
    bronze_spearman: %{hp: 120, movement: 1}
  }

  @doc "The buildable catalog: `%{settler: 100, worker: 60, warrior: 40}`."
  @spec catalog() :: %{buildable() => pos_integer()}
  def catalog, do: @catalog

  @doc "Every city's flat per-turn production base, before worked-tile production."
  @spec flat_base() :: pos_integer()
  def flat_base, do: @flat_production

  @doc "Production cost of a buildable type."
  @spec cost(buildable()) :: pos_integer()
  def cost(type), do: Map.fetch!(@catalog, type)

  @doc "Starting `%{hp:, movement:}` for any unit type — Lord and Settler included."
  @spec unit_stats(unit_type()) :: %{hp: pos_integer(), movement: pos_integer()}
  def unit_stats(type), do: Map.fetch!(@unit_stats, type)

  @doc "A fresh queue item for `type`, unbanked. Caller attaches an `id` once persisted."
  @spec new_item(buildable()) :: queue_item()
  def new_item(type), do: %{type: type, banked: 0, cost: cost(type)}

  @doc """
  Whether `type` can be queued right now (arity-2, backward-compatible
  shorthand for `can_queue?/3` with no options — `granary_available?`
  simply defaults to `false`, so a Granary is refused unless the
  caller explicitly opts it in).
  """
  @spec can_queue?(city(), buildable()) :: :ok | {:error, can_queue_error()}
  def can_queue?(city, type), do: can_queue?(city, type, [])

  @doc """
  Whether `type` can be queued right now: the size-1 settler rule (a
  size-1 city has no population to spare; story 883, criterion 7487),
  and — for `:granary` only (story 902) — the city's owner having
  completed Pottery (`opts[:granary_available?]`, since this
  dependency-free module never calls `BrokenOaths.Game.Research`
  itself) and not already having one (`:already_built`). Story 903:
  `:bronze_spearman` is gated the same dependency-free way, on
  `opts[:bronze_age?]` — the caller (`WorldServer`) resolves the
  city owner's `Research.age/1` and passes it in.
  """
  @spec can_queue?(city(), buildable(), keyword()) :: :ok | {:error, can_queue_error()}
  def can_queue?(%{size: 1}, :settler, _opts), do: {:error, :size_one}

  def can_queue?(city, :granary, opts) do
    cond do
      Map.get(city, :has_granary, false) -> {:error, :already_built}
      not Keyword.get(opts, :granary_available?, false) -> {:error, :locked}
      true -> :ok
    end
  end

  def can_queue?(_city, :bronze_spearman, opts) do
    if Keyword.get(opts, :bronze_age?, false), do: :ok, else: {:error, :locked}
  end

  def can_queue?(_city, _type, _opts), do: :ok

  @always_available [:settler, :worker, :warrior]

  @doc """
  The buildable TYPES worth offering in a Build UI right now, given the
  same `opts` `can_queue?/3` reads (`:granary_available?`,
  `:bronze_age?`) — the always-available `:settler`/`:worker`/
  `:warrior` plus `:granary` once `opts[:granary_available?]` is true
  (story 902) and `:bronze_spearman` once `opts[:bronze_age?]` is true
  (story 903). Deliberately narrower than `catalog/0` (never `:lord`)
  but NOT the same question as `can_queue?/3`: an item stays in this
  list even when `can_queue?/3` would still refuse it for another
  reason (a size-1 city's Settler, an already-built city's Granary) —
  those refusals are `disabled` states in the UI, not list exclusions.
  This is the one gate a caller (`BrokenOathsWeb.GameLive.CityPanel`)
  must apply to avoid offering — or hiding — anything
  `can_queue?/3`/`WorldServer`'s `queue_production` command wouldn't
  agree on, since both read the identical `opts`.
  """
  @spec available_items(keyword()) :: [buildable()]
  def available_items(opts \\ []) do
    @always_available
    |> maybe_offer(:granary, Keyword.get(opts, :granary_available?, false))
    |> maybe_offer(:bronze_spearman, Keyword.get(opts, :bronze_age?, false))
  end

  defp maybe_offer(types, type, true), do: types ++ [type]
  defp maybe_offer(types, _type, false), do: types

  # -------------------------------------------------------------------
  # Accrual
  # -------------------------------------------------------------------

  @doc """
  Bank this turn's production (flat base + worked-tile production) into
  the current (head) queue item. A no-op with an empty queue — nothing
  is queued to receive it.
  """
  @spec accrue(city(), World.t(), map()) :: city()
  def accrue(%{queue: []} = city, _world, _improvements), do: city

  def accrue(%{queue: [current | rest]} = city, world, improvements) do
    income = @flat_production + worked_production(city, world, improvements)
    %{city | queue: [%{current | banked: current.banked + income} | rest]}
  end

  defp worked_production(city, world, improvements) do
    city
    |> Yields.worked_yields(world, improvements)
    |> Enum.map(& &1.production)
    |> Enum.sum()
  end

  # -------------------------------------------------------------------
  # Completion + spawn placement
  # -------------------------------------------------------------------

  @doc """
  Resolve as many completed queue items as banked production and free
  landing tiles allow. Returns `{new_city, spawn_events}`; each event
  is a placement intent for the caller to materialize into a real unit.
  """
  @spec complete(city(), %{tile_id() => term()}, World.t()) :: {city(), [spawn_event()]}
  def complete(city, occupied_tiles, world) do
    complete_loop(city, occupied_tiles, world, [])
  end

  defp complete_loop(%{queue: []} = city, _occupied, _world, events),
    do: {city, Enum.reverse(events)}

  # A Granary completion needs no landing tile and produces no
  # `spawn_event` — it just flips `has_granary: true` on the completing
  # city itself and moves on, same overflow-carry treatment as every
  # other completion (story 902).
  defp complete_loop(%{queue: [%{type: :granary} = current | rest]} = city, occupied, world, events)
       when current.banked >= current.cost do
    overflow = current.banked - current.cost

    city
    |> Map.put(:has_granary, true)
    |> Map.put(:queue, carry_overflow(rest, overflow))
    |> complete_loop(occupied, world, events)
  end

  defp complete_loop(%{queue: [current | rest]} = city, occupied, world, events) do
    if current.banked >= current.cost and spawnable?(city, current.type) do
      resolve_completion(city, current, rest, occupied, world, events)
    else
      {city, Enum.reverse(events)}
    end
  end

  defp resolve_completion(city, current, rest, occupied, world, events) do
    case landing_tile(city, occupied, world) do
      nil ->
        {city, Enum.reverse(events)}

      tile ->
        overflow = current.banked - current.cost
        event = %{player_id: city.player_id, type: current.type, tile_id: tile}

        city
        |> apply_pop_cost(current.type, world)
        |> Map.put(:queue, carry_overflow(rest, overflow))
        |> complete_loop(occupied, world, [event | events])
    end
  end

  # A settler costs its city one population, at the moment it spawns —
  # not while merely banked (story 883). A size-1 city can never pay
  # that cost, so its settler item simply waits, exactly like a
  # blocked landing tile.
  defp spawnable?(_city, type) when type in [:worker, :warrior, :bronze_spearman], do: true
  defp spawnable?(%{size: size}, :settler), do: size > 1

  defp landing_tile(city, occupied, world) do
    candidates = [
      city.tile_id
      | world |> Regions.adjacent_tiles(city.tile_id) |> Enum.filter(&land?(world, &1))
    ]

    Enum.find(candidates, &(not Map.has_key?(occupied, &1)))
  end

  defp land?(world, tile_id), do: Regions.tile_class(world, tile_id) == :land

  defp carry_overflow([], _overflow), do: []
  defp carry_overflow([next | rest], overflow), do: [%{next | banked: next.banked + overflow} | rest]

  defp apply_pop_cost(city, :settler, world) do
    city
    |> Map.update!(:size, &(&1 - 1))
    |> unwork_weakest_tile(world)
  end

  defp apply_pop_cost(city, _type, _world), do: city

  # Territory is permanent (story 883) — only which tile is WORKED
  # shrinks. Drop the lowest-scoring worked tile so the city keeps its
  # best producers.
  defp unwork_weakest_tile(%{worked_tiles: []} = city, _world), do: city

  defp unwork_weakest_tile(city, world) do
    weakest =
      Enum.min_by(city.worked_tiles, fn tile_id ->
        yield = Yields.tile_yield(Regions.terrain(world, tile_id))
        {Yields.assignment_score(yield), tile_id}
      end)

    %{city | worked_tiles: List.delete(city.worked_tiles, weakest)}
  end

  # -------------------------------------------------------------------
  # City founding
  # -------------------------------------------------------------------

  @doc """
  Validate founding a city on `tile_id`: must be passable land, and at
  least 4 hexes (over the land graph) from every existing city.
  """
  @spec validate_founding(World.t(), [city()], tile_id()) ::
          :ok | {:error, :invalid_terrain | :too_close}
  def validate_founding(world, cities, tile_id) do
    cond do
      not land?(world, tile_id) -> {:error, :invalid_terrain}
      too_close?(world, cities, tile_id) -> {:error, :too_close}
      true -> :ok
    end
  end

  @doc "A freshly founded city's territory: the tile plus its six neighbors, unconditionally."
  @spec founding_territory(World.t(), tile_id()) :: MapSet.t(tile_id())
  def founding_territory(world, tile_id),
    do: MapSet.new([tile_id | Regions.adjacent_tiles(world, tile_id)])

  defp too_close?(world, cities, tile_id) do
    max_depth = @min_founding_spacing - 1
    Enum.any?(cities, &(land_distance(world, tile_id, &1.tile_id, max_depth) <= max_depth))
  end

  # Land-only BFS distance, capped at `max_depth` (returns `max_depth + 1`
  # once exceeded or unreachable) — spacing only ever cares whether the
  # distance is under the minimum, so the search never needs to look
  # further than that.
  defp land_distance(_world, from, from, _max_depth), do: 0

  defp land_distance(world, from, to, max_depth),
    do: grow_land_ring(world, MapSet.new([from]), [from], to, 1, max_depth)

  defp grow_land_ring(_world, _seen, _frontier, _to, depth, max_depth) when depth > max_depth,
    do: max_depth + 1

  defp grow_land_ring(world, seen, frontier, to, depth, max_depth) do
    next =
      frontier
      |> Enum.flat_map(&Regions.adjacent_tiles(world, &1))
      |> Enum.uniq()
      |> Enum.filter(&land?(world, &1))
      |> Enum.reject(&MapSet.member?(seen, &1))

    cond do
      to in next -> depth
      next == [] -> max_depth + 1
      true -> grow_land_ring(world, MapSet.union(seen, MapSet.new(next)), next, to, depth + 1, max_depth)
    end
  end
end
