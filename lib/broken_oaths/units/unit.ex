defmodule BrokenOaths.Units.Unit do
  @moduledoc """
  A unit on the board — type (lord/settler/warrior/worker/barbarian
  warrior/bronze spearman, story 903), owner, tile id, hp, movement
  points.

  `player_id` is nullable: a barbarian warrior (`type: :barbarian_warrior`,
  spawned by `BrokenOaths.Combat.Camps`, story 892) has no owning player —
  the seam `BrokenOaths.Combat.Resolver.hostile?/2` recognizes — and instead
  carries `camp_id`, the camp that spawned it (used to cap "alive
  warriors per camp" at 2). An ordinary player-owned unit always sets
  `player_id` and leaves `camp_id` nil; the two are never both set.

  One unit per hex is a hard rule, with two exceptions: a city's own
  tile (story 895's garrison exception — see
  `BrokenOaths.Combat.CityDefense.garrison_room?/2`), and, out in the open
  field, exactly one non-combat unit stacking with exactly one combat
  unit of the SAME owner (v0.2.1 playtest issue 5df5de88 — a worker or
  settler may walk with a warrior/lord/bronze-spearman escort — see
  `field_stack_room?/2` below and
  `BrokenOaths.Simulation.Turn.entering_field_stack_with_room?/2`). It's
  enforced at the application layer (`occupied_by_own?/4` below at queue
  time, `BrokenOaths.Simulation.Turn`'s movement collision check at tick time)
  rather than a blanket DB unique index — see migration
  `20260716190000` for why a DB-level constraint can no longer express
  this rule.

  Per-type stats (starting hp/movement) live in
  `BrokenOaths.Cities.Production.unit_stats/1` alongside the rest of the
  buildable catalog, not here — this schema only shapes and validates
  whatever stats it's given.

  `fortified_turns` (story 920, reworked to ramp like Civ 6) counts how
  many turn boundaries the Fortify defensive stance has held: `0` not
  fortified; `1` the instant `fortify/3` below fires (any
  `:defend`-capable type, `BrokenOaths.Units.Actions.available/1`) — the
  PARTIAL bonus; `2` (capped there) once the unit survives a whole turn
  boundary untouched (`BrokenOaths.Simulation.Turn.Movement.
  advance_fortify/1`) — the FULL bonus
  (`BrokenOaths.Combat.Resolver.effective_strength/3` reads the count
  to pick the ratio). Holds until the unit itself moves
  (`BrokenOaths.Simulation.Turn.Movement.apply_positions/3`, which resets
  it to `0`) or attacks (`BrokenOaths.Combat.Resolver.resolve_attack/4`,
  `BrokenOaths.Combat.Camps.resolve_camp_attack/3`,
  `BrokenOaths.Combat.Siege`'s own `resolve_city_attack/4`, same reset)
  — being attacked never clears it. Generic on the schema like
  `charges`/`temporary` above; a barbarian or civilian-only type simply
  carries the `0` default and is never read for it.

  `charges` (story 882 playtest update, issue 1caa87e9 — Civ 6 Builder
  convention) defaults to 3 and is generic on the schema, but only a
  `:worker` ever spends it: `BrokenOaths.Simulation.Turn` decrements it by
  one for each COMPLETED Farm or Mine (never Road, which is
  charge-exempt) and removes the unit outright once its last charge is
  spent — the same removal path a combat death already uses
  (`BrokenOaths.Simulation.WorldServer.persist_unit_changes/2` diffs
  `state.units` and deletes whatever's missing). Every other unit type
  simply carries the default and never reads it.

  ## Queue move (pragdave decomposition, slice 4)

  `queue_move/4` is the pure, process-unaware "domain model" home for
  the unit-movement "queue_move" command logic
  `BrokenOaths.Simulation.WorldServer` used to bury inline as private `do_*`
  functions (see `.code_my_spec/knowledge/genserver_decomposition.md`).
  It takes the WorldServer's own tick-`state` plus plain args and
  returns either an ok-tuple carrying both the pre-move and post-move
  `state` (persist_tick's own before/after diff needs both) or
  `{:error, reason}` — no `GenServer`, no `handle_*`, no process
  awareness; `WorldServer`'s own `:queue_move` `handle_call` is a thin
  delegation into this function. Orders execute immediately with
  whatever movement the unit has left, the same "resolve now, don't
  wait for a turn boundary" shape `BrokenOaths.Combat.Resolver.attack/4`
  uses — coordinates its siblings directly, per the north star's
  "cross-cutting operations are orchestrated by their OWNING domain
  model calling its siblings" rule: `BrokenOaths.Simulation.Turn.move_now/2`
  resolves the immediate step, `BrokenOaths.Feudal.Vassalization.
  apply_captures/1` and `BrokenOaths.Feudal.Rebellion.War.
  process_rebellion_endings/2` are the same two post-move hooks
  (story 919's adjacent-march rebellion check) `WorldServer`'s own
  callback used to run inline.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Combat.Camp
  alias BrokenOaths.Combat.CityDefense
  alias BrokenOaths.Units.Actions
  alias BrokenOaths.Units.Order
  alias BrokenOaths.Players.Player
  alias BrokenOaths.Feudal.Rebellion.War
  alias BrokenOaths.Simulation.Turn
  alias BrokenOaths.Feudal.Vassalization
  alias BrokenOaths.Repo
  alias BrokenOaths.Technology.Research
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.Terrain
  alias BrokenOaths.Worlds.World

  @type unit_type ::
          :lord
          | :settler
          | :warrior
          | :worker
          | :barbarian_warrior
          | :bronze_spearman
          | :archer
          | :galley
  @type tile_id :: non_neg_integer()

  @type t :: %__MODULE__{
          id: integer() | nil,
          type: unit_type() | nil,
          tile_id: integer() | nil,
          hp: integer() | nil,
          max_hp: integer() | nil,
          movement: integer() | nil,
          max_movement: integer() | nil,
          charges: integer() | nil,
          world_id: integer() | nil,
          player_id: integer() | nil,
          camp_id: integer() | nil,
          temporary: boolean(),
          fortified_turns: non_neg_integer(),
          rebellion_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          player: Player.t() | Ecto.Association.NotLoaded.t() | nil,
          camp: Camp.t() | Ecto.Association.NotLoaded.t() | nil,
          rebellion: BrokenOaths.Feudal.Rebellion.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_units" do
    field :type, Ecto.Enum,
      values: [
        :lord,
        :settler,
        :warrior,
        :worker,
        :barbarian_warrior,
        :bronze_spearman,
        :archer,
        # Story 921 — the Galley, the first naval unit (see this
        # module's own `passable_tile?/2` for the water-domain
        # movement rule it introduces).
        :galley
      ]

    field :tile_id, :integer
    field :hp, :integer
    field :max_hp, :integer
    field :movement, :integer
    field :max_movement, :integer
    field :charges, :integer, default: 3

    # Story 915: flags a unit as part of a temporary rebellion army
    # (spawned by `BrokenOaths.Feudal.Rebellion.Resolution.army_size/1`
    # at declare-independence time) — see this schema's own moduledoc.
    field :temporary, :boolean, default: false

    # Story 920 — see this schema's own moduledoc "fortified_turns"
    # paragraph.
    field :fortified_turns, :integer, default: 0

    belongs_to :world, World
    belongs_to :player, Player
    belongs_to :camp, Camp
    belongs_to :rebellion, BrokenOaths.Feudal.Rebellion

    timestamps()
  end

  @doc false
  def changeset(unit, attrs) do
    unit
    |> cast(attrs, [
      :world_id,
      :player_id,
      :camp_id,
      :type,
      :tile_id,
      :hp,
      :max_hp,
      :movement,
      :max_movement,
      :charges,
      :temporary,
      :fortified_turns,
      :rebellion_id
    ])
    |> validate_required([
      :world_id,
      :type,
      :tile_id,
      :hp,
      :max_hp,
      :movement,
      :max_movement,
      :charges
    ])
    |> validate_number(:hp, greater_than: 0)
    |> validate_number(:max_hp, greater_than: 0)
    |> validate_number(:movement, greater_than_or_equal_to: 0)
    |> validate_number(:max_movement, greater_than_or_equal_to: 0)
    |> validate_number(:charges, greater_than_or_equal_to: 0)
    |> validate_number(:fortified_turns, greater_than_or_equal_to: 0)
    |> validate_hp_within_max()
    |> validate_movement_within_max()
    |> assoc_constraint(:world)
    |> assoc_constraint(:player)
    |> assoc_constraint(:camp)
    |> assoc_constraint(:rebellion)
  end

  defp validate_hp_within_max(changeset) do
    validate_field_within_max(changeset, :hp, :max_hp)
  end

  defp validate_movement_within_max(changeset) do
    validate_field_within_max(changeset, :movement, :max_movement)
  end

  defp validate_field_within_max(changeset, field, max_field) do
    value = get_field(changeset, field)
    max_value = get_field(changeset, max_field)

    if is_integer(value) and is_integer(max_value) and value > max_value do
      add_error(changeset, field, "must be less than or equal to #{max_field}")
    else
      changeset
    end
  end

  # -------------------------------------------------------------------
  # Queue move (stories 875/899/919) — moved home from
  # `BrokenOaths.Simulation.WorldServer`'s own `do_queue_move/4` — see this
  # module's own "Queue move" moduledoc section above.
  # -------------------------------------------------------------------

  @doc """
  Queue (and immediately execute) a move order: `user`'s own `unit_id`
  paths toward `to_tile` over whichever tiles its own TYPE may occupy
  (`passable_tile?/2` — `:land` for every unit before story 921, now
  `:coastal_water` for the Galley), avoiding currently-occupied
  intermediate tiles (the destination itself may be occupied — see
  `bfs_path/4` below), persists the order, then resolves as much of it
  as the unit's remaining movement allows this instant
  (`Turn.move_now/2`), applying any resulting capture/vassalization and
  rebellion-ending fallout.

  Returns `{:ok, result, state_before_move, state_after_move,
  capture_events}` on success — both states are handed back because
  `WorldServer`'s own `persist_tick/2` diffs the state right after the
  order was queued/persisted against the one after `Turn.move_now/2`
  ran, not the very original request state.
  """
  @spec queue_move(map(), map(), term(), tile_id()) ::
          {:ok, %{path: [tile_id()]}, map(), map(), [term()]} | {:error, atom()}
  def queue_move(state, user, unit_id, to_tile) do
    case do_queue_move(state, user, unit_id, to_tile) do
      {:ok, _path, queued} ->
        moved = Turn.move_now(queued, unit_id)
        {moved, capture_events} = Vassalization.apply_captures(moved)
        # Story 919: an adjacent march can knock a rebel out of the
        # fight (or hand the former lord back every risen city) without
        # ever needing a full turn boundary — see `War.
        # process_rebellion_endings/2`'s own doc for why this immediate
        # hook matters alongside its `Turn`-tick call site.
        moved = War.process_rebellion_endings(moved, :move)

        remaining =
          case Map.get(moved.orders, unit_id) do
            %{path: rest} -> rest
            nil -> []
          end

        {:ok, %{path: remaining}, queued, moved, capture_events}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_queue_move(state, user, unit_id, to_tile) do
    player = find_player(state, user.id)
    unit = Map.get(state.units, unit_id)

    cond do
      is_nil(player) or is_nil(unit) or unit.player_id != player.id ->
        {:error, :not_owner}

      not is_integer(to_tile) or to_tile < 0 or
          to_tile >= 10 * state.world.frequency * state.world.frequency + 2 ->
        {:error, :invalid_tile}

      not passable_tile?(unit.type, Regions.tile_class(state.world, to_tile)) ->
        {:error, :impassable}

      occupied_by_own?(state, to_tile, player.id, unit) ->
        {:error, :occupied}

      true ->
        case bfs_path(state, unit.tile_id, to_tile, unit.type) do
          [] ->
            {:error, :unreachable}

          nil ->
            {:error, :unreachable}

          path ->
            persist_order!(unit_id, path)

            new_state = %{
              state
              | orders:
                  Map.put(state.orders, unit_id, %{kind: :move, path: path, status: :pending})
            }

            {:ok, path, new_state}
        end
    end
  end

  # A player can never stack their own units, but a tile another player
  # currently holds is still a valid target — Turn's dynamic collision
  # check (not this queue-time check) is what halts the mover if the
  # tile is still occupied when they actually arrive. Story 895's
  # exception: `mover`'s own city's own tile allows up to
  # `CityDefense.garrison_cap/0` military units (civilians always fit,
  # uncounted) — see `CityDefense.garrison_room?/2`. Every OTHER own
  # tile keeps a tighter, but not all-or-nothing, rule (v0.2.1 playtest
  # issue 5df5de88): exactly one non-combat unit may stack with exactly
  # one combat unit out in the open field — `field_stack_room?/2` below
  # — so a worker/settler can walk with a warrior escort without a
  # city underfoot. `Turn.blocked?/6` mirrors this same allowance for
  # the dynamic, tick-time collision check.
  defp occupied_by_own?(state, tile_id, player_id, mover) do
    own_units_here =
      for {_id, u} <- state.units, u.tile_id == tile_id, u.player_id == player_id, do: u

    case Enum.find(state.cities, fn {_id, c} ->
           c.tile_id == tile_id and c.player_id == player_id
         end) do
      nil -> not field_stack_room?(mover, own_units_here)
      _own_city -> not CityDefense.garrison_room?(mover, own_units_here)
    end
  end

  # Room for `mover` on a non-city tile already holding `own_units_here`
  # (all same-owner, by construction — see `occupied_by_own?/4`'s own
  # `own_units_here` filter): empty is always room; a lone existing unit
  # leaves room only for the OTHER combat class (one civilian + one
  # combat, either order); two or more units already there is always
  # full. `CityDefense.military?/1` is the same combat/civilian split
  # story 895's own garrison rule uses (`:lord`/`:warrior`/
  # `:bronze_spearman` are combat; everything else is civilian).
  defp field_stack_room?(_mover, []), do: true

  defp field_stack_room?(mover, [only]),
    do: CityDefense.military?(only) != CityDefense.military?(mover)

  defp field_stack_room?(_mover, _units), do: false

  @doc """
  Upserts `unit_id`'s own `Order` row to the given `path` — public
  (pragdave decomposition, slice 6) so `BrokenOaths.Feudal.Stewardship`'s
  own emergency-defense move can persist an order the exact same way a
  normal `queue_move/4` does, without WorldServer keeping a second,
  duplicate copy of this write.
  """
  @spec persist_order!(term(), [tile_id()]) :: Order.t()
  def persist_order!(unit_id, path) do
    attrs = %{unit_id: unit_id, kind: :move, path: path, status: :pending}

    case Repo.get_by(Order, unit_id: unit_id) do
      nil -> %Order{} |> Order.changeset(attrs) |> Repo.insert!()
      existing -> existing |> Order.changeset(attrs) |> Repo.update!()
    end
  end

  # -------------------------------------------------------------------
  # Build road to (story 929) — issues a `:road_to` order on a worker:
  # walk the cheapest owned-territory route to `destination`, laying
  # road tile-by-tile as it arrives. Resolution (the walk-vs-build state
  # machine, one segment per tick) lives on `BrokenOaths.Simulation.Turn.
  # RoadBuilder` — genuinely cross-cutting (Units + Cities.Improvement),
  # no single owning domain model, same "gets its own Turn.* submodule"
  # status `Turn.Movement`/`Turn.BarbarianPhase`/`Turn.HeirSuccession`
  # already have. This function only ever VALIDATES and PERSISTS the
  # order — the same "queue-time command, tick-time resolution" split
  # `queue_move/4` above already draws for `:move` orders.
  # -------------------------------------------------------------------

  @doc """
  Queue a `:road_to` order: `user`'s own worker `unit_id` walks the
  cheapest route — `bfs_path/5`, restricted to tiles inside `user`'s
  OWN territory (every one of their own cities' `territory`, unioned;
  `player_territory_tiles/2` below) — to `destination`, laying road on
  every gap tile along the way (already-complete road tiles are simply
  walked through, never rebuilt) until `destination` itself is roaded.

  Refuses: an unowned/non-worker unit (`:not_owner`/`:not_worker`), a
  player who hasn't researched The Wheel (`:tech_locked` —
  `Research.road_enabled?/1`, the same gate `Improvement.
  validate_improvement_terrain/4`'s own `:road` clause already reads),
  an out-of-range/malformed tile id (`:invalid_tile`), a destination
  outside the player's own borders (`:not_territory`), or no
  owned-territory route at all (`:unreachable`, including the
  degenerate case of `destination` already being the worker's own
  tile — `bfs_path/5` returns `[]` for `from == to`, same as
  `queue_move/4`'s own handling below).

  `hp_at_issue` (the worker's own HP right now) is captured on the
  order the instant it's persisted — `Turn.RoadBuilder`'s own
  "attacked mid-build cancels" check reads it back every tick; see that
  module's moduledoc.

  Returns `{:ok, %{route: [tile_id()]}, new_state}` — unlike
  `queue_move/4`, there is no immediate partial resolution here: a
  `:road_to` order always waits for the next tick boundary to take its
  first step (`Turn.RoadBuilder.resolve/1`), rather than spending
  movement the instant it's issued — PM decision, story 929 (walking a
  road route is deliberately paced to the tick, not an "instant dash"
  the way a bare move order is).
  """
  @spec build_road_to(map(), map(), term(), tile_id()) ::
          {:ok, %{route: [tile_id()]}, map()} | {:error, atom()}
  def build_road_to(state, user, unit_id, destination) do
    player = find_player(state, user.id)
    unit = Map.get(state.units, unit_id)

    cond do
      is_nil(player) or is_nil(unit) or unit.player_id != player.id ->
        {:error, :not_owner}

      unit.type != :worker ->
        {:error, :not_worker}

      not Research.road_enabled?(player_research_for(state, player.id)) ->
        {:error, :tech_locked}

      not is_integer(destination) or destination < 0 or
          destination >= 10 * state.world.frequency * state.world.frequency + 2 ->
        {:error, :invalid_tile}

      true ->
        territory = player_territory_tiles(state, player.id)

        cond do
          not MapSet.member?(territory, destination) ->
            {:error, :not_territory}

          true ->
            case bfs_path(state, unit.tile_id, destination, unit.type, territory) do
              route when route in [[], nil] ->
                {:error, :unreachable}

              route ->
                persist_road_order!(unit_id, route, unit.hp)

                new_orders =
                  Map.put(state.orders, unit_id, %{
                    kind: :road_to,
                    path: route,
                    status: :pending,
                    hp_at_issue: unit.hp
                  })

                {:ok, %{route: route}, %{state | orders: new_orders}}
            end
        end
    end
  end

  # Every tile inside ANY of `player_id`'s own cities' `territory` —
  # the "owned borders" `build_road_to/4`'s own destination check AND
  # `bfs_path/5`'s own route restriction both read, so the two can
  # never quietly disagree on what counts as "in territory."
  defp player_territory_tiles(state, player_id) do
    for {_id, city} <- state.cities,
        city.player_id == player_id,
        tile_id <- city.territory,
        into: MapSet.new(),
        do: tile_id
  end

  defp persist_road_order!(unit_id, route, hp_at_issue) do
    attrs = %{
      unit_id: unit_id,
      kind: :road_to,
      path: route,
      status: :pending,
      hp_at_issue: hp_at_issue
    }

    case Repo.get_by(Order, unit_id: unit_id) do
      nil -> %Order{} |> Order.changeset(attrs) |> Repo.insert!()
      existing -> existing |> Order.changeset(attrs) |> Repo.update!()
    end
  end

  defp player_research_for(state, player_id),
    do: Map.get(state.player_research, player_id, Research.new())

  @doc """
  LEAST-TOTAL-COST path (story 925 — Dijkstra, upgraded from a plain
  BFS now that `entry_cost/3` prices tiles unevenly) over tiles
  `unit_type` may occupy (`passable_tile?/2`), excluding `from`,
  including `to`. Plan around units that are on the board RIGHT NOW:
  occupied tiles are impassable as intermediate steps (an equally cheap
  free path must be preferred; a knowingly-blocked plan would interrupt
  on step one). The DESTINATION may be occupied — approaching another
  player's tile is legal; `BrokenOaths.Simulation.Turn`'s dynamic
  collision check is what stops the mover adjacent to it. A unit now
  routes ALONG roads and open ground and around difficult terrain
  whenever a cheaper route exists, rather than beelining through a
  forest a road runs around. Ties (equal total cost via more than one
  route) resolve deterministically, lowest tile id first, via the
  `{cost, tile_id}` frontier key below — same "reproducible regardless
  of map order" contract the old BFS held. Public (pragdave
  decomposition, slice 6) — the same "shared, real" reason
  `persist_order!/2` above is public: `BrokenOaths.Feudal.Stewardship`'s
  own emergency-defense move calls this directly rather than
  WorldServer keeping a duplicate copy.

  `allowed_tiles` (story 929, default `nil` — unrestricted, every
  existing caller's behavior unchanged) optionally narrows every
  candidate tile (the destination included) to a `MapSet` — `build_road_to/4`
  above passes the issuing player's own territory (`player_territory_tiles/2`)
  so a road route never strays outside their own borders, "restricted
  to owned-territory tiles" per that story's own PM decision.
  """
  @spec bfs_path(map(), tile_id(), tile_id(), unit_type(), MapSet.t(tile_id()) | nil) ::
          [tile_id()] | nil
  def bfs_path(state, from, to, unit_type, allowed_tiles \\ nil) do
    occupied =
      for {_id, u} <- state.units, u.tile_id != from, into: MapSet.new(), do: u.tile_id

    roads = Map.get(state, :roads, %{})
    cleared_features = Map.get(state, :cleared_features, MapSet.new())

    dijkstra(
      state.world,
      roads,
      cleared_features,
      occupied,
      allowed_tiles,
      :gb_sets.singleton({0, from}),
      %{from => 0},
      %{},
      to,
      unit_type
    )
  end

  defp dijkstra(
         world,
         roads,
         cleared_features,
         occupied,
         allowed_tiles,
         frontier,
         dist,
         prev,
         to,
         unit_type
       ) do
    if :gb_sets.is_empty(frontier) do
      nil
    else
      {{cost, tile}, frontier} = :gb_sets.take_smallest(frontier)

      cond do
        tile == to ->
          reconstruct_path(prev, to, [])

        # A stale duplicate: a cheaper route to `tile` was already found
        # and popped (and expanded) earlier — nothing new to explore.
        cost > Map.get(dist, tile) ->
          dijkstra(
            world,
            roads,
            cleared_features,
            occupied,
            allowed_tiles,
            frontier,
            dist,
            prev,
            to,
            unit_type
          )

        true ->
          neighbors =
            world
            |> Regions.adjacent_tiles(tile)
            |> Enum.filter(
              &(passable_tile?(unit_type, Regions.tile_class(world, &1)) and
                  (&1 == to or not MapSet.member?(occupied, &1)) and
                  (is_nil(allowed_tiles) or MapSet.member?(allowed_tiles, &1)))
            )

          {frontier, dist, prev} =
            Enum.reduce(neighbors, {frontier, dist, prev}, fn n, {f, d, p} ->
              new_cost = cost + entry_cost(world, roads, n, cleared_features)

              if new_cost < Map.get(d, n, :infinity) do
                {:gb_sets.add({new_cost, n}, f), Map.put(d, n, new_cost), Map.put(p, n, tile)}
              else
                {f, d, p}
              end
            end)

          dijkstra(
            world,
            roads,
            cleared_features,
            occupied,
            allowed_tiles,
            frontier,
            dist,
            prev,
            to,
            unit_type
          )
      end
    end
  end

  defp reconstruct_path(prev, tile, acc) do
    case Map.fetch(prev, tile) do
      {:ok, parent} -> reconstruct_path(prev, parent, [tile | acc])
      :error -> acc
    end
  end

  @doc """
  Whether a unit of `unit_type` may occupy/traverse a tile classified
  `tile_class` (`Regions.tile_class/2`) — the single domain-aware seam
  story 921's Galley needed: `queue_move/4`'s own destination check and
  `bfs_path/4`'s pathfinding both read this SAME predicate, so the two
  can never quietly drift apart on which tiles a given unit type may
  step on. Every unit type before the Galley is `:land`-only, unchanged;
  `:galley` is `:coastal_water`-only (V1's locked scope — no deep-ocean
  sailing yet, no land unit ever boards a Galley).
  """
  @spec passable_tile?(unit_type(), Regions.tile_class()) :: boolean()
  def passable_tile?(:galley, tile_class), do: tile_class == :coastal_water
  def passable_tile?(_land_unit, tile_class), do: tile_class == :land

  @doc """
  Movement points to enter `tile_id` — story 925's single place cost is
  decided, read by both `bfs_path/4` below (pathfinding) and
  `BrokenOaths.Simulation.Turn.Movement.attempt_step/7` (the actual
  per-round step, `roads` threaded down from `state.roads`) so the two
  can never quietly disagree on what a tile costs. A COMPLETED Road
  (`status: :complete` — a `:building` road grants nothing yet) always
  costs 1 regardless of terrain, Civ 6's road-negates-difficult-terrain
  rule; anything else falls through to `Worlds.Terrain.movement_cost/1`
  (open terrain 1, DIFFICULT terrain — hills/woods/rainforest/marsh —
  2).
  """
  @spec entry_cost(World.t(), map(), tile_id()) :: 1 | 2
  def entry_cost(world, roads, tile_id), do: entry_cost(world, roads, tile_id, MapSet.new())

  @doc """
  `entry_cost/3`, with story 927's worker-cleared overlay applied
  (`cleared_features` — `state.cleared_features`, see `Regions.terrain/3`'s
  own doc): a chopped Woods/Rainforest tile prices like open terrain (1)
  the instant it's cleared, same as the movement-cost drop
  `Terrain.movement_cost/1` already gives a featureless tile.
  `BrokenOaths.Simulation.Turn.Movement.attempt_step/8` (the real tick-
  time step) and `bfs_path/4` above both call this arity; the arity-3
  sibling stays the "nothing cleared" default every existing caller
  (and test) keeps using unchanged.
  """
  @spec entry_cost(World.t(), map(), tile_id(), MapSet.t(tile_id())) :: 1 | 2
  def entry_cost(world, roads, tile_id, cleared_features) do
    if match?(%{status: :complete}, Map.get(roads, tile_id)) do
      1
    else
      world |> Regions.terrain(tile_id, cleared_features) |> Terrain.movement_cost()
    end
  end

  # -------------------------------------------------------------------
  # Fortify (story 920) — mirrors `Combat.Resolver.shoot/4`'s own shape
  # (QA issue 12bed1e4): the domain model home for the Fortify stance
  # command, `WorldServer`'s own `:fortify` `handle_call` is a thin
  # delegation into this function, same as `queue_move/4` above.
  # -------------------------------------------------------------------

  @doc """
  Fortify `unit_id`: grants `user`'s own unit the defensive stance
  (story 920) immediately — no dig-in turn, no movement spent — at its
  PARTIAL level (`fortified_turns` 1 of 2, see this module's own
  moduledoc "fortified_turns" paragraph); it ramps to the full bonus on
  its own at the next turn boundary if the unit holds
  (`Simulation.Turn.Movement.advance_fortify/1`). Legal for any
  `:defend`-capable type (`Units.Actions.available/1` — every
  player-commandable type except a barbarian) and idempotent —
  re-fortifying an already-fortified unit is a harmless no-op that
  never DOWNGRADES an already-ramped (2) unit back to partial (1), via
  `max(unit.fortified_turns, 1)` rather than a blind overwrite (a
  judgment call: the UI itself never offers the button once
  `fortified_turns > 0` — see `UnitPanel` — so this only guards a
  direct/test caller). The bonus itself lives in
  `Combat.Resolver.effective_strength/3`; this function only sets the
  counter that bonus reads. Holds until the unit next moves
  (`Simulation.Turn.Movement.apply_positions/3`) or attacks
  (`Combat.Resolver.resolve_attack/4`, `Combat.Camps.
  resolve_camp_attack/3`, `Combat.Siege`'s own `resolve_city_attack/4`)
  — being attacked while fortified never clears it.
  """
  @spec fortify(map(), map(), term()) :: {:ok, map()} | {:error, :not_owner | :not_fortifiable}
  def fortify(state, user, unit_id) do
    player = find_player(state, user.id)
    unit = Map.get(state.units, unit_id)

    cond do
      is_nil(player) or is_nil(unit) or unit.player_id != player.id ->
        {:error, :not_owner}

      :defend not in Actions.available(unit) ->
        {:error, :not_fortifiable}

      true ->
        fortified_turns = max(Map.get(unit, :fortified_turns, 0), 1)
        new_unit = Map.put(unit, :fortified_turns, fortified_turns)
        {:ok, %{state | units: Map.put(state.units, unit_id, new_unit)}}
    end
  end

  @doc """
  Whether `unit` currently holds ANY level of the Fortify stance (story
  920's ramp — see this module's own "fortified_turns" moduledoc
  paragraph): true for both the partial (`fortified_turns == 1`) and
  full (`fortified_turns >= 2`) bonus. `Map.get/3` defaults to `0` (not
  fortified) so a hand-built unit map that predates the field — a test
  fixture, an older cached assign — never raises.
  """
  @spec fortified?(map()) :: boolean()
  def fortified?(unit), do: Map.get(unit, :fortified_turns, 0) > 0

  # -------------------------------------------------------------------
  # Healing (moved from `BrokenOaths.Simulation.Turn`'s own private
  # `heal_units/1`, the tick-decomposition pass, see
  # `.code_my_spec/knowledge/genserver_decomposition.md`)
  # -------------------------------------------------------------------

  @doc """
  Heal every unit that DID NOT MOVE this tick — its `tile_id` is unchanged from
  `tiles_before`, the positions snapshot the tick takes before the movement
  phase. Deliberately tile-based, not `movement == max_movement`: story 924's
  split recharge only refills movement every N turns, so the movement proxy
  would starve a stationary-but-not-yet-recharged unit of healing. Heals 15 HP
  garrisoned on its own city's tile, 10 HP elsewhere in its owner's territory,
  and 5 HP anywhere else (open field, neutral, or enemy land); barbarians never
  heal here. `state` is the canonical tick-state described in
  `BrokenOaths.Simulation.Turn`.
  """
  @spec heal_all(map(), map()) :: map()
  def heal_all(state, tiles_before) do
    units =
      Map.new(state.units, fn {id, unit} -> {id, heal(id, unit, state.cities, tiles_before)} end)

    %{state | units: units}
  end

  defp heal(_id, %{hp: hp, max_hp: max_hp} = unit, _cities, _tiles_before) when hp >= max_hp,
    do: unit

  defp heal(id, unit, cities, tiles_before) do
    # "Didn't move this tick" = the unit's tile is unchanged from before the
    # movement phase (`tiles_before`, captured at the top of the tick). This is
    # deliberately NOT read off `movement == max_movement` anymore: story 924's
    # split recharge only refills movement every N turns, so that proxy would
    # deny healing to a unit that's sitting still but simply hasn't recharged.
    if unit.tile_id == Map.get(tiles_before, id) do
      %{unit | hp: min(unit.max_hp, unit.hp + heal_rate(unit, cities))}
    else
      unit
    end
  end

  # Barbarians have no cities and never heal from this player-territory logic —
  # keep them at 0 rather than letting the "anywhere else" rate buff them.
  defp heal_rate(%{type: :barbarian_warrior}, _cities), do: 0

  defp heal_rate(unit, cities) do
    owned = for {_id, city} <- cities, city.player_id == unit.player_id, do: city

    cond do
      Enum.any?(owned, &(&1.tile_id == unit.tile_id)) -> 15
      Enum.any?(owned, &(unit.tile_id in &1.territory)) -> 10
      # Some slow healing anywhere (open field, neutral, enemy land) so a unit
      # wounded out on campaign isn't stuck at low HP with no way home.
      true -> 5
    end
  end

  # -------------------------------------------------------------------
  # Shared, trivial lookups — duplicated rather than reaching back into
  # `WorldServer`, matching the sibling `BrokenOaths.Cities.City`/
  # `BrokenOaths.Combat.Resolver`'s own "pure, process-unaware,
  # unit-testable with no GenServer running" contract (small private
  # helper copies rather than expanding public APIs).
  # -------------------------------------------------------------------

  defp find_player(state, user_id) do
    state.players |> Map.values() |> Enum.find(&(&1.user_id == user_id))
  end
end
