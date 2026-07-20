defmodule BrokenOaths.Cities.Production do
  @moduledoc """
  Pure production core: the Stone Age buildable catalog (Settler 100,
  Worker 60, Warrior 40, Granary 60 — Monument is still out of scope,
  see story 879's own criteria) with per-type unit stats, per-turn
  production accrual, queue completion with overflow carry-over,
  completed-unit spawn placement, the settler population cost and
  size-1 guard, and city-founding validation (terrain, 4-hex spacing).
  No `Repo`: `complete/3` returns spawn intents as data (`spawn_event`)
  rather than inserting units itself — `BrokenOaths.Simulation.WorldServer`
  is the only place real unit ids get allocated.

  ## The flat production base

  Every city banks a flat 5 production per turn regardless of size or
  terrain (story 879), on top of its worked tiles' production —
  deliberately NOT the city center's own terrain-based production
  (that stays folded into the flat base; see
  `BrokenOaths.Cities.Yields`'s moduledoc). Food has no such override:
  the center's food floor accrues separately via
  `BrokenOaths.Cities.Yields.accrue_food/3`.

  ## Queue completion

  `complete/3` is a loop, not a single check: an overflow big enough to
  finish the next queued item too keeps cascading, and a fully blocked
  city (no free landing tile) simply stops with its current item's
  `banked` intact — nothing is lost, it just keeps growing next turn
  until a tile frees up (story 879, criterion 7472).

  ## Queue commands (pragdave decomposition, slice 3)

  `queue_production/4`, `reorder_production_item/4`, and
  `cancel_production_item/4` are the pure, process-unaware "domain
  model" home for the command logic `BrokenOaths.Simulation.WorldServer` used
  to bury inline as private `do_*` functions (see
  `.code_my_spec/knowledge/genserver_decomposition.md`). Each takes the
  WorldServer's own tick-`state` plus plain args and returns `{:ok,
  new_state} | {:error, reason}` — `WorldServer`'s own `handle_call`
  clauses are thin one-line delegations into this module.

  ## The Granary (story 902, criterion 7629)

  Unlike every other buildable, `:granary` is a BUILDING, not a unit:
  it needs no landing tile (`spawnable?/2`'s free-tile gate never
  applies to it) and its completion never produces a `spawn_event` —
  instead it flips `has_granary: true` directly on the completing city
  (read back by `BrokenOaths.Cities.Yields.accrue_food/3` for its +2
  food/turn bonus, the same "unlock flips a flag, read back on demand"
  pattern `BrokenOaths.Technology.Research` already documents for its own
  unlocks). Gated on the city's OWNER having completed Pottery
  (`can_queue?/3`'s `granary_available?` option) and on the city not
  already having one (`:already_built` — a Granary is built once,
  ever). `can_queue?/3` itself never touches `BrokenOaths.Technology.Research`
  directly — opts arrive pre-resolved. The resolution lives one level
  up, in `granary_available?/2`, called from `queue_production/4`
  (moved home from `WorldServer` in the pragdave decomposition, slice
  3 — previously the CALLER resolved the flag across a process
  boundary; now it's this module's own orchestration doing it, one
  function up from the pure gate it feeds).

  ## The Bronze Spearman's Copper gate (story 911)

  `:bronze_spearman` needs TWO independent opts to queue, not one:
  `opts[:bronze_age?]` (story 903 — the owner has completed Bronze
  Working) AND `opts[:copper_access?]` (story 911 — the CITY itself
  has a Copper tile somewhere in its own `territory` — a pure ACCESS
  GATE, no stockpile/consumption). Missing Bronze Working reports
  `{:error, :locked}` (unchanged from story 903 — the option never even
  appears in a Build UI until then, per `available_items/1` below);
  missing Copper with Bronze Working already done reports the more
  specific `{:error, :copper_required}`, so a caller can render
  "Requires Copper" rather than a generic locked message. As with
  `granary_available?/2` above, `can_queue?/3` stays opt-driven and
  dependency-free; `bronze_age?/2`/`copper_access?/2` do the actual
  `BrokenOaths.Technology.Research`/`BrokenOaths.Worlds.Resources` reads,
  called from `queue_production/4`.

  ## The Archer (QA issue da39e50b "No archer")

  The expanded tech tree's Archery tech (story 902) unlocked nothing —
  `:archer` is the first-pass fix, gated on a single opt,
  `opts[:archery?]` (the owner has completed Archery), the same single-
  opt shape `:granary`'s `granary_available?` already uses. Missing
  Archery reports `{:error, :locked}` and the option never appears in a
  Build UI until then (`available_items/1` below), same as
  `:bronze_spearman`'s own `bronze_age?` gate.

  Civ 6's own Archer is a RANGED unit (attacks from 2 tiles away
  without retaliation); this game's whole combat model
  (`BrokenOaths.Combat.Resolver`) is melee/adjacent-only — no unit anywhere
  in this codebase has a ranged attack. Implementing true ranged combat
  is a genuine design/engineering project (attack range, no-retaliation
  math, a new UI affordance for "attack from range"), well beyond a bug
  fix's scope. This first pass ships the Archer as a buildable MELEE
  unit instead — real, buildable, fights (adjacent, both sides land a
  blow) — with stats scaled to sit between the Warrior and the Bronze
  Spearman (`@unit_stats`/`BrokenOaths.Combat.Resolver`'s own
  `@base_strength`): strength 14 (Warrior 10, Bronze Spearman 16), 100
  HP (Warrior's own HP), cost 40 production (cheaper than the Bronze
  Spearman's 60 — Archery is a tier-2 tech but doesn't need a strategic
  resource the way Bronze Spearman needs Copper). **True ranged attack
  (strike without retaliation, from 2 tiles away) is flagged here as a
  follow-up design item for the product owner** — this comment is that
  flag; see the QA issue's resolution for the full writeup.
  """

  import Ecto.Query

  alias BrokenOaths.Combat.CityDefense
  alias BrokenOaths.Cities.ProductionItem
  alias BrokenOaths.Technology.Research
  alias BrokenOaths.Cities.Yields
  alias BrokenOaths.Repo
  alias BrokenOaths.Worlds.Globe
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.Resources
  alias BrokenOaths.Worlds.World

  @type tile_id :: non_neg_integer()
  @type unit_buildable :: :settler | :worker | :warrior | :bronze_spearman | :archer
  @type buildable :: unit_buildable() | :granary
  @type unit_type ::
          :lord | :settler | :warrior | :worker | :barbarian_warrior | :bronze_spearman | :archer

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
  @type can_queue_error :: :size_one | :locked | :already_built | :copper_required

  @flat_production 5
  @min_founding_spacing 4

  @catalog %{settler: 100, worker: 60, warrior: 40, granary: 60, bronze_spearman: 60, archer: 40}

  @unit_stats %{
    lord: %{hp: 150, movement: 2},
    settler: %{hp: 50, movement: 2},
    warrior: %{hp: 100, movement: 1},
    worker: %{hp: 10, movement: 2},
    barbarian_warrior: %{hp: 120, movement: 1},
    # Story 903 — `.code_my_spec/knowledge/civ6_tech_tree.md` §5.
    bronze_spearman: %{hp: 120, movement: 1},
    # QA issue da39e50b — see this module's own moduledoc, "The Archer",
    # for the melee-for-now stats rationale and the ranged-attack flag.
    archer: %{hp: 100, movement: 1}
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
  shorthand for `can_queue?/3` with no options — `granary_available?`/
  `copper_access?` simply default to `false`, so a Granary or a Bronze
  Spearman is refused unless the caller explicitly opts them in).
  """
  @spec can_queue?(city(), buildable()) :: :ok | {:error, can_queue_error()}
  def can_queue?(city, type), do: can_queue?(city, type, [])

  @doc """
  Whether `type` can be queued right now: the size-1 settler rule (a
  size-1 city has no population to spare; story 883, criterion 7487),
  and — for `:granary` only (story 902) — the city's owner having
  completed Pottery (`opts[:granary_available?]`, since this
  dependency-free function never calls `BrokenOaths.Technology.Research`
  itself) and not already having one (`:already_built`). Story 903/911:
  `:bronze_spearman` needs BOTH `opts[:bronze_age?]` (Bronze Working
  completed) and `opts[:copper_access?]` (a Copper tile somewhere in
  the city's own territory) — see this module's own moduledoc, "The
  Bronze Spearman's Copper gate."
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
    cond do
      not Keyword.get(opts, :bronze_age?, false) -> {:error, :locked}
      not Keyword.get(opts, :copper_access?, false) -> {:error, :copper_required}
      true -> :ok
    end
  end

  # QA issue da39e50b — see this module's own moduledoc, "The Archer".
  def can_queue?(_city, :archer, opts) do
    if Keyword.get(opts, :archery?, false), do: :ok, else: {:error, :locked}
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
  reason (a size-1 city's Settler, an already-built city's Granary, or
  — story 911 — a Bronze Age city with no Copper access) — those
  refusals are `disabled` states in the UI, not list exclusions.
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
    |> maybe_offer(:archer, Keyword.get(opts, :archery?, false))
  end

  defp maybe_offer(types, type, true), do: types ++ [type]
  defp maybe_offer(types, _type, false), do: types

  # -------------------------------------------------------------------
  # Queue commands (moved from WorldServer, story 879)
  # -------------------------------------------------------------------

  @doc """
  Queue a new `type` item at the tail of `city_id`'s own build queue —
  resolves the Granary/Bronze Spearman/Archer gates itself
  (`granary_available?/2`/`bronze_age?/2`/`copper_access?/2`/
  `archery?/2`) before handing them to the pure `can_queue?/3`.
  """
  @spec queue_production(map(), map(), integer(), atom() | String.t()) ::
          {:ok, map()} | {:error, atom()}
  def queue_production(state, user, city_id, type) do
    with {:ok, city} <- owned_city(state, user, city_id),
         {:ok, type} <- parse_item_type(type),
         :ok <-
           can_queue?(city, type,
             granary_available?: granary_available?(state, city),
             bronze_age?: bronze_age?(state, city),
             copper_access?: copper_access?(state, city),
             archery?: archery?(state, city)
           ) do
      next_position =
        city.queue |> Enum.map(&Map.get(&1, :position, 0)) |> Enum.max(fn -> 0 end) |> Kernel.+(1)

      {:ok, item} =
        %ProductionItem{}
        |> ProductionItem.changeset(
          new_item(type)
          |> Map.put(:city_id, city_id)
          |> Map.put(:position, next_position)
        )
        |> Repo.insert()

      new_city = %{city | queue: city.queue ++ [queue_item_map(item)]}
      {:ok, %{state | cities: Map.put(state.cities, city_id, new_city)}}
    end
  end

  # Move a queued item one slot toward the head by swapping positions
  # with its predecessor. The head (current) item can't move; item
  # identity — and its banked progress — stays put, only order changes.
  @doc "Move `item_id` one slot toward the head of `city_id`'s own build queue."
  @spec reorder_production_item(map(), map(), integer(), integer()) ::
          {:ok, map()} | {:error, atom()}
  def reorder_production_item(state, user, city_id, item_id) do
    with {:ok, city} <- owned_city(state, user, city_id) do
      case Enum.find_index(city.queue, &(&1.id == item_id)) do
        nil ->
          {:error, :not_found}

        0 ->
          {:error, :invalid_item}

        idx ->
          above = Enum.at(city.queue, idx - 1)
          item = Enum.at(city.queue, idx)

          Repo.update_all(from(p in ProductionItem, where: p.id == ^item.id),
            set: [position: above.position]
          )

          Repo.update_all(from(p in ProductionItem, where: p.id == ^above.id),
            set: [position: item.position]
          )

          swapped = %{item | position: above.position}
          swapped_above = %{above | position: item.position}

          new_queue =
            city.queue
            |> List.replace_at(idx - 1, swapped)
            |> List.replace_at(idx, swapped_above)

          new_city = %{city | queue: new_queue}
          {:ok, %{state | cities: Map.put(state.cities, city_id, new_city)}}
      end
    end
  end

  @doc "Cancel (delete) `item_id` from `city_id`'s own build queue."
  @spec cancel_production_item(map(), map(), integer(), integer()) ::
          {:ok, map()} | {:error, atom()}
  def cancel_production_item(state, user, city_id, item_id) do
    with {:ok, city} <- owned_city(state, user, city_id) do
      if Enum.any?(city.queue, &(&1.id == item_id)) do
        Repo.delete_all(from(p in ProductionItem, where: p.id == ^item_id))
        new_city = %{city | queue: Enum.reject(city.queue, &(&1.id == item_id))}
        {:ok, %{state | cities: Map.put(state.cities, city_id, new_city)}}
      else
        {:error, :not_found}
      end
    end
  end

  @doc "Parses a build-type param (atom or string) into a known `buildable()`."
  @spec parse_item_type(term()) :: {:ok, buildable()} | {:error, :invalid_item}
  def parse_item_type(type)
      when type in [:settler, :worker, :warrior, :granary, :bronze_spearman, :archer],
      do: {:ok, type}

  def parse_item_type("settler"), do: {:ok, :settler}
  def parse_item_type("worker"), do: {:ok, :worker}
  def parse_item_type("warrior"), do: {:ok, :warrior}
  def parse_item_type("granary"), do: {:ok, :granary}
  def parse_item_type("bronze_spearman"), do: {:ok, :bronze_spearman}
  # QA issue da39e50b — the Archery tech unlocked nothing; a first-pass
  # Archer (melee-for-now — see this module's own moduledoc) buildable
  # once the city's owner has completed Archery.
  def parse_item_type("archer"), do: {:ok, :archer}
  def parse_item_type(_other), do: {:error, :invalid_item}

  # Story 902, criterion 7629 — whether `city`'s OWNER has completed
  # Pottery, the option `can_queue?/3` needs to gate `:granary` on.
  @doc "Whether `city`'s OWNER has completed Pottery — the `:granary_available?` opt `can_queue?/3` needs."
  @spec granary_available?(map(), city()) :: boolean()
  def granary_available?(state, city),
    do: Research.granary_enabled?(player_research_for(state, city.player_id))

  # Story 903 — whether `city`'s OWNER is in the Bronze Age
  # (`Research.age/1`), the option `can_queue?/3` needs to gate
  # `:bronze_spearman` on.
  @doc "Whether `city`'s OWNER is in the Bronze Age — the `:bronze_age?` opt `can_queue?/3` needs."
  @spec bronze_age?(map(), city()) :: boolean()
  def bronze_age?(state, city),
    do: Research.age(player_research_for(state, city.player_id)) == :bronze_age

  # QA issue da39e50b — whether `city`'s OWNER has completed Archery,
  # the option `can_queue?/3` needs to gate `:archer` on.
  @doc "Whether `city`'s OWNER has completed Archery — the `:archery?` opt `can_queue?/3` needs."
  @spec archery?(map(), city()) :: boolean()
  def archery?(state, city),
    do: Research.archery_enabled?(player_research_for(state, city.player_id))

  # Story 911 — whether `city` itself has Copper access: a Copper tile
  # anywhere in its own `territory` (worked or not — a pure ACCESS
  # GATE), the option `can_queue?/3` needs to gate `:bronze_spearman`
  # on ALONGSIDE `bronze_age?/2` above. Unlike `granary_available?/2`/
  # `bronze_age?/2` (both resolve `Research` over the city's OWNER),
  # this reads `Resources.at/2` over the CITY's own territory — Copper
  # access is a per-city fact, not a per-player one (two cities
  # belonging to the same player can differ: one may sit on Copper
  # hills, the other may not).
  @doc "Whether `city` has a Copper tile in its own territory — the `:copper_access?` opt `can_queue?/3` needs."
  @spec copper_access?(map(), city()) :: boolean()
  def copper_access?(state, city),
    do: Enum.any?(city.territory, &(Resources.at(state.world, &1) == :copper))

  @doc """
  Test-only helper for `WorldServer`'s own `:grant_copper_access_for_test`
  bridge: the first tile id (mesh order) anywhere on `world` carrying
  Copper, or `nil` if this particular seed/density placed none at all.
  """
  @spec find_any_copper_tile(World.t()) :: tile_id() | nil
  def find_any_copper_tile(world) do
    mesh = Globe.get(world.frequency)

    Enum.find_value(mesh.tiles, fn {tile_id, _tile} ->
      if Resources.at(world, tile_id) == :copper, do: tile_id
    end)
  end

  # -------------------------------------------------------------------
  # Shared, trivial lookups — duplicated rather than reaching back into
  # `WorldServer` (or reaching sideways into `City`), matching the
  # sibling `Rebellion.War`'s own "pure, process-unaware, unit-testable
  # with no GenServer running" contract (small private helper copies
  # rather than expanding public APIs).
  # -------------------------------------------------------------------

  defp find_player(state, user_id) do
    state.players |> Map.values() |> Enum.find(&(&1.user_id == user_id))
  end

  defp owned_city(state, user, city_id) do
    player = find_player(state, user.id)
    city = Map.get(state.cities, city_id)

    if is_nil(player) or is_nil(city) or city.player_id != player.id do
      {:error, :not_owner}
    else
      {:ok, city}
    end
  end

  defp player_research_for(state, player_id),
    do: Map.get(state.player_research, player_id, Research.new())

  defp queue_item_map(%ProductionItem{} = item),
    do: %{
      id: item.id,
      type: item.type,
      banked: item.banked,
      cost: item.cost,
      position: item.position
    }

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
  # Tick-loop accrual (moved from `BrokenOaths.Simulation.Turn`'s own private
  # `accrue_production/1`/`accrue_or_skip/2`, the tick-decomposition
  # pass — see `.code_my_spec/knowledge/genserver_decomposition.md`)
  # -------------------------------------------------------------------

  @doc """
  Bank this turn's production for every city in `state.cities`, skipping
  any city still serving `BrokenOaths.Combat.CityDefense.production_halted?/2`'s
  pillage freeze (story 895) -- that city's queue simply doesn't move
  this boundary; its banked progress is untouched, not lost. `state` is
  the canonical tick-state described in `BrokenOaths.Simulation.Turn`.
  """
  @spec accrue_cities(map()) :: map()
  def accrue_cities(state) do
    cities =
      Map.new(state.cities, fn {id, city} ->
        {id, accrue_or_skip(city, state)}
      end)

    %{state | cities: cities}
  end

  # A pillaged city's queue simply doesn't move while
  # `CityDefense.production_halted?/2` holds -- see that function's doc
  # for exactly which boundaries that covers.
  defp accrue_or_skip(city, state) do
    if CityDefense.production_halted?(city, state.turn) do
      city
    else
      accrue(city, state.world, state.improvements)
    end
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
  defp complete_loop(
         %{queue: [%{type: :granary} = current | rest]} = city,
         occupied,
         world,
         events
       )
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
  defp spawnable?(_city, type) when type in [:worker, :warrior, :bronze_spearman, :archer],
    do: true

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

  defp carry_overflow([next | rest], overflow),
    do: [%{next | banked: next.banked + overflow} | rest]

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
  # Tick-loop completion resolution (moved from `BrokenOaths.Simulation.Turn`'s
  # own private `resolve_completions/1`/`resolve_city_completion/2`, the
  # tick-decomposition pass)
  # -------------------------------------------------------------------

  @doc """
  Resolve every city's queue completions for one tick, in ascending
  city id order, threading a running "occupied tiles" set through so a
  spawn from one city in this same tick correctly blocks a landing tile
  for the next city's completion -- before either lands in `state.units`,
  which only the caller can update (`{:unit_spawned, _}` events are
  placement intents, not real units -- this module never allocates a
  real unit id itself). Also threads a `MapSet` of city ids whose queue
  completed a `:settler` THIS tick (`apply_pop_cost/3` already docked
  their population the instant the spawn event was built) --
  `BrokenOaths.Cities.Yields.grow_cities/2` reads this to skip those
  cities' own growth this same tick (issue 63300098: growth resolving
  in the same tick otherwise silently refunds the settler's population
  cost the instant a well-fed city crosses its next growth threshold).
  `state` is the canonical tick-state described in
  `BrokenOaths.Simulation.Turn`.

  Returns `{new_state, spawn_events, occupied, settled_this_tick}`.
  """
  @spec resolve_completions(map()) :: {map(), [spawn_event()], map(), MapSet.t()}
  def resolve_completions(state) do
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
    {new_city, city_events} = complete(city, occupied, world)
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
      to in next ->
        depth

      next == [] ->
        max_depth + 1

      true ->
        grow_land_ring(
          world,
          MapSet.union(seen, MapSet.new(next)),
          next,
          to,
          depth + 1,
          max_depth
        )
    end
  end
end
