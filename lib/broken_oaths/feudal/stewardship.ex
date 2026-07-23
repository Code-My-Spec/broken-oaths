defmodule BrokenOaths.Feudal.Stewardship do
  @moduledoc """
  Feudal + alliance stewardship core (story 910): pure business rules
  on top of `BrokenOaths.Feudal.Vassalage` (907) and `BrokenOaths.Game.
  Alliance` (899/901) — mirrors `BrokenOaths.Diplomacy.Cooperation`/
  `BrokenOaths.Feudal.Vassalization`'s own "pure changeset/decision
  logic, no `Repo`" role, plus (pragdave decomposition, slice 6 —
  `.code_my_spec/knowledge/genserver_decomposition.md`) the state-taking
  orchestration `BrokenOaths.Simulation.WorldServer` used to bury inline as
  private `do_*`/`resolve_*` functions. Each state-taking function below
  takes the WorldServer's own tick-`state` (or the relevant
  substructure) plus plain args and returns either a plain value or an
  updated `state` — no `GenServer`, no `handle_*`, no process
  awareness. `WorldServer`'s own `handle_call` clauses for `:steward_*`,
  `:alliances`, and `:steward_log` are thin delegations into this
  module; it resolves the DB-backed relationship facts (who's whose
  lord, who's allied with whom, who's currently online —
  `BrokenOaths.Players.Presence`) into the plain values this module's own
  pure functions take, applies the resulting decision, and persists the
  outcome (a `state.players`/`state.cities` diff via the caller's usual
  `persist_tick/2` path for a bank sweep/emergency move, an immediate
  `BrokenOaths.Feudal.StewardLog` insert for the audit trail).

  ## Who may steward whom

  `steward_role/4` resolves the ONE relationship that matters for a
  given (steward, owner) pair into `:lord | :fellow_vassal | :ally |
  :none` — the household lattice the design doc calls for
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Feudal
  Stewardship (910)"): the owner's own LORD, a FELLOW VASSAL sworn to
  that same lord, or an ALLY (`Alliance`, `:accepted`) may all act;
  nobody else. `eligible?/1` is the single yes/no gate every steward
  command checks first. The one asymmetry this story keeps: a vassal
  never stewards their own lord — `steward_role/4` only ever resolves
  `:lord` in the direction "owner is a vassal, steward is their lord,"
  never the reverse, so there is no clause anywhere that could match a
  vassal acting on their own lord's behalf. Alliance stewardship is the
  mirror opposite: `:ally` resolves identically regardless of which
  side is asking — `steward_role/4`'s own `allied?` argument is already
  symmetric (an accepted `Alliance` has no "up"/"down"), so either
  party stewards the other exactly the same way. `fetch_context/3` is
  the state-taking wrapper: it resolves the owner's own lord, the
  steward's own lord, and whether an ACCEPTED alliance exists between
  the two, each read fresh off `Repo` (world-membership-scoped
  coordination state, same non-tick-state status `list_alliances/2`
  already has for `Alliance`), then checks `Game.feudal_enabled?/0`,
  `eligible?/1`, and that the owner is genuinely offline
  (`Presence.online?/2`) before handing back `{:ok, steward_player,
  owner_player}` — every real steward mutation below shares this one
  gate.

  ## What a steward may do

  Three actions, each constructive-only or defensive-only by
  construction — never a blank check:

    * **Bank sweep** — `BrokenOaths.Feudal.Bank.steward_collect/1` (not
      this module's own job; stewardship only decides WHO may call it
      and WHEN, `Bank` decides what collecting actually moves).
      `collect_bank/3` is the state-taking command behind
      `WorldServer`'s own `:steward_collect_bank`.
    * **Production stewardship** — `constructive_item?/1` is the safe
      whitelist gate: every unit/building this codebase can build today
      is economic or defensive by nature (no aggression-only item
      exists yet), so the whitelist is really "a legitimate build order
      at all" — cancelling an in-progress item or disbanding a unit are
      not whitelist violations to REFUSE via this gate, they are
      different COMMANDS this module never defines a path for at all
      (no `cancel`/`disband` function exists here — "no disbanding, no
      cancel-griefing" is enforced structurally, by absence, not by a
      runtime check). Playtest issue 340c1ad4 adds a SECOND gate ahead
      of the whitelist: the owner's own EMPIRE-WIDE `Player.
      allow_steward_production` grant (opt-in, default `false`) —
      `queue_production/5` refuses with `:steward_production_disabled`
      before it ever looks at `city_id` unless that ONE flag is set,
      covering every city the owner has, not a per-city switch.
      `queue_production/5` is the state-taking command behind
      `WorldServer`'s own `:steward_queue_production` — it mirrors
      `BrokenOaths.Cities.Production.queue_production/4` exactly (same
      catalog, same `can_queue?/3` gate) but scoped through stewardship
      eligibility instead of ownership.
    * **Emergency defense** — `under_attack?/1` is the gate: normally a
      steward cannot touch the offline owner's units at all; only while
      at least one of the owner's own units carries live damage (`hp <
      max_hp` — the most literal, observable "under attack" signal
      available; see story 910's own spec fixtures) does the window
      open, and even then only for a genuinely DEFENSIVE reposition —
      `defend_target_allowed?/3` refuses anything beyond one hex from
      the unit's own current tile, so the emergency window can never be
      used to march the army off or launch it at a target (aggression
      has no path through this module at all, same "enforced by
      absence" discipline production cancel/disband has above).
      `defend/5` is the state-taking command behind `WorldServer`'s own
      `:steward_defend` — on the genuinely-defensive path it calls
      `BrokenOaths.Units.Unit.bfs_path/4` +
      `BrokenOaths.Units.Unit.persist_order!/2` +
      `BrokenOaths.Simulation.Turn.move_now/2`, the exact same "orders
      execute immediately" sequence `Unit.queue_move/4` already
      establishes for an ordinary move.

  ## Anti-sabotage

  `log_attrs/7` is the one shared shape every steward action's own
  `StewardLog` insert builds from — every action, successful or
  refused-as-overreach, gets a row so the owner can review the full
  history on return (criterion 7695); `log_action!/6` is the state-taking
  write itself. `steward_log/2` (+ `format_steward_log/2`) is the
  owner's own read of that same trail. `apply_sabotage_penalty/1` is the
  Honor consequence: a steward who abuses the emergency window (an
  `under_attack?/1`-gated attempt that still fails `defend_target_allowed?/3`)
  is provable sabotage the moment it's attempted, whether or not the
  underlying move itself is also blocked — `sabotage_honor_penalty/0`
  is the fixed, small, tunable ding (mirrors `Tribute.
  oath_strain_refusal_spike/0`'s own "a fixed, documented, callable
  constant" status).

  ## Click-through steward view (QA issue bd93cc0a)

  `steward_view/2` is the payload carried on every OFFLINE household
  member's own `format_vassal/2` (`WorldServer`)/`format_alliance/3`
  row — everything `GameLive.Play`'s own production-stewardship +
  emergency-defend controls need to render REAL options, not a blank
  check. `list_alliances/2` (moved home in slice 5, extended here since
  `format_alliance/3` is the other carrier of this same payload) is the
  `Alliance` counterpart to `WorldServer`'s own `vassals/2`: only an
  ACCEPTED, offline ally is stewardable at all — a merely `:proposed`
  row, or an online ally, carries no `steward_view/2` payload.
  """

  import Ecto.Query

  alias BrokenOaths.Game
  alias BrokenOaths.Diplomacy.Alliance
  alias BrokenOaths.Feudal.Bank
  alias BrokenOaths.Diplomacy.Cooperation
  alias BrokenOaths.Players.Presence
  alias BrokenOaths.Cities.Production
  alias BrokenOaths.Cities.ProductionItem
  alias BrokenOaths.Feudal.StewardLog
  alias BrokenOaths.Simulation.Turn
  alias BrokenOaths.Units.Unit
  alias BrokenOaths.Feudal.Vassalage
  alias BrokenOaths.Repo
  alias BrokenOaths.Users
  alias BrokenOaths.Users.User
  alias BrokenOaths.Worlds.Regions

  @type player_id :: term()
  @type role :: :lord | :fellow_vassal | :ally | :none
  @type unit :: %{hp: integer(), max_hp: integer()}

  @constructive_items [:settler, :worker, :warrior, :granary, :bronze_spearman]
  @sabotage_honor_penalty 2

  # -------------------------------------------------------------------
  # Who may steward whom
  # -------------------------------------------------------------------

  @doc """
  Resolves the (steward, owner) relationship into a `role/0` —
  `owner_lord_id` is the lord of `owner`'s own active `Vassalage` (as
  vassal), or `nil` if `owner` isn't presently anyone's vassal;
  `steward_lord_id` is the same fact for `steward_player_id`;
  `allied?` is whether an ACCEPTED `Alliance` exists between the two
  (already symmetric — the caller resolves it once, not per-direction).
  """
  @spec steward_role(player_id() | nil, player_id(), player_id() | nil, boolean()) :: role()
  def steward_role(owner_lord_id, steward_player_id, _steward_lord_id, _allied?)
      when not is_nil(owner_lord_id) and owner_lord_id == steward_player_id,
      do: :lord

  def steward_role(owner_lord_id, _steward_player_id, steward_lord_id, _allied?)
      when not is_nil(owner_lord_id) and not is_nil(steward_lord_id) and
             owner_lord_id == steward_lord_id,
      do: :fellow_vassal

  def steward_role(_owner_lord_id, _steward_player_id, _steward_lord_id, true), do: :ally
  def steward_role(_owner_lord_id, _steward_player_id, _steward_lord_id, _allied?), do: :none

  @doc "Whether `role` may steward at all — every role except `:none`."
  @spec eligible?(role()) :: boolean()
  def eligible?(:none), do: false
  def eligible?(_role), do: true

  @doc """
  Every real steward mutation shares this same eligibility gate:
  `steward_user`/`owner_user_id` both real players, `eligible?/1` over
  the resolved `steward_role/4`, and the owner genuinely offline
  (`Presence.online?/2`) — `{:ok, steward_player, owner_player}` once
  every check clears.
  """
  @spec fetch_context(map(), term(), term()) ::
          {:ok, map(), map()} | {:error, atom()}
  def fetch_context(state, steward_user, owner_user_id) do
    with {:ok, steward_player} <- fetch_player(state, steward_user.id),
         {:ok, owner_player} <- fetch_player(state, owner_user_id) do
      role = resolve_role(state, steward_player.id, owner_player.id)
      owner_online? = Presence.online?(state.world, %{id: owner_player.user_id})

      cond do
        not Game.feudal_enabled?() -> {:error, :feudal_disabled}
        not eligible?(role) -> {:error, :not_eligible}
        owner_online? -> {:error, :owner_online}
        true -> {:ok, steward_player, owner_player}
      end

      # NOTE: kept as its own literal `Game.feudal_enabled?()` check
      # (rather than a shared `ensure_feudal_enabled/0` helper) since
      # this branch sits inside a `cond`, not a `with`, and needs to
      # run AFTER both players are already resolved (`:not_a_player`
      # must still win over `:feudal_disabled` for an invalid user_id).
    end
  end

  defp resolve_role(state, steward_player_id, owner_player_id) do
    owner_lord_id = state |> active_vassalage_for_vassal(owner_player_id) |> lord_id_of()
    steward_lord_id = state |> active_vassalage_for_vassal(steward_player_id) |> lord_id_of()
    allied? = accepted_ally?(state.world.id, steward_player_id, owner_player_id)

    steward_role(owner_lord_id, steward_player_id, steward_lord_id, allied?)
  end

  defp lord_id_of(nil), do: nil
  defp lord_id_of(%Vassalage{lord_player_id: lord_player_id}), do: lord_player_id

  defp accepted_ally?(world_id, player_a_id, player_b_id) do
    case Cooperation.find_alliance(world_id, player_a_id, player_b_id) do
      %Alliance{status: :accepted} -> true
      _other -> false
    end
  end

  defp active_vassalage_for_vassal(state, vassal_player_id) do
    Repo.get_by(Vassalage,
      world_id: state.world.id,
      vassal_player_id: vassal_player_id,
      status: :active
    )
  end

  # -------------------------------------------------------------------
  # Production stewardship
  # -------------------------------------------------------------------

  @doc "Whether `type` is on the constructive-only production whitelist a steward may queue."
  @spec constructive_item?(atom()) :: boolean()
  def constructive_item?(type), do: type in @constructive_items

  @doc """
  Playtest issue 340c1ad4 — `user`'s own EMPIRE-WIDE grant: whether
  ANY eligible steward may set their production while they're offline.
  Owner-only (`user` may only ever set THEIR OWN flag — there is no
  `owner_user_id` param here at all, unlike every real steward
  mutation above), and never scoped by `city_id`: `queue_production/5`'s
  own `ensure_production_allowed/1` gate reads this ONE flag regardless
  of which of the owner's cities the steward is targeting.
  """
  @spec set_allow_steward_production(map(), term(), boolean()) :: {:ok, map()} | {:error, atom()}
  def set_allow_steward_production(state, user, allowed?) do
    with {:ok, player} <- fetch_player(state, user.id) do
      updated = %{player | allow_steward_production: allowed?}
      {:ok, %{state | players: Map.put(state.players, player.id, updated)}}
    end
  end

  @doc """
  Sets the offline owner's own production queue — the SAME
  constructive-only catalog `Production.queue_production/4` itself
  already builds from, scoped through stewardship eligibility instead
  of ownership. Persisted immediately, same "not tick-state" status
  `Production.queue_production/4` already has. Playtest issue
  340c1ad4: refuses with `:steward_production_disabled` unless the
  OWNER has granted `Player.allow_steward_production` — empire-wide,
  checked BEFORE `city_id` is ever resolved, so the grant covers every
  city the owner has, not just this one.
  """
  @spec queue_production(map(), term(), term(), term(), atom() | String.t()) ::
          {:ok, map()} | {:error, atom()}
  def queue_production(state, steward_user, owner_user_id, city_id, type) do
    with {:ok, steward_player, owner_player} <- fetch_context(state, steward_user, owner_user_id),
         :ok <- ensure_production_allowed(owner_player),
         {:ok, city} <- fetch_owned_city(state, owner_player, city_id),
         {:ok, type} <- Production.parse_item_type(type),
         :ok <- ensure_constructive(type),
         :ok <-
           Production.can_queue?(city, type,
             granary_available?: Production.granary_available?(state, city),
             bronze_age?: Production.bronze_age?(state, city),
             copper_access?: Production.copper_access?(state, city)
           ) do
      next_position =
        city.queue |> Enum.map(&Map.get(&1, :position, 0)) |> Enum.max(fn -> 0 end) |> Kernel.+(1)

      {:ok, item} =
        %ProductionItem{}
        |> ProductionItem.changeset(
          Production.new_item(type)
          |> Map.put(:city_id, city_id)
          |> Map.put(:position, next_position)
        )
        |> Repo.insert()

      new_city = %{city | queue: city.queue ++ [queue_item_map(item)]}

      log_action!(
        state,
        steward_player.id,
        owner_player.id,
        :production_set,
        %{city_id: city_id, item: type}
      )

      {:ok, %{state | cities: Map.put(state.cities, city_id, new_city)}}
    end
  end

  defp ensure_constructive(type) do
    if constructive_item?(type), do: :ok, else: {:error, :not_constructive}
  end

  # Playtest issue 340c1ad4 — the owner's own empire-wide grant, never
  # the per-city `constructive_item?/1` whitelist's own job. `%Player{}`
  # rows from BEFORE this migration's own default backfilled `false`
  # would already read `false` for a missing key too (`Map.get/3`
  # default), same defensive posture `queue_item_map/1`'s own
  # `Map.get(unit, :charges, 3)` sibling establishes elsewhere.
  defp ensure_production_allowed(owner_player) do
    if Map.get(owner_player, :allow_steward_production, false),
      do: :ok,
      else: {:error, :steward_production_disabled}
  end

  defp fetch_owned_city(state, owner_player, city_id) do
    case Map.get(state.cities, city_id) do
      %{player_id: player_id} = city when player_id == owner_player.id -> {:ok, city}
      _other -> {:error, :not_found}
    end
  end

  defp queue_item_map(%ProductionItem{} = item),
    do: %{
      id: item.id,
      type: item.type,
      banked: item.banked,
      cost: item.cost,
      position: item.position
    }

  # -------------------------------------------------------------------
  # Bank sweep
  # -------------------------------------------------------------------

  @doc """
  `Bank.steward_collect/1` — sweeps the offline owner's ENTIRE bank
  into their own treasury, pure stewardship (the steward's own
  treasury never moves). Logged immediately (not tick-state, same
  "persisted immediately" status every other direct stewardship write
  already has) regardless of the swept amount (even a 0-gold sweep is a
  real, logged action).
  """
  @spec collect_bank(map(), term(), term()) :: {:ok, map()} | {:error, atom()}
  def collect_bank(state, steward_user, owner_user_id) do
    with {:ok, steward_player, owner_player} <- fetch_context(state, steward_user, owner_user_id) do
      {new_owner, swept} = Bank.steward_collect(owner_player)

      log_action!(
        state,
        steward_player.id,
        owner_player.id,
        :bank_collect,
        %{amount: swept}
      )

      {:ok, %{state | players: Map.put(state.players, owner_player.id, new_owner)}}
    end
  end

  # -------------------------------------------------------------------
  # Emergency defense
  # -------------------------------------------------------------------

  @doc """
  Whether the offline owner counts as "under attack" right now — at
  least one of their own units currently carries live damage (`hp <
  max_hp`). The emergency-defense window's own gate.
  """
  @spec under_attack?([unit()]) :: boolean()
  def under_attack?(units), do: Enum.any?(units, &(&1.hp < &1.max_hp))

  @doc """
  Whether `to_tile` is a genuinely DEFENSIVE reposition for a unit
  standing on `current_tile_id` — strictly one of `adjacent_tile_ids`
  (mesh-adjacent to where it already is) and never the tile it's
  already standing on. Refuses both marching the army off (any
  farther tile) and a no-op "defend in place."
  """
  @spec defend_target_allowed?(term(), term(), [term()]) :: boolean()
  def defend_target_allowed?(current_tile_id, to_tile, adjacent_tile_ids),
    do: to_tile != current_tile_id and to_tile in adjacent_tile_ids

  @doc """
  EMERGENCY DEFENSE: three gates, in order — eligible + offline
  (`fetch_context/3`), genuinely `under_attack?/1`, and a
  `defend_target_allowed?/3` destination (strictly adjacent, never the
  unit's own tile). The third gate has two failure shapes: NOT under
  attack at all is a quiet, unlogged refusal (no legitimate emergency
  window ever existed to abuse); under attack but overreaching the
  destination IS provable sabotage — logged AND dinged on the
  steward's own Honor, even though the move itself is still refused.
  Only every gate clearing actually queues and immediately resolves
  the move (`Unit.bfs_path/4` + `Unit.persist_order!/2` +
  `Turn.move_now/2`, the same "orders execute immediately" pattern
  `Unit.queue_move/4` already establishes).
  """
  @spec defend(map(), term(), term(), term(), term()) :: {:ok, map()} | {:error, atom()}
  def defend(state, steward_user, owner_user_id, unit_id, to_tile) do
    with {:ok, steward_player, owner_player} <- fetch_context(state, steward_user, owner_user_id),
         {:ok, unit} <- fetch_owned_unit(state, owner_player, unit_id) do
      resolve_defend(state, steward_player, owner_player, unit, to_tile)
    end
  end

  defp resolve_defend(state, steward_player, owner_player, unit, to_tile) do
    cond do
      not under_attack?(owner_units(state, owner_player.id)) ->
        {:error, :not_under_attack}

      not defend_target_allowed?(
        unit.tile_id,
        to_tile,
        Regions.adjacent_tiles(state.world, unit.tile_id)
      ) ->
        log_action!(
          state,
          steward_player.id,
          owner_player.id,
          :emergency_defense,
          %{unit_id: unit.id, to_tile: to_tile},
          true
        )

        new_state =
          update_in(
            state.players[steward_player.id].honor,
            &apply_sabotage_penalty/1
          )

        {:ok, new_state}

      true ->
        case Unit.bfs_path(state, unit.tile_id, to_tile, unit.type) do
          path when path in [nil, []] ->
            {:error, :unreachable}

          path ->
            Unit.persist_order!(unit.id, path)

            queued = %{
              state
              | orders:
                  Map.put(state.orders, unit.id, %{kind: :move, path: path, status: :pending})
            }

            moved = Turn.move_now(queued, unit.id)

            log_action!(
              state,
              steward_player.id,
              owner_player.id,
              :emergency_defense,
              %{unit_id: unit.id, to_tile: to_tile}
            )

            {:ok, moved}
        end
    end
  end

  defp owner_units(state, owner_player_id) do
    for {_id, u} <- state.units, u.player_id == owner_player_id, do: u
  end

  defp fetch_owned_unit(state, owner_player, unit_id) do
    case Map.get(state.units, unit_id) do
      %{player_id: player_id} = unit when player_id == owner_player.id -> {:ok, unit}
      _other -> {:error, :not_owner}
    end
  end

  # -------------------------------------------------------------------
  # Anti-sabotage
  # -------------------------------------------------------------------

  @doc "How much a provable-sabotage attempt dings the steward's own Honor."
  @spec sabotage_honor_penalty() :: pos_integer()
  def sabotage_honor_penalty, do: @sabotage_honor_penalty

  @doc "`honor - sabotage_honor_penalty/0` — the Honor consequence for provable sabotage."
  @spec apply_sabotage_penalty(integer()) :: integer()
  def apply_sabotage_penalty(honor), do: honor - @sabotage_honor_penalty

  @doc "Builds the attrs map for a fresh `StewardLog` insert — the one shape every steward action's own audit row shares."
  @spec log_attrs(
          term(),
          player_id(),
          player_id(),
          StewardLog.action(),
          map(),
          non_neg_integer(),
          boolean()
        ) :: map()
  def log_attrs(
        world_id,
        steward_player_id,
        owner_player_id,
        action,
        details,
        turn,
        sabotage? \\ false
      ) do
    %{
      world_id: world_id,
      steward_player_id: steward_player_id,
      owner_player_id: owner_player_id,
      action: action,
      details: details,
      turn: turn,
      sabotage: sabotage?
    }
  end

  @doc "Inserts a fresh `StewardLog` row via `log_attrs/7` — the state-taking write every real steward action calls once it clears its own gate."
  @spec log_action!(map(), player_id(), player_id(), StewardLog.action(), map(), boolean()) :: :ok
  def log_action!(
        state,
        steward_player_id,
        owner_player_id,
        action,
        details,
        sabotage? \\ false
      ) do
    %StewardLog{}
    |> StewardLog.changeset(
      log_attrs(
        state.world.id,
        steward_player_id,
        owner_player_id,
        action,
        details,
        state.turn,
        sabotage?
      )
    )
    |> Repo.insert!()

    :ok
  end

  @doc """
  The owner's own full steward-action audit trail (criterion 7695) —
  every `StewardLog` row where THIS player is the one being stewarded,
  freshest first.
  """
  @spec steward_log(map(), term()) :: [map()]
  def steward_log(state, user) do
    case find_player(state, user.id) do
      nil ->
        []

      player ->
        StewardLog
        |> where([s], s.world_id == ^state.world.id and s.owner_player_id == ^player.id)
        |> order_by([s], desc: s.id)
        |> Repo.all()
        |> Enum.map(&format_steward_log(state, &1))
    end
  end

  defp format_steward_log(state, log) do
    steward_player = Map.fetch!(state.players, log.steward_player_id)
    steward_user = Users.get_user!(steward_player.user_id)

    %{
      id: log.id,
      steward_name: User.display_name(steward_user),
      action: log.action,
      turn: log.turn,
      sabotage: log.sabotage
    }
  end

  # -------------------------------------------------------------------
  # Click-through steward view (QA issue bd93cc0a)
  # -------------------------------------------------------------------

  @doc """
  The click-through steward view carried on every OFFLINE household
  member's own `format_vassal/2` (`WorldServer`)/`format_alliance/3`
  row — everything `GameLive.Play`'s own production-stewardship +
  emergency-defend controls need to render REAL options, not a blank
  check. `nil` (never computed at all) whenever the owner is online or
  not currently stewardable, the same "absent means nothing to offer"
  posture `WorldServer.vassal_status/2` already gives a free player's
  own `nil`.
  """
  @spec steward_view(map(), map()) :: map()
  def steward_view(state, owner_player) do
    units = owner_units(state, owner_player.id)
    cities = for {_id, c} <- state.cities, c.player_id == owner_player.id, do: c

    %{
      cities: Enum.map(cities, &steward_city_view(state, &1)),
      under_attack?: under_attack?(units),
      # Only units genuinely worth defending (`under_attack?/1`'s own
      # literal "hp < max_hp" signal) — each carrying its own CURRENT
      # `adjacent_tile_ids` so the rendered defend buttons can never go
      # stale against a unit that's already moved (a stale button would
      # make `defend_target_allowed?/3` refuse as provable sabotage,
      # dinging an innocent steward's own Honor for nothing).
      threatened_units:
        units
        |> Enum.filter(&(&1.hp < &1.max_hp))
        |> Enum.map(&steward_unit_view(state, &1))
    }
  end

  # `catalog` reuses `Production.available_items/1` — the SAME
  # research/copper-gated Build list `GameLive.CityPanel` already reads
  # for the owning player themselves — filtered through
  # `constructive_item?/1` (today a no-op: every buildable type IS
  # already constructive, see this module's own moduledoc, but still
  # the one gate this view is contractually bound to).
  defp steward_city_view(state, city) do
    opts = [
      granary_available?: Production.granary_available?(state, city),
      bronze_age?: Production.bronze_age?(state, city),
      copper_access?: Production.copper_access?(state, city),
      # Story 930 — the same four opts `GameLive.CityPanel`'s own
      # `production_opts/3` resolves for the owner themselves.
      library_available?: Production.library_available?(state, city),
      walls_available?: Production.walls_available?(state, city),
      barracks_available?: Production.barracks_available?(state, city),
      water_mill_available?: Production.water_mill_available?(state, city)
    ]

    catalog =
      opts
      |> Production.available_items()
      |> Enum.filter(&constructive_item?/1)

    %{id: city.id, name: city.name, catalog: catalog}
  end

  defp steward_unit_view(state, unit) do
    %{
      id: unit.id,
      type: unit.type,
      tile_id: unit.tile_id,
      hp: unit.hp,
      max_hp: unit.max_hp,
      adjacent_tile_ids: Regions.adjacent_tiles(state.world, unit.tile_id)
    }
  end

  # -------------------------------------------------------------------
  # Alliances (story 901, click-through payload extended in slice 6)
  # -------------------------------------------------------------------

  @doc "`user`'s own full Alliance list, each row carrying the click-through `steward_view/2` payload while the other side is an accepted, offline ally."
  @spec list_alliances(map(), term()) :: [map()]
  def list_alliances(state, user) do
    case find_player(state, user.id) do
      nil ->
        []

      player ->
        Alliance
        |> where(
          [a],
          a.world_id == ^state.world.id and
            (a.player_a_id == ^player.id or a.player_b_id == ^player.id)
        )
        |> Repo.all()
        |> Enum.map(&format_alliance(state, &1, player.id))
    end
  end

  defp format_alliance(state, alliance, my_player_id) do
    other_player_id =
      if alliance.player_a_id == my_player_id,
        do: alliance.player_b_id,
        else: alliance.player_a_id

    other_player = Map.fetch!(state.players, other_player_id)
    other_user = Users.get_user!(other_player.user_id)
    online? = Presence.online?(state.world, %{id: other_user.id})
    # QA issue bd93cc0a: only an ACCEPTED, offline ally is stewardable
    # at all (`steward_role/4`'s own `:ally` clause reads straight off
    # an accepted `Alliance`) — a merely `:proposed` row, or an online
    # ally, carries no `steward_view/2` payload.
    stewardable? = alliance.status == :accepted and not online?

    %{
      id: alliance.id,
      status: alliance.status,
      proposed_by_me?: alliance.proposer_player_id == my_player_id,
      other_user_id: other_user.id,
      other_name: User.display_name(other_user),
      # Story 910: same "offer Steward only while offline" status
      # `WorldServer.format_vassal/2` already carries.
      online?: online?,
      steward: if(stewardable?, do: steward_view(state, other_player), else: nil)
    }
  end

  # -------------------------------------------------------------------
  # Shared, trivial lookups — duplicated rather than reaching back into
  # `WorldServer`, matching the sibling `BrokenOaths.Units.Unit`/
  # `BrokenOaths.Diplomacy.Cooperation`'s own "pure, process-unaware,
  # unit-testable with no GenServer running" contract (small private
  # helper copies rather than expanding public APIs).
  # -------------------------------------------------------------------

  defp find_player(state, user_id) do
    state.players |> Map.values() |> Enum.find(&(&1.user_id == user_id))
  end

  defp fetch_player(state, user_id) do
    case find_player(state, user_id) do
      nil -> {:error, :not_a_player}
      player -> {:ok, player}
    end
  end
end
