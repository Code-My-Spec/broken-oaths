defmodule BrokenOaths.Game do
  @moduledoc """
  Bounded context for gameplay — join, movement orders, turn advancement,
  fog-filtered reads. A thin client onto each world's `WorldServer`, the
  single serialization point for that world's state (see
  `BrokenOaths.Game.WorldServer`'s moduledoc for the process architecture
  and `BrokenOaths.Game.Turn`'s moduledoc for the tick-state contract
  every read here is filtered through).

  Every function that touches a specific world's live state — everything
  below except `subscribe/1` — lazily starts that world's `WorldServer`
  and round-trips through it, so joins, moves, and turn boundaries are
  never raced against each other.

  ## Module shape (pragdave decomposition)

  This facade used to carry all ~100 public functions itself. Per
  `.code_my_spec/knowledge/genserver_decomposition.md`'s "Game API
  (973) → split by domain" target, the wrapper bodies (and their full
  narrative docs) now live in per-domain sub-facades —
  `BrokenOaths.Game.API.Feudal`, `.Diplomacy` — plus the top-level
  `BrokenOaths.Cities`, `BrokenOaths.Combat`, `BrokenOaths.Players`,
  `BrokenOaths.Technology`, `BrokenOaths.Units`, and `BrokenOaths.
  Vision` contexts (see
  `.code_my_spec/knowledge/genserver_decomposition.md`'s "Target bounded
  contexts" table) — and every one of those functions is
  `defdelegate`d back here unchanged, so no caller needs to know the
  split exists. The one-line `@doc` on each delegate below is a
  pointer; read the sub-facade/context module for the full contract.

  World lifecycle/runtime concerns (join/subscribe, turn clock control,
  and `feudal_enabled?/0`) have no clear single owning domain and stay
  directly on `Game` itself.
  """

  alias BrokenOaths.Cities
  alias BrokenOaths.Combat
  alias BrokenOaths.Game.API.{Diplomacy, Feudal}
  alias BrokenOaths.Game.WorldServer
  alias BrokenOaths.Players
  alias BrokenOaths.Technology
  alias BrokenOaths.Units
  alias BrokenOaths.Vision

  # -------------------------------------------------------------------
  # World lifecycle / runtime
  # -------------------------------------------------------------------

  @doc "Subscribe the caller to `world`'s PubSub topic — broadcasts `{:turn_advanced, turn}`."
  def subscribe(world),
    do: Phoenix.PubSub.subscribe(BrokenOaths.PubSub, WorldServer.topic(world.id))

  @doc """
  Join `world` as `user`: claim a region via `Spawner`, spawn a Lord and
  a Settler, seed initial exploration. Idempotent for an existing member
  (returns the existing player, no re-spawn).
  """
  @spec join_world(map(), map()) :: {:ok, map()} | {:error, :world_full | :membership_limit}
  def join_world(world, user), do: WorldServer.call(world, {:join, user})

  @doc "Any spawnable region left for a new player?"
  @spec world_full?(map()) :: boolean()
  def world_full?(world), do: WorldServer.call(world, :world_full?)

  @doc "The region `user` claimed in `world`, or `nil` if they haven't joined."
  @spec claimed_region(map(), map()) :: term() | nil
  def claimed_region(world, user), do: WorldServer.call(world, {:claimed_region, user})

  @doc "The current turn number."
  def turn_number(world), do: WorldServer.call(world, :turn_number)

  @doc "`DateTime` the next turn boundary fires."
  def turn_ends_at(world), do: WorldServer.call(world, :turn_ends_at)

  @doc "`user`'s current gold in `world`. See `Players.gold/2`."
  defdelegate gold(world, user), to: Players

  @doc "Run one deterministic turn tick — exactly what the 60s timer fires."
  def advance_turn(world), do: WorldServer.call(world, :advance_turn)

  @doc """
  Dev-only QA control surface (see `BrokenOathsWeb.DevQaController`):
  freeze `world`'s turn clock — cancels any pending automatic tick and
  persists `paused: true` so it stays frozen across a server restart.
  `advance_turn/1` (the manual step) still works while paused.
  """
  @spec pause_ticks(map()) :: :ok
  def pause_ticks(world), do: WorldServer.call(world, :pause_ticks)

  @doc """
  Dev-only QA control surface: resume `world`'s turn clock. Resets the
  current turn's start time to now, so resuming never triggers a big
  catch-up for time spent paused.
  """
  @spec resume_ticks(map()) :: :ok
  def resume_ticks(world), do: WorldServer.call(world, :resume_ticks)

  @doc "Dev-only QA control surface: whether `world`'s turn clock is currently paused."
  @spec paused?(map()) :: boolean()
  def paused?(world), do: WorldServer.call(world, :paused?)

  @doc "Stop and lazily-restart `world`'s server; state rehydrates from the DB."
  def restart_world_server(world), do: WorldServer.restart(world)

  @doc "Delete `user`'s civilization in `world` and free their region."
  @spec abandon_world(map(), map()) :: :ok
  def abandon_world(world, user), do: WorldServer.call(world, {:abandon, user})

  @doc """
  Whether the in-progress feudal PvP batch (Siege player-city capture —
  story 906, Vassalization — story 907, Tribute — story 908) is
  reachable at all right now. `config :broken_oaths, :feudal_enabled`
  (`true` in `config/dev.exs` and `config/test.exs`, `false` in
  `config/prod.exs`, `false` by default so anything unset stays safe) —
  the batch is fully built and wired into `WorldServer`, but still
  missing its Bank/Stewardship/first-class panels/QA/balance pass, so
  it must stay dormant in prod until that lands. This is the single
  check point every feudal entry point reads: `Siege.
  attack_city/4`'s own gate (attacking another player's city is
  refused outright, `{:error, :not_hostile}`, restoring the pre-906
  "no Stone Age PvP" rule, exactly like unit-vs-unit `Combat.
  hostile?/2`), `Vassalization.apply_captures/1` (no vassalage), and `apply_tribute/1`
  (no tribute collected) — each a no-op while this reads `false`. The
  feudal LiveView UI (vassals panel, oath screen, vassal-status/
  tribute-rate/levy badges, occupied-city status) never needs its own
  separate check: with capture/vassalage/tribute never created, the
  underlying reads (`vassals/2`, `vassal_status/2`, a city's own
  `Siege.status/1`) stay empty/`:free` on their own. Barbarian city
  assault (`BrokenOaths.Combat.CityDefense`'s pillage path, driven
  entirely by `BrokenOaths.Game.Turn`'s own barbarian-AI phase) never
  touches this flag either way — it was never part of the feudal batch.
  """
  @spec feudal_enabled?() :: boolean()
  def feudal_enabled?, do: Application.get_env(:broken_oaths, :feudal_enabled, false)

  # -------------------------------------------------------------------
  # Research (story 902) — delegated to BrokenOaths.Technology
  # -------------------------------------------------------------------

  @doc "The Stone Age tech catalog. See `Technology.tech_catalog/0`."
  @spec tech_catalog() :: map()
  defdelegate tech_catalog, to: Technology

  @doc "`user`'s research state in `world`. See `Technology.player_research/2`."
  @spec player_research(map(), map()) :: map() | nil
  defdelegate player_research(world, user), to: Technology

  @doc "Select `tech` as `user`'s `current_research` in `world`. See `Technology.set_research/3`."
  @spec set_research(map(), map(), atom()) ::
          :ok
          | {:error, :not_a_player | :invalid_tech | :already_completed | :prereqs_not_met}
  defdelegate set_research(world, user, tech), to: Technology

  # -------------------------------------------------------------------
  # Progress panel (story 904) — delegated to BrokenOaths.Players
  # -------------------------------------------------------------------

  @doc "`user`'s lifetime combat totals in `world`. See `Players.player_stats/2`."
  @spec player_stats(map(), map()) ::
          %{barbarians_killed: non_neg_integer(), camps_destroyed: non_neg_integer()} | nil
  defdelegate player_stats(world, user), to: Players

  # -------------------------------------------------------------------
  # Units (queue_move / orders) — delegated to BrokenOaths.Units
  # -------------------------------------------------------------------

  @doc "All of `user`'s units in `world`, each carrying its queued order (if any). See `Units.player_units/2`."
  defdelegate player_units(world, user), to: Units

  @doc "Queue a move order for `unit_id` to `to_tile`. See `Units.queue_move/4`."
  @spec queue_move(map(), map(), term(), term()) :: {:ok, %{path: [term()]}} | {:error, atom()}
  defdelegate queue_move(world, user, unit_id, to_tile), to: Units

  @doc "Test-only: set a unit's HP directly. See `Units.set_unit_hp_for_test/3`."
  @spec set_unit_hp_for_test(map(), term(), non_neg_integer()) :: :ok
  defdelegate set_unit_hp_for_test(world, unit_id, hp), to: Units

  @doc "Test-only: instantly restore `unit_id`'s movement to its own max. See `Units.recharge_unit_for_test/2`."
  @spec recharge_unit_for_test(map(), term()) :: :ok
  defdelegate recharge_unit_for_test(world, unit_id), to: Units

  @doc "Test-only: instantly relocate `unit_id` to `tile_id`. See `Units.relocate_unit_for_test/3`."
  @spec relocate_unit_for_test(map(), term(), term()) :: :ok | {:error, :occupied}
  defdelegate relocate_unit_for_test(world, unit_id, tile_id), to: Units

  @doc "Dev-only QA control surface: place a REAL player-owned unit at `tile_id`. See `Units.spawn_unit_for_test/4`."
  @spec spawn_unit_for_test(map(), term(), atom(), term()) :: map()
  defdelegate spawn_unit_for_test(world, player_id, type, tile_id), to: Units

  @doc "Dev-only QA control surface: hard-delete `unit_id` outright. See `Units.remove_unit_for_test/2`."
  @spec remove_unit_for_test(map(), term()) :: :ok
  defdelegate remove_unit_for_test(world, unit_id), to: Units

  # -------------------------------------------------------------------
  # Combat (attack, attack_city, garrison fate, camp assault) —
  # delegated to BrokenOaths.Combat
  # -------------------------------------------------------------------

  @doc "Order `unit_id` to attack `target_unit_id` (adjacent, hostile barbarian targets only). See `Combat.attack/4`."
  @spec attack(map(), map(), term(), term()) ::
          {:ok, %{damage_dealt: pos_integer(), damage_taken: pos_integer()}}
          | {:error,
             :not_owner
             | :invalid_target
             | :out_of_movement
             | :not_adjacent
             | :not_hostile}
  defdelegate attack(world, user, unit_id, target_unit_id), to: Combat

  @doc "Order `unit_id` to attack `camp_id` (story 894). See `Combat.attack_camp/4`."
  @spec attack_camp(map(), map(), term(), term()) ::
          {:ok, %{damage_dealt: pos_integer(), damage_taken: 0}}
          | {:error, :not_owner | :invalid_target | :out_of_movement | :not_adjacent}
  defdelegate attack_camp(world, user, unit_id, camp_id), to: Combat

  @doc "Order `unit_id` to attack `city_id` (story 895). See `Combat.attack_city/4`."
  @spec attack_city(map(), map(), term(), term()) ::
          {:ok, %{damage_dealt: non_neg_integer(), damage_taken: non_neg_integer()}}
          | {:error,
             :not_owner
             | :invalid_target
             | :out_of_movement
             | :not_adjacent
             | :own_city
             | :not_military
             | :not_hostile}
  defdelegate attack_city(world, user, unit_id, city_id), to: Combat

  @doc "Resolve the conqueror's execute-or-release choice for a captured city's fallen garrison (story 906). See `Combat.resolve_garrison_fate/4`."
  @spec resolve_garrison_fate(map(), map(), term(), :release | :execute) ::
          :ok | {:error, :invalid_target | :not_owner}
  defdelegate resolve_garrison_fate(world, user, city_id, choice), to: Combat

  @doc "Every barbarian camp in `world`, unfiltered ground truth. See `Combat.list_camps/1`."
  defdelegate list_camps(world), to: Combat

  @doc "Test-only: place a real barbarian warrior directly on `tile_id`. See `Combat.spawn_barbarian_for_test/3`."
  @spec spawn_barbarian_for_test(map(), term(), term()) :: map()
  defdelegate spawn_barbarian_for_test(world, tile_id, camp_id \\ nil), to: Combat

  @doc "Test-only: move a barbarian directly onto `tile_id`. See `Combat.move_barbarian_for_test/3`."
  @spec move_barbarian_for_test(map(), term(), term()) :: :ok | {:error, :occupied}
  defdelegate move_barbarian_for_test(world, barbarian_id, tile_id), to: Combat

  @doc "Test-only: destroy every camp except `keep_camp_id`. See `Combat.isolate_camp_for_test/2`."
  @spec isolate_camp_for_test(map(), term()) :: :ok
  defdelegate isolate_camp_for_test(world, keep_camp_id), to: Combat

  @doc "Test-only: hard-delete every warrior tied to `camp_id`. See `Combat.clear_camp_warriors_for_test/2`."
  @spec clear_camp_warriors_for_test(map(), term()) :: :ok
  defdelegate clear_camp_warriors_for_test(world, camp_id), to: Combat

  @doc "Test-only: resolve an attack FROM a barbarian. See `Combat.resolve_barbarian_attack_for_test/3`."
  @spec resolve_barbarian_attack_for_test(map(), term(), term()) ::
          {:ok, %{damage_dealt: pos_integer(), damage_taken: pos_integer()}} | {:error, atom()}
  defdelegate resolve_barbarian_attack_for_test(world, attacker_unit_id, target_unit_id),
    to: Combat

  @doc "Dev-only QA control surface: set `camp_id`'s HP directly. See `Combat.set_camp_hp_for_test/3`."
  @spec set_camp_hp_for_test(map(), term(), non_neg_integer()) :: :ok
  defdelegate set_camp_hp_for_test(world, camp_id, hp), to: Combat

  # -------------------------------------------------------------------
  # City loop (stories 878-883) — delegated to BrokenOaths.Cities
  # -------------------------------------------------------------------

  @doc "Found a city on `unit_id`'s tile, consuming the settler. See `Cities.found_city/3`."
  @spec found_city(map(), map(), term()) ::
          :ok | {:error, :not_owner | :not_settler | :invalid_terrain | :too_close}
  defdelegate found_city(world, user, unit_id), to: Cities

  @doc "Append `type` to `city_id`'s production queue. See `Cities.queue_production/4`."
  @spec queue_production(map(), map(), term(), atom() | String.t()) ::
          :ok | {:error, :not_owner | :invalid_item | :size_one}
  defdelegate queue_production(world, user, city_id, type), to: Cities

  @doc "Move a queued item one slot toward the head. See `Cities.reorder_production_item/4`."
  @spec reorder_production_item(map(), map(), term(), term()) ::
          :ok | {:error, :not_owner | :not_found | :invalid_item}
  defdelegate reorder_production_item(world, user, city_id, item_id), to: Cities

  @doc "Remove `item_id` from `city_id`'s queue. See `Cities.cancel_production_item/4`."
  @spec cancel_production_item(map(), map(), term(), term()) ::
          :ok | {:error, :not_owner | :not_found}
  defdelegate cancel_production_item(world, user, city_id, item_id), to: Cities

  @doc "Reassign a citizen's worked tile. See `Cities.assign_worked_tile/5`."
  @spec assign_worked_tile(map(), map(), term(), term() | nil, term() | nil) ::
          :ok
          | {:error,
             :not_owner
             | :not_worked
             | :invalid_tile
             | :not_territory
             | :already_worked
             | :invalid_terrain
             | :size_exceeded}
  defdelegate assign_worked_tile(world, user, city_id, from_tile, to_tile), to: Cities

  @doc "Rename `city_id`. Persists immediately. See `Cities.rename_city/4`."
  @spec rename_city(map(), map(), term(), String.t()) ::
          :ok | {:error, :not_owner | :invalid_name}
  defdelegate rename_city(world, user, city_id, name), to: Cities

  @doc "Start (or resume) building `kind` on `unit_id`'s tile. See `Cities.start_improvement/4`."
  @spec start_improvement(map(), map(), term(), atom() | String.t()) ::
          :ok
          | {:error,
             :not_owner
             | :not_worker
             | :invalid_improvement
             | :invalid_terrain
             | :occupied_improvement}
  defdelegate start_improvement(world, user, unit_id, kind), to: Cities

  @doc "Cancel the `:building` improvement on `unit_id`'s tile (QA issue 8aa2c571). See `Cities.cancel_improvement/3`."
  @spec cancel_improvement(map(), map(), term()) ::
          :ok | {:error, :not_owner | :not_worker | :no_active_build}
  defdelegate cancel_improvement(world, user, unit_id), to: Cities

  @doc "All of `user`'s cities in `world`. See `Cities.player_cities/2`."
  defdelegate player_cities(world, user), to: Cities

  @doc "A tile's completed improvement (`nil | :farm | :mine | :road`). See `Cities.tile_improvement/2`."
  defdelegate tile_improvement(world, tile_id), to: Cities

  @doc "Test-only: instantly place a COMPLETE improvement of `kind` on `tile_id`. See `Cities.complete_improvement_for_test/3`."
  @spec complete_improvement_for_test(map(), term(), atom()) :: map()
  defdelegate complete_improvement_for_test(world, tile_id, kind), to: Cities

  @doc "Test-only: grant `city_id` Copper access (story 911). See `Cities.grant_copper_access_for_test/2`."
  @spec grant_copper_access_for_test(map(), term()) ::
          :ok | {:error, :no_copper_on_map | :not_found}
  defdelegate grant_copper_access_for_test(world, city_id), to: Cities

  # -------------------------------------------------------------------
  # Diplomacy — discovery/known-players, alliance/cooperation
  # (chat is its own separate context — see `BrokenOaths.Chat`) —
  # delegated to BrokenOaths.Game.API.Diplomacy
  # -------------------------------------------------------------------

  @doc "Every civilization `user` has discovered in `world` (story 899). See `Diplomacy.known_players/2`."
  defdelegate known_players(world, user), to: Diplomacy

  @doc "Every alliance `user` is a party to in `world` (story 901). See `Diplomacy.alliances/2`."
  @spec alliances(map(), map()) :: [map()]
  defdelegate alliances(world, user), to: Diplomacy

  @doc "Propose an alliance between `user` and `other_user` in `world`. See `Diplomacy.propose_alliance/3`."
  @spec propose_alliance(map(), map(), map()) ::
          :ok
          | {:error, :not_a_player | :already_proposed | :already_allied | Ecto.Changeset.t()}
  defdelegate propose_alliance(world, user, other_user), to: Diplomacy

  @doc "Accept `alliance_id`, a pending alliance `user` is the other party to. See `Diplomacy.accept_alliance/3`."
  @spec accept_alliance(map(), map(), term()) ::
          :ok
          | {:error,
             :not_found
             | :not_a_party
             | :self_accept
             | :already_accepted
             | Ecto.Changeset.t()}
  defdelegate accept_alliance(world, user, alliance_id), to: Diplomacy

  # -------------------------------------------------------------------
  # Vassalage / Tribute (stories 907/908) —
  # delegated to BrokenOaths.Game.API.Feudal
  # -------------------------------------------------------------------

  @doc "The lord's own \"Vassals\" list in `world` (story 907/908). See `Feudal.vassals/2`."
  @spec vassals(map(), map()) :: [map()]
  defdelegate vassals(world, user), to: Feudal

  @doc "`user`'s own oath, if any, or `nil` for a free player. See `Feudal.vassal_status/2`."
  @spec vassal_status(map(), map()) :: map() | nil
  defdelegate vassal_status(world, user), to: Feudal

  @doc "Record `user`'s own secret Hidden Agenda pick from the Oath screen. See `Feudal.choose_hidden_agenda/3`."
  @spec choose_hidden_agenda(map(), map(), atom()) ::
          :ok | {:error, :not_a_vassal | Ecto.Changeset.t()}
  defdelegate choose_hidden_agenda(world, user, agenda), to: Feudal

  @doc "Raise or lower `vassal_user_id`'s own tribute rate (0.0-1.0). See `Feudal.set_tribute_rate/4`."
  @spec set_tribute_rate(map(), map(), term(), float()) ::
          :ok | {:error, :not_a_player | :not_a_vassal | Ecto.Changeset.t()}
  defdelegate set_tribute_rate(world, user, vassal_user_id, rate), to: Feudal

  @doc "Issue a call to arms (story 908). See `Feudal.issue_levy/5`."
  @spec issue_levy(map(), map(), term(), term(), float()) ::
          :ok | {:error, :not_a_player | :not_a_vassal | Ecto.Changeset.t()}
  defdelegate issue_levy(world, user, vassal_user_id, target_user_id, share), to: Feudal

  @doc "The vassal answers their own lord's pending call to arms. See `Feudal.answer_levy/3`."
  @spec answer_levy(map(), map(), term()) ::
          :ok | {:error, :not_a_player | :not_found | Ecto.Changeset.t()}
  defdelegate answer_levy(world, user, lord_user_id), to: Feudal

  @doc "The vassal refuses their own lord's pending call. See `Feudal.refuse_levy/3`."
  @spec refuse_levy(map(), map(), term()) ::
          :ok | {:error, :not_a_player | :not_found | Ecto.Changeset.t()}
  defdelegate refuse_levy(world, user, lord_user_id), to: Feudal

  # -------------------------------------------------------------------
  # Oath Strain concessions / Protection Pact (stories 913/914) —
  # delegated to BrokenOaths.Game.API.Feudal
  # -------------------------------------------------------------------

  @doc "`user` (the lord) gifts `vassal_user_id`, easing their Oath Strain. See `Feudal.gift_vassal/3`."
  @spec gift_vassal(map(), map(), term()) ::
          :ok | {:error, :not_a_player | :not_a_vassal | Ecto.Changeset.t()}
  defdelegate gift_vassal(world, user, vassal_user_id), to: Feudal

  @doc "`user` and `vassal_user_id` declare `enemy_user_id` a shared enemy. See `Feudal.declare_shared_enemy/4`."
  @spec declare_shared_enemy(map(), map(), term(), term()) ::
          :ok | {:error, :not_a_player | :not_a_vassal | Ecto.Changeset.t()}
  defdelegate declare_shared_enemy(world, user, vassal_user_id, enemy_user_id), to: Feudal

  @doc "The vassal marks their own bond with `lord_user_id` unhonored. See `Feudal.mark_pact_unhonored/3`."
  @spec mark_pact_unhonored(map(), map(), term()) ::
          :ok | {:error, :not_a_player | :not_a_vassal | Ecto.Changeset.t()}
  defdelegate mark_pact_unhonored(world, user, lord_user_id), to: Feudal

  # -------------------------------------------------------------------
  # Rebellion (stories 915/919) — delegated to BrokenOaths.Game.API.Feudal
  # -------------------------------------------------------------------

  @doc "Read-only preview of what declaring independence against `lord_user_id` would do RIGHT NOW. See `Feudal.independence_preview/3`."
  @spec independence_preview(map(), map(), term()) ::
          {:ok, %{cities: [%{city_id: term(), will_rise?: boolean()}], army_size: pos_integer()}}
          | {:error, :not_a_player | :not_a_vassal}
  defdelegate independence_preview(world, user, lord_user_id), to: Feudal

  @doc "`user` declares independence from `lord_user_id` (story 915). See `Feudal.declare_independence/3`."
  @spec declare_independence(map(), map(), term()) ::
          {:ok, BrokenOaths.Game.Rebellion.t()}
          | {:error, :not_a_player | :not_a_vassal | Ecto.Changeset.t()}
  defdelegate declare_independence(world, user, lord_user_id), to: Feudal

  @doc "Story 917: whether `lord_user_id`'s own Lord unit is currently dead on the board. See `Feudal.lord_fallen?/2`."
  @spec lord_fallen?(map(), term()) :: boolean()
  defdelegate lord_fallen?(world, lord_user_id), to: Feudal

  @doc "`user`'s own active-or-most-recent Rebellion as REBEL, or `nil`. See `Feudal.rebellion_status/2`."
  @spec rebellion_status(map(), map()) :: map() | nil
  defdelegate rebellion_status(world, user), to: Feudal

  @doc "Every Rebellion raised against `user` as the FORMER LORD. See `Feudal.rebellions_as_lord/2`."
  @spec rebellions_as_lord(map(), map()) :: [map()]
  defdelegate rebellions_as_lord(world, user), to: Feudal

  @doc "Either side of an active Rebellion offers a negotiated peace (story 919). See `Feudal.offer_peace/5`."
  @spec offer_peace(map(), map(), term(), String.t(), non_neg_integer() | nil) ::
          :ok | {:error, :not_a_player | :no_active_rebellion}
  defdelegate offer_peace(world, user, counterparty_user_id, outcome, reparations_gold), to: Feudal

  @doc "`user` accepts `counterparty_user_id`'s own pending peace offer. See `Feudal.accept_peace/3`."
  @spec accept_peace(map(), map(), term()) ::
          :ok | {:error, :not_a_player | :no_active_rebellion | :no_pending_offer}
  defdelegate accept_peace(world, user, counterparty_user_id), to: Feudal

  @doc "`user` rejects `counterparty_user_id`'s own pending peace offer. See `Feudal.reject_peace/3`."
  @spec reject_peace(map(), map(), term()) :: :ok | {:error, :not_a_player | :no_active_rebellion}
  defdelegate reject_peace(world, user, counterparty_user_id), to: Feudal

  # -------------------------------------------------------------------
  # Coordinated Rebellion — Pact of Broken Oaths (story 916) —
  # delegated to BrokenOaths.Game.API.Feudal
  # -------------------------------------------------------------------

  @doc "`user`'s own membership in an active Pact of Broken Oaths, or `nil`. See `Feudal.pact_view/2`."
  @spec pact_view(map(), map()) :: map() | nil
  defdelegate pact_view(world, user), to: Feudal

  @doc "Every FELLOW vassal of `user`'s own lord — the eligible-to-invite roster. See `Feudal.pact_candidates/2`."
  @spec pact_candidates(map(), map()) :: [%{user_id: term(), email: String.t()}]
  defdelegate pact_candidates(world, user), to: Feudal

  @doc "`user` (a vassal) opens a Pact of Broken Oaths against their own lord. See `Feudal.open_pact_chat/4`."
  @spec open_pact_chat(map(), map(), pos_integer() | String.t(), [term()]) ::
          {:ok, BrokenOaths.Game.RebellionPact.t()}
          | {:error, :not_a_player | :not_a_vassal | :invalid_strike_turn | Ecto.Changeset.t()}
  defdelegate open_pact_chat(world, user, strike_turn, invitee_user_ids), to: Feudal

  @doc "`user` secretly commits to strike with their own pact. See `Feudal.pact_commit/2`."
  @spec pact_commit(map(), map()) ::
          {:ok, BrokenOaths.Game.RebellionPactMember.t()}
          | {:error, :not_a_player | :not_a_pact_member}
  defdelegate pact_commit(world, user), to: Feudal

  @doc "`user` secretly declines to strike with their own pact. See `Feudal.pact_decline/2`."
  @spec pact_decline(map(), map()) ::
          {:ok, BrokenOaths.Game.RebellionPactMember.t()}
          | {:error, :not_a_player | :not_a_pact_member}
  defdelegate pact_decline(world, user), to: Feudal

  @doc "`user` secretly informs their own pact's targeted lord of the plot. See `Feudal.pact_inform/2`."
  @spec pact_inform(map(), map()) ::
          {:ok, BrokenOaths.Game.RebellionPactMember.t()}
          | {:error, :not_a_player | :not_a_pact_member}
  defdelegate pact_inform(world, user), to: Feudal

  @doc "`user`'s own warning that a plot against them has been informed on, or `nil`. See `Feudal.pact_informed_notice/2`."
  @spec pact_informed_notice(map(), map()) :: %{strike_turn: pos_integer()} | nil
  defdelegate pact_informed_notice(world, user), to: Feudal

  @doc "`user`'s own coarse conspiracy \"heat\" gauge (story 916). See `Feudal.conspiracy_heat/2`."
  @spec conspiracy_heat(map(), map()) :: BrokenOaths.Game.OathStrain.strain()
  defdelegate conspiracy_heat(world, user), to: Feudal

  @doc "`user` (a lord) fully heals every one of their own cities. See `Feudal.brace_defenses/2`."
  @spec brace_defenses(map(), map()) :: :ok | {:error, :not_a_player}
  defdelegate brace_defenses(world, user), to: Feudal

  @doc "`user` (a lord) fully heals their own Lord unit. See `Feudal.reposition_lord/2`."
  @spec reposition_lord(map(), map()) :: :ok | {:error, :not_a_player | :no_lord_unit}
  defdelegate reposition_lord(world, user), to: Feudal

  @doc "`user` (a lord) eases EVERY one of their own vassals' Oath Strain at once. See `Feudal.buy_off_conspirators/2`."
  @spec buy_off_conspirators(map(), map()) :: :ok | {:error, :not_a_player}
  defdelegate buy_off_conspirators(world, user), to: Feudal

  @doc "`user` (a lord) honors an overdue Protection Pact call for `vassal_user_id`. See `Feudal.honor_protection_call/3`."
  @spec honor_protection_call(map(), map(), term()) ::
          :ok | {:error, :not_a_player | :not_a_vassal | Ecto.Changeset.t()}
  defdelegate honor_protection_call(world, user, vassal_user_id), to: Feudal

  # -------------------------------------------------------------------
  # Gold Bank (story 909) — delegated to BrokenOaths.Game.API.Feudal
  # -------------------------------------------------------------------

  @doc "`user`'s own bank status: `%{gold:, cap:}`. See `Feudal.bank/2`."
  @spec bank(map(), map()) :: %{gold: non_neg_integer(), cap: pos_integer()}
  defdelegate bank(world, user), to: Feudal

  @doc "Sweep `user`'s own bank into their treasury. See `Feudal.collect_bank/2`."
  @spec collect_bank(map(), map()) :: :ok | {:error, :not_a_player | :feudal_disabled}
  defdelegate collect_bank(world, user), to: Feudal

  @doc "Raise `user`'s own bank cap for its gold price. See `Feudal.upgrade_bank/2`."
  @spec upgrade_bank(map(), map()) ::
          :ok | {:error, :not_a_player | :insufficient_gold | :feudal_disabled}
  defdelegate upgrade_bank(world, user), to: Feudal

  # -------------------------------------------------------------------
  # Feudal Stewardship (story 910) — delegated to BrokenOaths.Game.API.Feudal
  # -------------------------------------------------------------------

  @doc "`user`'s own world-visible Honor reputation figure. See `Feudal.honor/2`."
  @spec honor(map(), map()) :: integer()
  defdelegate honor(world, user), to: Feudal

  @doc "`user`'s own full steward-action audit trail, freshest first. See `Feudal.steward_log/2`."
  @spec steward_log(map(), map()) :: [map()]
  defdelegate steward_log(world, user), to: Feudal

  @doc "`steward_user` sweeps `owner_user_id`'s own offline Gold Bank into the OWNER's treasury. See `Feudal.steward_collect_bank/3`."
  @spec steward_collect_bank(map(), map(), term()) ::
          :ok | {:error, :not_a_player | :not_eligible | :owner_online | :feudal_disabled}
  defdelegate steward_collect_bank(world, steward_user, owner_user_id), to: Feudal

  @doc "`steward_user` sets `owner_user_id`'s own production queue — constructive-only. See `Feudal.steward_queue_production/5`."
  @spec steward_queue_production(map(), map(), term(), term(), atom() | String.t()) ::
          :ok
          | {:error,
             :not_a_player
             | :not_eligible
             | :owner_online
             | :not_found
             | :not_constructive
             | :invalid_item
             | :feudal_disabled
             | atom()}
  defdelegate steward_queue_production(world, steward_user, owner_user_id, city_id, type),
    to: Feudal

  @doc "Always refused — no cancel-griefing (story 910). See `Feudal.steward_cancel_production_item/5`."
  @spec steward_cancel_production_item(map(), map(), term(), term(), term()) ::
          {:error, :not_constructive}
  defdelegate steward_cancel_production_item(world, steward_user, owner_user_id, city_id, item_id),
    to: Feudal

  @doc "Always refused — no disbanding (story 910). See `Feudal.steward_disband_unit/4`."
  @spec steward_disband_unit(map(), map(), term(), term()) :: {:error, :not_constructive}
  defdelegate steward_disband_unit(world, steward_user, owner_user_id, unit_id), to: Feudal

  @doc "Always refused — the default-closed baseline `steward_defend/5` opens against. See `Feudal.steward_queue_move/5`."
  @spec steward_queue_move(map(), map(), term(), term(), term()) :: {:error, :not_allowed}
  defdelegate steward_queue_move(world, steward_user, owner_user_id, unit_id, to_tile \\ nil),
    to: Feudal

  @doc "Always refused — a steward may never launch aggression (story 910). See `Feudal.steward_attack/5`."
  @spec steward_attack(map(), map(), term(), term(), term()) :: {:error, :not_allowed}
  defdelegate steward_attack(world, steward_user, owner_user_id, unit_id, target_camp_id \\ nil),
    to: Feudal

  @doc "EMERGENCY DEFENSE: `steward_user` orders `owner_user_id`'s own unit to a strictly adjacent tile. See `Feudal.steward_defend/5`."
  @spec steward_defend(map(), map(), term(), term(), term()) ::
          :ok
          | {:error,
             :not_a_player
             | :not_eligible
             | :owner_online
             | :not_owner
             | :not_under_attack
             | :unreachable
             | :feudal_disabled}
  defdelegate steward_defend(world, steward_user, owner_user_id, unit_id, to_tile), to: Feudal

  # -------------------------------------------------------------------
  # Feudal test-only seams (gold/honor) —
  # delegated to BrokenOaths.Game.API.Feudal
  # -------------------------------------------------------------------

  @doc "Test-only: set `user`'s own gold treasury directly. See `Feudal.set_player_gold_for_test/3`."
  @spec set_player_gold_for_test(map(), map(), integer()) :: :ok
  defdelegate set_player_gold_for_test(world, user, gold), to: Feudal

  @doc "Test-only: declares `user`'s per-turn gold INCOME, separate from their treasury. See `Feudal.set_player_gold_income_for_test/3`."
  @spec set_player_gold_income_for_test(map(), map(), integer()) :: :ok
  defdelegate set_player_gold_income_for_test(world, user, income), to: Feudal

  @doc "Test-only: set `user`'s own world-visible Honor reputation directly. See `Feudal.set_player_honor_for_test/3`."
  @spec set_player_honor_for_test(map(), map(), integer()) :: :ok
  defdelegate set_player_honor_for_test(world, user, honor), to: Feudal

  # -------------------------------------------------------------------
  # Vision (fog-filtered reads) — delegated to BrokenOaths.Vision
  # -------------------------------------------------------------------

  @doc "Fog-filtered units `user` can currently see. See `Vision.units_visible_to/2`."
  defdelegate units_visible_to(world, user), to: Vision

  @doc "`%{visible: [tile_id], explored: [tile_id]}` for `user`. See `Vision.visibility/2`."
  defdelegate visibility(world, user), to: Vision

  @doc "Barbarian camps `user` currently knows about (story 892). See `Vision.camps_visible_to/2`."
  defdelegate camps_visible_to(world, user), to: Vision

  @doc "Enemy cities `user` currently knows about (QA issue 56ee521a). See `Vision.enemy_cities_visible_to/2`."
  @spec enemy_cities_visible_to(map(), map()) :: [map()]
  defdelegate enemy_cities_visible_to(world, user), to: Vision

  @doc "Cities `user` has personally captured (QA issue ffa66192). See `Vision.captured_cities_visible_to/2`."
  @spec captured_cities_visible_to(map(), map()) :: [map()]
  defdelegate captured_cities_visible_to(world, user), to: Vision

  @doc "Improvements on tiles the player knows (home region or explored). See `Vision.improvements_visible_to/2`."
  defdelegate improvements_visible_to(world, user), to: Vision
end
