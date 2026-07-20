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
  `BrokenOaths.Game.Turn.entering_field_stack_with_room?/2`). It's
  enforced at the application layer (`occupied_by_own?/4` below at queue
  time, `BrokenOaths.Game.Turn`'s movement collision check at tick time)
  rather than a blanket DB unique index — see migration
  `20260716190000` for why a DB-level constraint can no longer express
  this rule.

  Per-type stats (starting hp/movement) live in
  `BrokenOaths.Cities.Production.unit_stats/1` alongside the rest of the
  buildable catalog, not here — this schema only shapes and validates
  whatever stats it's given.

  `charges` (story 882 playtest update, issue 1caa87e9 — Civ 6 Builder
  convention) defaults to 3 and is generic on the schema, but only a
  `:worker` ever spends it: `BrokenOaths.Game.Turn` decrements it by
  one for each COMPLETED Farm or Mine (never Road, which is
  charge-exempt) and removes the unit outright once its last charge is
  spent — the same removal path a combat death already uses
  (`BrokenOaths.Game.WorldServer.persist_unit_changes/2` diffs
  `state.units` and deletes whatever's missing). Every other unit type
  simply carries the default and never reads it.

  ## Queue move (pragdave decomposition, slice 4)

  `queue_move/4` is the pure, process-unaware "domain model" home for
  the unit-movement "queue_move" command logic
  `BrokenOaths.Game.WorldServer` used to bury inline as private `do_*`
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
  model calling its siblings" rule: `BrokenOaths.Game.Turn.move_now/2`
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
  alias BrokenOaths.Units.Order
  alias BrokenOaths.Players.Player
  alias BrokenOaths.Feudal.Rebellion.War
  alias BrokenOaths.Game.Turn
  alias BrokenOaths.Feudal.Vassalization
  alias BrokenOaths.Repo
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.World

  @type unit_type ::
          :lord | :settler | :warrior | :worker | :barbarian_warrior | :bronze_spearman | :archer
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
      values: [:lord, :settler, :warrior, :worker, :barbarian_warrior, :bronze_spearman, :archer]

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
  # `BrokenOaths.Game.WorldServer`'s own `do_queue_move/4` — see this
  # module's own "Queue move" moduledoc section above.
  # -------------------------------------------------------------------

  @doc """
  Queue (and immediately execute) a move order: `user`'s own `unit_id`
  paths toward `to_tile` over `:land` tiles, avoiding currently-occupied
  intermediate tiles (the destination itself may be occupied — see
  `bfs_path/3` below), persists the order, then resolves as much of it
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

      Regions.tile_class(state.world, to_tile) != :land ->
        {:error, :impassable}

      occupied_by_own?(state, to_tile, player.id, unit) ->
        {:error, :occupied}

      true ->
        case bfs_path(state, unit.tile_id, to_tile) do
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

  @doc """
  Shortest path over `:land` tiles, excluding `from`, including `to`.
  Plan around units that are on the board RIGHT NOW: occupied tiles are
  impassable as intermediate steps (an equally short free path must be
  preferred; a knowingly-blocked plan would interrupt on step one). The
  DESTINATION may be occupied — approaching another player's tile is
  legal; `BrokenOaths.Game.Turn`'s dynamic collision check is what stops
  the mover adjacent to it. Public (pragdave decomposition, slice 6) —
  the same "shared, real" reason `persist_order!/2` above is public: 
  `BrokenOaths.Feudal.Stewardship`'s own emergency-defense move calls this
  directly rather than WorldServer keeping a duplicate copy.
  """
  @spec bfs_path(map(), tile_id(), tile_id()) :: [tile_id()] | nil
  def bfs_path(state, from, to) do
    occupied =
      for {_id, u} <- state.units, u.tile_id != from, into: MapSet.new(), do: u.tile_id

    bfs_loop(state.world, occupied, :queue.from_list([{from, []}]), MapSet.new([from]), to)
  end

  defp bfs_loop(world, occupied, queue, visited, to) do
    case :queue.out(queue) do
      {:empty, _} ->
        nil

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

  # -------------------------------------------------------------------
  # Healing (moved from `BrokenOaths.Game.Turn`'s own private
  # `heal_units/1`, the tick-decomposition pass, see
  # `.code_my_spec/knowledge/genserver_decomposition.md`)
  # -------------------------------------------------------------------

  @doc """
  Heal every unit in `state.units` that spent no movement this tick.
  "Unmoved" is read straight off this tick's own movement ledger: a
  unit that spent zero movement points still holds `movement ==
  max_movement` after `BrokenOaths.Game.Turn.Movement.resolve_orders/1`
  ran, whether that's because it had no order or because its order was
  blocked before its first step. Heals 15 HP garrisoned on its own
  city's own tile, 10 HP anywhere else in its owner's territory, 0
  outside it. `state` is the canonical tick-state described in
  `BrokenOaths.Game.Turn`.
  """
  @spec heal_all(map()) :: map()
  def heal_all(state) do
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
