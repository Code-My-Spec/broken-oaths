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
  """

  alias BrokenOaths.Game.WorldServer

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

  @doc "All of `user`'s units in `world`, each carrying its queued order (if any)."
  def player_units(world, user), do: WorldServer.call(world, {:player_units, user})

  @doc "Fog-filtered units `user` can currently see — own units always, others only while visible."
  def units_visible_to(world, user), do: WorldServer.call(world, {:units_visible_to, user})

  @doc "`%{visible: [tile_id], explored: [tile_id]}` for `user`."
  def visibility(world, user), do: WorldServer.call(world, {:visibility, user})

  @doc "The current turn number."
  def turn_number(world), do: WorldServer.call(world, :turn_number)

  @doc "`DateTime` the next turn boundary fires."
  def turn_ends_at(world), do: WorldServer.call(world, :turn_ends_at)

  @doc "`user`'s current gold in `world`."
  def gold(world, user), do: WorldServer.call(world, {:gold, user})

  @doc """
  Queue a move order for `unit_id` to `to_tile`, replacing any existing
  order. Validates ownership and a passable (`:land`), unoccupied
  destination, then computes a shortest path over land tiles.
  """
  @spec queue_move(map(), map(), term(), term()) :: {:ok, %{path: [term()]}} | {:error, atom()}
  def queue_move(world, user, unit_id, to_tile),
    do: WorldServer.call(world, {:queue_move, user, unit_id, to_tile})

  @doc """
  Order `unit_id` to attack `target_unit_id`: adjacent, hostile
  (barbarian) targets only — see `BrokenOaths.Game.Combat` for the
  legality rules and damage math. Resolves immediately, like
  `queue_move/4`, and spends all of the attacker's remaining movement.
  """
  @spec attack(map(), map(), term(), term()) ::
          {:ok, %{damage_dealt: pos_integer(), damage_taken: pos_integer()}}
          | {:error,
             :not_owner
             | :invalid_target
             | :out_of_movement
             | :not_adjacent
             | :not_hostile}
  def attack(world, user, unit_id, target_unit_id),
    do: WorldServer.call(world, {:attack, user, unit_id, target_unit_id})

  @doc """
  Order `unit_id` to attack `camp_id` (story 894): adjacent, not yet
  destroyed camps only. Flat damage (`Game.Combat.camp_damage/2`, no
  counter) — resolves immediately, like `attack/4`. A camp reduced to 0
  HP is destroyed: `user` is paid `Game.Camps.destroy_reward/0` gold,
  the camp stops spawning and disappears from `camps_visible_to/2`, and
  its former tile is ordinary land again.
  """
  @spec attack_camp(map(), map(), term(), term()) ::
          {:ok, %{damage_dealt: pos_integer(), damage_taken: 0}}
          | {:error, :not_owner | :invalid_target | :out_of_movement | :not_adjacent}
  def attack_camp(world, user, unit_id, camp_id),
    do: WorldServer.call(world, {:attack_camp, user, unit_id, camp_id})

  @doc """
  Order `unit_id` to attack `city_id` (story 895): adjacent, not the
  attacker's own city. Resolves immediately, like `attack/4` — damage
  to the city's own HP (pillaged, not captured, at 0 — see
  `BrokenOaths.Game.CityDefense`) and counter-attack damage the
  attacker takes from the city's strongest garrisoned defender (0 if
  undefended).
  """
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
  def attack_city(world, user, unit_id, city_id),
    do: WorldServer.call(world, {:attack_city, user, unit_id, city_id})

  @doc """
  Resolve the conqueror's own execute-or-release choice for a captured
  city's fallen garrison (story 906): `choice` is `:release` (the
  garrison survives untouched) or `:execute` (removed from the board).
  `user` must be `city_id`'s own captor.
  """
  @spec resolve_garrison_fate(map(), map(), term(), :release | :execute) ::
          :ok | {:error, :invalid_target | :not_owner}
  def resolve_garrison_fate(world, user, city_id, choice),
    do: WorldServer.call(world, {:resolve_garrison_fate, user, city_id, choice})

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

  # -------------------------------------------------------------------
  # City loop (stories 878-883)
  # -------------------------------------------------------------------

  @doc """
  Found a city on `unit_id`'s tile: the settler must be `user`'s, the
  tile must be passable land at least 4 hexes from every existing
  city. Consumes the settler and creates a working size-1 city
  immediately — no turn boundary required.
  """
  @spec found_city(map(), map(), term()) ::
          :ok | {:error, :not_owner | :not_settler | :invalid_terrain | :too_close}
  def found_city(world, user, unit_id), do: WorldServer.call(world, {:found_city, user, unit_id})

  @doc """
  Append `type` (`:settler`, `:worker`, or `:warrior`) to `city_id`'s
  production queue. A size-1 city cannot queue a Settler.
  """
  @spec queue_production(map(), map(), term(), atom() | String.t()) ::
          :ok | {:error, :not_owner | :invalid_item | :size_one}
  def queue_production(world, user, city_id, type),
    do: WorldServer.call(world, {:queue_production, user, city_id, type})

  @doc "Move a queued item one slot toward the head — free, progress stays with the item."
  @spec reorder_production_item(map(), map(), term(), term()) ::
          :ok | {:error, :not_owner | :not_found | :invalid_item}
  def reorder_production_item(world, user, city_id, item_id),
    do: WorldServer.call(world, {:reorder_production_item, user, city_id, item_id})

  @doc "Remove `item_id` from `city_id`'s queue, forfeiting any production already banked on it."
  @spec cancel_production_item(map(), map(), term(), term()) ::
          :ok | {:error, :not_owner | :not_found}
  def cancel_production_item(world, user, city_id, item_id),
    do: WorldServer.call(world, {:cancel_production_item, user, city_id, item_id})

  @doc """
  Reassign a citizen's worked tile: `from_tile`/`to_tile` are each
  optionally `nil` (unassign only, assign an idle citizen only, or
  both for an ordinary reassignment). Assigning a `to_tile` with no
  paired `from_tile` is refused once the city is already working as
  many tiles as its `size` allows (`:size_exceeded`) — a paired swap
  never grows the count, so it stays allowed at the cap.
  """
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
  def assign_worked_tile(world, user, city_id, from_tile, to_tile),
    do: WorldServer.call(world, {:assign_worked_tile, user, city_id, from_tile, to_tile})

  @doc "Rename `city_id`. Persists immediately."
  @spec rename_city(map(), map(), term(), String.t()) ::
          :ok | {:error, :not_owner | :invalid_name}
  def rename_city(world, user, city_id, name),
    do: WorldServer.call(world, {:rename_city, user, city_id, name})

  @doc """
  Start (or resume) building `kind` (`:farm`, `:mine`, or `:road`) on
  `unit_id`'s tile — `unit_id` must be a `:worker` owned by `user`.
  """
  @spec start_improvement(map(), map(), term(), atom() | String.t()) ::
          :ok
          | {:error,
             :not_owner
             | :not_worker
             | :invalid_improvement
             | :invalid_terrain
             | :occupied_improvement}
  def start_improvement(world, user, unit_id, kind),
    do: WorldServer.call(world, {:start_improvement, user, unit_id, kind})

  @doc """
  Cancel the `:building` improvement on `unit_id`'s tile (QA issue
  8aa2c571 — a worker mid-dig had no way to back out of it). `unit_id`
  must be a `:worker` owned by `user`, standing on a tile that
  currently carries a `:building` improvement (any kind — the same
  `:building` gate `BrokenOathsWeb.GameLive.Play`'s `worker_current_dig/2`
  already uses to show the dig-progress badge). The improvement row is
  deleted outright — progress is discarded, not merely frozen the way
  walking the worker away already freezes it — so the tile is
  immediately free for ANY kind to start fresh, and the worker is free
  to queue a different build (or move) in the very same turn.
  """
  @spec cancel_improvement(map(), map(), term()) ::
          :ok | {:error, :not_owner | :not_worker | :no_active_build}
  def cancel_improvement(world, user, unit_id),
    do: WorldServer.call(world, {:cancel_improvement, user, unit_id})

  @doc "All of `user`'s cities in `world` (see `BrokenOaths.Game.WorldServer` for the shape)."
  def player_cities(world, user), do: WorldServer.call(world, {:player_cities, user})

  @doc """
  Every civilization `user` has discovered in `world` (story 899):
  `[%{user_id:, email:}]`. Permanent once recorded — unrelated to
  current fog of war, see `BrokenOaths.Game.Discovery` and
  `BrokenOaths.Game.KnownPlayer`.
  """
  def known_players(world, user), do: WorldServer.call(world, {:known_players, user})

  @doc """
  Every alliance (`:proposed` or `:accepted`) `user` is a party to in
  `world` (story 901) — `[%{id:, status:, proposed_by_me?:,
  other_user_id:, other_email:}]`, the OTHER party's identity resolved
  for each row so `GameLive.AlliancePanel` never has to cross-reference
  a raw `player_id` itself. See `BrokenOaths.Game.Alliance` and
  `BrokenOaths.Game.Cooperation`'s propose/accept business rules —
  cooperative bounty splitting on a shared barbarian kill never
  requires one of these rows to exist (criterion 7624); an alliance is
  purely the player-facing coordination signal this panel surfaces.
  """
  @spec alliances(map(), map()) :: [map()]
  def alliances(world, user), do: WorldServer.call(world, {:alliances, user})

  @doc """
  Propose an alliance between `user` and `other_user` in `world` —
  refused if either isn't a member, or a proposal/alliance between the
  two already exists (`BrokenOaths.Game.Cooperation.propose/4`).
  """
  @spec propose_alliance(map(), map(), map()) ::
          :ok
          | {:error, :not_a_player | :already_proposed | :already_allied | Ecto.Changeset.t()}
  def propose_alliance(world, user, other_user),
    do: WorldServer.call(world, {:propose_alliance, user, other_user})

  @doc """
  Accept `alliance_id`, a pending alliance `user` is the (non-proposing)
  other party to (`BrokenOaths.Game.Cooperation.accept/2`).
  """
  @spec accept_alliance(map(), map(), term()) ::
          :ok
          | {:error,
             :not_found
             | :not_a_party
             | :self_accept
             | :already_accepted
             | Ecto.Changeset.t()}
  def accept_alliance(world, user, alliance_id),
    do: WorldServer.call(world, {:accept_alliance, user, alliance_id})

  # -------------------------------------------------------------------
  # Vassalage / Tribute (stories 907/908)
  # -------------------------------------------------------------------

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
  assault (`BrokenOaths.Game.CityDefense`'s pillage path, driven
  entirely by `BrokenOaths.Game.Turn`'s own barbarian-AI phase) never
  touches this flag either way — it was never part of the feudal batch.
  """
  @spec feudal_enabled?() :: boolean()
  def feudal_enabled?, do: Application.get_env(:broken_oaths, :feudal_enabled, false)

  @doc """
  The lord's own "Vassals" list in `world` (story 907/908):
  `[%{vassal_user_id:, email:, tribute_rate:, oath_strain:, levy_status:}]`
  for every ACTIVE vassalage `user` holds as lord — never carries the
  vassal's own secret Hidden Agenda (see `vassal_status/2`'s own doc
  for where that lives).
  """
  @spec vassals(map(), map()) :: [map()]
  def vassals(world, user), do: WorldServer.call(world, {:vassals, user})

  @doc """
  `user`'s own oath, if any: `%{lord_user_id:, lord_email:,
  tribute_rate:, oath_strain:, agenda_pending?:, levy_status:,
  lord_fallen?:}`, or `nil` for a free player. `agenda_pending?` is the
  Oath screen's own trigger — `true` until `choose_hidden_agenda/3`
  closes it. `lord_fallen?` (story 917) is `true` once the lord's own
  Lord unit is dead — `GameLive.Play`'s own "seize the moment" trigger.
  """
  @spec vassal_status(map(), map()) :: map() | nil
  def vassal_status(world, user), do: WorldServer.call(world, {:vassal_status, user})

  @doc """
  Record `user`'s own secret Hidden Agenda pick from the Oath screen —
  refused unless `user` is a vassal still awaiting one.
  """
  @spec choose_hidden_agenda(map(), map(), atom()) ::
          :ok | {:error, :not_a_vassal | Ecto.Changeset.t()}
  def choose_hidden_agenda(world, user, agenda),
    do: WorldServer.call(world, {:choose_hidden_agenda, user, agenda})

  @doc """
  Raise or lower `vassal_user_id`'s own tribute rate (0.0-1.0) — `user`
  must be their lord. Takes effect on the vassal's next turn boundary
  tribute.
  """
  @spec set_tribute_rate(map(), map(), term(), float()) ::
          :ok | {:error, :not_a_player | :not_a_vassal | Ecto.Changeset.t()}
  def set_tribute_rate(world, user, vassal_user_id, rate),
    do: WorldServer.call(world, {:set_tribute_rate, user, vassal_user_id, rate})

  @doc """
  Issue a call to arms (story 908): `user` (the lord) calls
  `vassal_user_id` to pledge `share` (0, 1] of their standing army
  against `target_user_id` — a third player, never the lord or the
  vassal themselves.
  """
  @spec issue_levy(map(), map(), term(), term(), float()) ::
          :ok | {:error, :not_a_player | :not_a_vassal | Ecto.Changeset.t()}
  def issue_levy(world, user, vassal_user_id, target_user_id, share),
    do: WorldServer.call(world, {:issue_levy, user, vassal_user_id, target_user_id, share})

  @doc "The vassal (`user`) answers their own lord's pending call to arms — they keep command of the pledged units."
  @spec answer_levy(map(), map(), term()) ::
          :ok | {:error, :not_a_player | :not_found | Ecto.Changeset.t()}
  def answer_levy(world, user, lord_user_id),
    do: WorldServer.call(world, {:answer_levy, user, lord_user_id})

  @doc "The vassal (`user`) refuses their own lord's pending call — spikes their own Oath Strain."
  @spec refuse_levy(map(), map(), term()) ::
          :ok | {:error, :not_a_player | :not_found | Ecto.Changeset.t()}
  def refuse_levy(world, user, lord_user_id),
    do: WorldServer.call(world, {:refuse_levy, user, lord_user_id})

  # -------------------------------------------------------------------
  # Oath Strain concessions / Protection Pact (stories 913/914)
  # -------------------------------------------------------------------

  @doc """
  `user` (the lord) gifts `vassal_user_id` — a one-off concession that
  eases their Oath Strain (`BrokenOaths.Game.OathStrain.ease_gift/1`).
  """
  @spec gift_vassal(map(), map(), term()) ::
          :ok | {:error, :not_a_player | :not_a_vassal | Ecto.Changeset.t()}
  def gift_vassal(world, user, vassal_user_id),
    do: WorldServer.call(world, {:gift_vassal, user, vassal_user_id})

  @doc """
  `user` (the lord) and `vassal_user_id` declare `enemy_user_id` a
  shared enemy — eases the vassal's Oath Strain
  (`BrokenOaths.Game.OathStrain.ease_shared_enemy/1`).
  """
  @spec declare_shared_enemy(map(), map(), term(), term()) ::
          :ok | {:error, :not_a_player | :not_a_vassal | Ecto.Changeset.t()}
  def declare_shared_enemy(world, user, vassal_user_id, enemy_user_id),
    do: WorldServer.call(world, {:declare_shared_enemy, user, vassal_user_id, enemy_user_id})

  @doc """
  The vassal (`user`) marks their own bond with `lord_user_id`
  unhonored — spikes their own Oath Strain
  (`BrokenOaths.Game.OathStrain.spike_broken_protection_pact/1`). See
  `BrokenOaths.Game.WorldServer`'s own `handle_call/3` doc for how this
  narrow, vassal-driven seam differs from the real Protection Pact
  engine's own broken-pact resolution (a window genuinely expiring
  unanswered — story 914).
  """
  @spec mark_pact_unhonored(map(), map(), term()) ::
          :ok | {:error, :not_a_player | :not_a_vassal | Ecto.Changeset.t()}
  def mark_pact_unhonored(world, user, lord_user_id),
    do: WorldServer.call(world, {:mark_pact_unhonored, user, lord_user_id})

  # -------------------------------------------------------------------
  # Rebellion (stories 915/919)
  # -------------------------------------------------------------------

  @doc """
  Read-only preview of what declaring independence against
  `lord_user_id` would do RIGHT NOW (story 915, criterion 7732): every
  one of `user`'s own occupied cities marked `will_rise?` per
  `BrokenOaths.Game.Rebellion.Resolution.city_rises?/4` (the SAME
  deterministic formula `declare_independence/3` itself commits with),
  plus the predicted temporary army size
  (`BrokenOaths.Game.Rebellion.Resolution.army_size/1`). Never live RNG,
  never a side effect — the same inputs (the lord's own Honor, this
  vassalage's own tribute rate, the world's own seed) produce the same
  verdicts calling this a hundred times in a row, and `declare_
  independence/3` recomputes the identical split from the identical
  inputs at commit time.
  """
  @spec independence_preview(map(), map(), term()) ::
          {:ok, %{cities: [%{city_id: term(), will_rise?: boolean()}], army_size: pos_integer()}}
          | {:error, :not_a_player | :not_a_vassal}
  def independence_preview(world, user, lord_user_id),
    do: WorldServer.call(world, {:independence_preview, user, lord_user_id})

  @doc """
  `user` (the vassal) declares independence from `lord_user_id` (story
  915): immediately severs the Vassalage (tribute stops the same turn
  boundary), resolves which of `user`'s own occupied cities rise back
  to them (`BrokenOaths.Game.Rebellion.Resolution.resolve_risings/4`) —
  each risen city de-occupies, restored to full health, and any of the
  former lord's own units still standing on it defect to `user` — spawns
  a temporary rebellion army (`BrokenOaths.Game.Rebellion.Resolution.
  army_size/1`) flagged `temporary: true`, and opens a state of war
  between the two (a narrow, rebellion-scoped PvP exception —
  `BrokenOaths.Game.Combat.hostile?/2` itself never changes). Creates a
  persisted, first-class `BrokenOaths.Game.Rebellion` row (`status:
  :active`) naming both parties and recording the split, the army size,
  and the start turn.
  """
  @spec declare_independence(map(), map(), term()) ::
          {:ok, BrokenOaths.Game.Rebellion.t()}
          | {:error, :not_a_player | :not_a_vassal | Ecto.Changeset.t()}
  def declare_independence(world, user, lord_user_id),
    do: WorldServer.call(world, {:declare_independence, user, lord_user_id})

  @doc """
  Story 917: whether `lord_user_id`'s own Lord unit is currently dead
  on the board — "the lord has fallen, seize the moment." Read fresh
  off live state every call (never cached), so a caller like `GameLive.
  Play`'s own `"declare_independence"` handler can decide, at the
  instant of the click, whether to skip story 915's two-step confirm
  (the lord is already gone — there is nothing further to warn about)
  or raise it as usual (the lord is still alive).
  """
  @spec lord_fallen?(map(), term()) :: boolean()
  def lord_fallen?(world, lord_user_id),
    do: WorldServer.call(world, {:lord_fallen?, lord_user_id})

  @doc """
  `user`'s own active-or-most-recent Rebellion as REBEL, or `nil` if
  they've never declared one: `%{id:, status:, rebel_user_id:,
  rebel_email:, former_lord_user_id:, former_lord_email:, started_turn:,
  army_size:, risen_city_ids:, loyal_city_ids:}`. Once a rebellion ends
  (`independence_won`/`crushed`/`peace`) this keeps reading that same
  settled row — a rebel only ever carries one ACTIVE rebellion at a
  time (`BrokenOaths.Game.Rebellion`'s own moduledoc).
  """
  @spec rebellion_status(map(), map()) :: map() | nil
  def rebellion_status(world, user), do: WorldServer.call(world, {:rebellion_status, user})

  @doc """
  Every Rebellion (active or ended) raised against `user` as the FORMER
  LORD — same shape as `rebellion_status/2`'s own single map, one per
  row, freshest first.
  """
  @spec rebellions_as_lord(map(), map()) :: [map()]
  def rebellions_as_lord(world, user), do: WorldServer.call(world, {:rebellions_as_lord, user})

  @doc """
  Either side of an active Rebellion between `user` and
  `counterparty_user_id` offers a negotiated peace (story 919):
  `outcome` is `"independence"` (the rebel is granted full freedom) or
  `"restored_vassal"` (the rebel swears fealty again) — nobody loses
  cities either way. `reparations_gold` (optional) moves from whoever
  accepts to whoever offers once `accept_peace/3` closes the deal. A
  fresh offer replaces any prior one still pending for this same
  Rebellion.
  """
  @spec offer_peace(map(), map(), term(), String.t(), non_neg_integer() | nil) ::
          :ok | {:error, :not_a_player | :no_active_rebellion}
  def offer_peace(world, user, counterparty_user_id, outcome, reparations_gold),
    do:
      WorldServer.call(
        world,
        {:offer_peace, user, counterparty_user_id, outcome, reparations_gold}
      )

  @doc """
  `user` accepts `counterparty_user_id`'s own pending peace offer —
  refused unless one is actually pending FROM the counterparty. Ends
  the Rebellion `:peace`, frees every one of the rebel's own cities
  (risen or loyal — "nobody loses cities in a peace"), disbands the
  temporary rebellion army, and moves any agreed reparations.
  """
  @spec accept_peace(map(), map(), term()) ::
          :ok | {:error, :not_a_player | :no_active_rebellion | :no_pending_offer}
  def accept_peace(world, user, counterparty_user_id),
    do: WorldServer.call(world, {:accept_peace, user, counterparty_user_id})

  @doc "`user` rejects `counterparty_user_id`'s own pending peace offer — the war simply continues, the Rebellion stays `:active`."
  @spec reject_peace(map(), map(), term()) :: :ok | {:error, :not_a_player | :no_active_rebellion}
  def reject_peace(world, user, counterparty_user_id),
    do: WorldServer.call(world, {:reject_peace, user, counterparty_user_id})

  # -------------------------------------------------------------------
  # Coordinated Rebellion — Pact of Broken Oaths (story 916)
  # -------------------------------------------------------------------

  @doc """
  `user`'s own membership in an active (`:forming`) Pact of Broken
  Oaths, or `nil` if they aren't currently a member of one: `%{id:,
  strike_turn:, own_status:, informer?:, members: [%{user_id:, email:,
  status:}]}`. Every OTHER member's own `status` is always `:invited`
  ("Outstanding") regardless of their real, secret commit answer —
  only the reader's own row (`own_status`) ever tells the truth,
  criterion 7738's own secrecy rule.
  """
  @spec pact_view(map(), map()) :: map() | nil
  def pact_view(world, user), do: WorldServer.call(world, {:pact_view, user})

  @doc """
  Every FELLOW vassal of `user`'s own lord — the eligible-to-invite
  roster a pact composer offers (criterion 7737's own "only fellow
  vassals of the same lord are eligible"). `[]` for a free player, or
  for a vassal with no fellow vassals under the same lord.
  """
  @spec pact_candidates(map(), map()) :: [%{user_id: term(), email: String.t()}]
  def pact_candidates(world, user), do: WorldServer.call(world, {:pact_candidates, user})

  @doc """
  `user` (a vassal) opens a Pact of Broken Oaths against their own
  lord, naming `strike_turn` (a positive integer of turn BOUNDARIES
  from right now, not an absolute world-turn number) and inviting
  `invitee_user_ids` into it — chat membership IS the conspiracy
  roster. An invitee who isn't a fellow vassal of the SAME lord is
  silently dropped, never rejecting the call outright. `user` becomes
  a member of their own pact too (`:invited`, same as any other
  invitee — they still `pact_commit/2` explicitly).
  """
  @spec open_pact_chat(map(), map(), pos_integer() | String.t(), [term()]) ::
          {:ok, BrokenOaths.Game.RebellionPact.t()}
          | {:error, :not_a_player | :not_a_vassal | :invalid_strike_turn | Ecto.Changeset.t()}
  def open_pact_chat(world, user, strike_turn, invitee_user_ids),
    do: WorldServer.call(world, {:open_pact_chat, user, strike_turn, invitee_user_ids})

  @doc "`user` secretly commits to strike with their own pact — reversible any time before the strike turn."
  @spec pact_commit(map(), map()) ::
          {:ok, BrokenOaths.Game.RebellionPactMember.t()}
          | {:error, :not_a_player | :not_a_pact_member}
  def pact_commit(world, user), do: WorldServer.call(world, {:pact_commit, user})

  @doc "`user` secretly declines to strike with their own pact — reversible any time before the strike turn."
  @spec pact_decline(map(), map()) ::
          {:ok, BrokenOaths.Game.RebellionPactMember.t()}
          | {:error, :not_a_player | :not_a_pact_member}
  def pact_decline(world, user), do: WorldServer.call(world, {:pact_decline, user})

  @doc """
  `user` secretly informs their own pact's targeted lord of the plot,
  for a personal reward — their identity stays hidden from every
  OTHER member (criterion 7741). Informing changes no odds; it only
  warns the lord, who can then pre-empt.
  """
  @spec pact_inform(map(), map()) ::
          {:ok, BrokenOaths.Game.RebellionPactMember.t()}
          | {:error, :not_a_player | :not_a_pact_member}
  def pact_inform(world, user), do: WorldServer.call(world, {:pact_inform, user})

  @doc """
  `user`'s own warning that a plot against them has been informed on,
  or `nil` while no member of any of their own pacts has informed:
  `%{strike_turn:}`. Never carries the informer's own identity, nor
  the rest of the roster.
  """
  @spec pact_informed_notice(map(), map()) :: %{strike_turn: pos_integer()} | nil
  def pact_informed_notice(world, user),
    do: WorldServer.call(world, {:pact_informed_notice, user})

  @doc """
  `user`'s own coarse conspiracy "heat" gauge (story 916, criterion
  7742): the mean `BrokenOaths.Game.Vassalage.oath_strain` across
  every one of their own ACTIVE vassals — a needle, never the pact
  chat's own content. `0` for a lord with no vassals.
  """
  @spec conspiracy_heat(map(), map()) :: BrokenOaths.Game.OathStrain.strain()
  def conspiracy_heat(world, user), do: WorldServer.call(world, {:conspiracy_heat, user})

  @doc "`user` (a lord) fully heals every one of their own cities — a pre-emptive defensive brace once warned of a plot."
  @spec brace_defenses(map(), map()) :: :ok | {:error, :not_a_player}
  def brace_defenses(world, user), do: WorldServer.call(world, {:brace_defenses, user})

  @doc "`user` (a lord) fully heals their own Lord unit — a pre-emptive reposition once warned of a plot."
  @spec reposition_lord(map(), map()) :: :ok | {:error, :not_a_player | :no_lord_unit}
  def reposition_lord(world, user), do: WorldServer.call(world, {:reposition_lord, user})

  @doc """
  `user` (a lord) eases EVERY one of their own vassals' Oath Strain by
  `BrokenOaths.Game.OathStrain.gift_ease/0` at once — a broad
  concession a warned lord can make without knowing which of their
  vassals is actually plotting (the roster stays secret even once
  informed).
  """
  @spec buy_off_conspirators(map(), map()) :: :ok | {:error, :not_a_player}
  def buy_off_conspirators(world, user),
    do: WorldServer.call(world, {:buy_off_conspirators, user})

  @doc """
  `user` (a lord) honors an overdue Protection Pact call for
  `vassal_user_id`, easing their Oath Strain by
  `BrokenOaths.Game.OathStrain.autonomy_ease/0` — a targeted
  concession, alongside the real `set_tribute_rate/4`, story 916's own
  "lowers tribute rates and honors an overdue protection call" lever.
  """
  @spec honor_protection_call(map(), map(), term()) ::
          :ok | {:error, :not_a_player | :not_a_vassal | Ecto.Changeset.t()}
  def honor_protection_call(world, user, vassal_user_id),
    do: WorldServer.call(world, {:honor_protection_call, user, vassal_user_id})

  # -------------------------------------------------------------------
  # Gold Bank (story 909)
  # -------------------------------------------------------------------

  @doc "`user`'s own bank status: `%{gold:, cap:}` (`BrokenOaths.Game.Bank.status/1`)."
  @spec bank(map(), map()) :: %{gold: non_neg_integer(), cap: pos_integer()}
  def bank(world, user), do: WorldServer.call(world, {:bank, user})

  @doc "Sweep `user`'s own bank into their treasury — a no-op against an already-empty bank, never refused."
  @spec collect_bank(map(), map()) :: :ok | {:error, :not_a_player | :feudal_disabled}
  def collect_bank(world, user), do: WorldServer.call(world, {:collect_bank, user})

  @doc "Raise `user`'s own bank cap for `BrokenOaths.Game.Bank.upgrade_cost/1`'s own gold price — refused outright when unaffordable."
  @spec upgrade_bank(map(), map()) ::
          :ok | {:error, :not_a_player | :insufficient_gold | :feudal_disabled}
  def upgrade_bank(world, user), do: WorldServer.call(world, {:upgrade_bank, user})

  # -------------------------------------------------------------------
  # Feudal Stewardship (story 910)
  # -------------------------------------------------------------------

  @doc "`user`'s own world-visible Honor reputation figure (`BrokenOaths.Game.Player.honor`)."
  @spec honor(map(), map()) :: integer()
  def honor(world, user), do: WorldServer.call(world, {:honor, user})

  @doc "`user`'s own full steward-action audit trail — every action taken on their behalf while offline, freshest first."
  @spec steward_log(map(), map()) :: [map()]
  def steward_log(world, user), do: WorldServer.call(world, {:steward_log, user})

  @doc """
  `steward_user` sweeps `owner_user_id`'s own offline Gold Bank
  entirely into the OWNER's treasury — pure stewardship, the steward's
  own treasury never moves. Refused unless `steward_user` is the
  owner's lord, a fellow vassal of the same lord, or an accepted ally
  (`BrokenOaths.Game.Stewardship.eligible?/1`), AND `owner_user_id` is
  genuinely offline (`BrokenOaths.Game.Presence.online?/2`).
  """
  @spec steward_collect_bank(map(), map(), term()) ::
          :ok | {:error, :not_a_player | :not_eligible | :owner_online | :feudal_disabled}
  def steward_collect_bank(world, steward_user, owner_user_id),
    do: WorldServer.call(world, {:steward_collect_bank, steward_user, owner_user_id})

  @doc """
  `steward_user` sets `owner_user_id`'s own production queue —
  constructive-only, same eligibility gate as `steward_collect_bank/3`.
  """
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
  def steward_queue_production(world, steward_user, owner_user_id, city_id, type),
    do:
      WorldServer.call(
        world,
        {:steward_queue_production, steward_user, owner_user_id, city_id, type}
      )

  @doc "Always refused — \"no cancel-griefing\" (story 910); no path anywhere ever reaches the real cancel command for a steward."
  @spec steward_cancel_production_item(map(), map(), term(), term(), term()) ::
          {:error, :not_constructive}
  def steward_cancel_production_item(world, steward_user, owner_user_id, city_id, item_id),
    do:
      WorldServer.call(
        world,
        {:steward_cancel_production_item, steward_user, owner_user_id, city_id, item_id}
      )

  @doc "Always refused — \"no disbanding\" (story 910); no disband mechanic exists anywhere in this codebase yet, for anyone."
  @spec steward_disband_unit(map(), map(), term(), term()) :: {:error, :not_constructive}
  def steward_disband_unit(world, steward_user, owner_user_id, unit_id),
    do: WorldServer.call(world, {:steward_disband_unit, steward_user, owner_user_id, unit_id})

  @doc "Always refused — the default-closed baseline `steward_defend/4`'s own emergency exception opens against."
  @spec steward_queue_move(map(), map(), term(), term(), term()) :: {:error, :not_allowed}
  def steward_queue_move(world, steward_user, owner_user_id, unit_id, to_tile \\ nil),
    do:
      WorldServer.call(
        world,
        {:steward_queue_move, steward_user, owner_user_id, unit_id, to_tile}
      )

  @doc "Always refused — a steward may never launch aggression, even mid-emergency (story 910)."
  @spec steward_attack(map(), map(), term(), term(), term()) :: {:error, :not_allowed}
  def steward_attack(world, steward_user, owner_user_id, unit_id, target_camp_id \\ nil),
    do:
      WorldServer.call(
        world,
        {:steward_attack, steward_user, owner_user_id, unit_id, target_camp_id}
      )

  @doc """
  EMERGENCY DEFENSE: `steward_user` orders `owner_user_id`'s own unit
  to a strictly adjacent, defensive `to_tile` — refused unless eligible
  AND `owner_user_id` is both offline and currently
  `BrokenOaths.Game.Stewardship.under_attack?/1`. An eligible steward
  who overreaches the destination during a genuine emergency window is
  provable sabotage: the move is still refused, but the attempt is
  logged and dings the STEWARD's own Honor.
  """
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
  def steward_defend(world, steward_user, owner_user_id, unit_id, to_tile),
    do: WorldServer.call(world, {:steward_defend, steward_user, owner_user_id, unit_id, to_tile})

  @doc """
  Every barbarian camp in `world`, unfiltered ground truth (never
  fog-filtered) — see `BrokenOathsSpex.Fixtures.list_camps/1`'s doc for
  why this sanctioned, no-UI-surface read exists (same status as
  `Worlds.Regions.partition/1`). Never call this to decide what a
  player sees; use `camps_visible_to/2` for that.
  """
  def list_camps(world), do: WorldServer.call(world, :list_camps)

  @doc """
  Barbarian camps `user` currently knows about — inside their own
  claimed region (immediate, no scouting required) or already
  explored. The fog-filtered surface `GameLive.Play` pushes as
  "game:camps" (story 892, criterion 7546 — a HARD constraint: a camp
  outside both sets never appears here).
  """
  def camps_visible_to(world, user), do: WorldServer.call(world, {:camps_visible_to, user})

  @doc """
  Enemy (another player's own) cities `user` currently knows about
  (QA issue 56ee521a): `[%{id:, name:, tile_id:, size:}]`, fog-filtered
  the same "own region OR explored" way `camps_visible_to/2` already
  is, minus any city `user` has personally captured (see
  `captured_cities_visible_to/2` for those). Empty unless
  `feudal_enabled?/0` — the surface `GameLive.Play` merges into its own
  `"game:cities"` push as `hostile: true` markers, powering both the
  right-click attack target and the adjacent-unit attack affordance.
  """
  @spec enemy_cities_visible_to(map(), map()) :: [map()]
  def enemy_cities_visible_to(world, user),
    do: WorldServer.call(world, {:enemy_cities_visible_to, user})

  @doc """
  Cities `user` has personally captured (QA issue ffa66192):
  `[%{id:, name:, tile_id:, fallen_garrison?:}]` — `fallen_garrison?`
  is whether a living defender of the ORIGINAL owner still awaits
  `resolve_garrison_fate/4`'s execute/release choice. Empty unless
  `feudal_enabled?/0`. Powers `GameLive.Play`'s own "Captured Cities"
  panel.
  """
  @spec captured_cities_visible_to(map(), map()) :: [map()]
  def captured_cities_visible_to(world, user),
    do: WorldServer.call(world, {:captured_cities_visible_to, user})

  @doc """
  Improvements on tiles the player knows (home region or explored) —
  same fog rule as `camps_visible_to/2`.
  """
  def improvements_visible_to(world, user),
    do: WorldServer.call(world, {:improvements_visible_to, user})

  @doc "A tile's completed improvement (`nil | :farm | :mine | :road`)."
  def tile_improvement(world, tile_id), do: WorldServer.call(world, {:tile_improvement, tile_id})

  @doc """
  Test-only: set a unit's HP directly. Story 881's healing rules need a
  damaged unit to observe, and combat (the epic's only real damage
  source) is future work — see `BrokenOathsSpex.Fixtures.set_unit_hp/3`.
  """
  @spec set_unit_hp_for_test(map(), term(), non_neg_integer()) :: :ok
  def set_unit_hp_for_test(world, unit_id, hp),
    do: WorldServer.call(world, {:set_unit_hp_for_test, unit_id, hp})

  @doc """
  Test-only: set `user`'s own gold treasury directly, standing in for a
  per-turn city gold YIELD this codebase has no real source for yet —
  see `BrokenOaths.Game.WorldServer`'s `:set_player_gold_for_test`
  handler for the same documented, narrow-exception status
  `set_unit_hp_for_test/3` already has.
  """
  @spec set_player_gold_for_test(map(), map(), integer()) :: :ok
  def set_player_gold_for_test(world, user, gold),
    do: WorldServer.call(world, {:set_player_gold_for_test, user.id, gold})

  @doc """
  Test-only: declares `user`'s per-turn gold INCOME, separate from
  their actual treasury balance (`set_player_gold_for_test/3`) — see
  `BrokenOaths.Game.WorldServer`'s `:set_player_gold_income_for_test`
  handler for the full rationale and its CURRENT, narrower status now
  that story 912 shipped a real per-turn city gold income mechanic:
  `apply_tribute/1`/`apply_bank/1` compute their own figure straight
  from `Yields.city_gold_income/2` every turn boundary and no longer
  read this seam at all — it's kept only for narrower, not-yet-
  reconciled test scenarios that still want a hand-declared income
  independent of any real city.
  """
  @spec set_player_gold_income_for_test(map(), map(), integer()) :: :ok
  def set_player_gold_income_for_test(world, user, income),
    do: WorldServer.call(world, {:set_player_gold_income_for_test, user.id, income})

  @doc """
  Test-only: set `user`'s own world-visible Honor reputation
  (`BrokenOaths.Game.Player.honor`) directly, same narrow, documented-
  bridge status as `set_player_gold_for_test/3` — a direct precondition
  setter for Honor, standing in for however many dishonorable acts it
  would otherwise take to depress it to a specific figure (`Siege.
  apply_execute_honor_penalty/1` only ever moves it by small, fixed
  steps). Never used to fabricate a RESULT this codebase computes itself
  (e.g. a rebellion's own `risen_city_ids` — `Rebellion.Resolution.
  city_rises?/4` still does that math for real, off whatever Honor this
  sets) — only the lord's own starting reputation.
  """
  @spec set_player_honor_for_test(map(), map(), integer()) :: :ok
  def set_player_honor_for_test(world, user, honor),
    do: WorldServer.call(world, {:set_player_honor_for_test, user.id, honor})

  @doc """
  Test-only: instantly restore `unit_id`'s movement to its own max,
  bypassing the turn boundary that would normally do it — see
  `BrokenOaths.Game.WorldServer`'s `:recharge_unit_for_test` handler for
  the same documented, narrow-exception status.
  """
  @spec recharge_unit_for_test(map(), term()) :: :ok
  def recharge_unit_for_test(world, unit_id),
    do: WorldServer.call(world, {:recharge_unit_for_test, unit_id})

  @doc """
  Test-only: place a real barbarian warrior directly on `tile_id` — see
  `BrokenOaths.Game.WorldServer`'s `:spawn_barbarian_for_test` handler
  for the same documented, narrow-exception status `set_unit_hp_for_test/3`
  already has. `camp_id` (nil by default — ownerless, no AI, story 891's
  original behavior) ties the warrior to a REAL camp so story 893's
  barbarian AI drives it for real from the next boundary. Returns the
  spawned unit's map (`id`, `tile_id`, `hp`, ...).
  """
  @spec spawn_barbarian_for_test(map(), term(), term()) :: map()
  def spawn_barbarian_for_test(world, tile_id, camp_id \\ nil),
    do: WorldServer.call(world, {:spawn_barbarian_for_test, tile_id, camp_id})

  @doc """
  Test-only: instantly relocate `unit_id` to `tile_id`, bypassing
  movement/pathing/turn boundaries — see `BrokenOaths.Game.WorldServer`'s
  `:relocate_unit_for_test` handler for the same documented,
  narrow-exception status. `:ok` or `{:error, :occupied}`.
  """
  @spec relocate_unit_for_test(map(), term(), term()) :: :ok | {:error, :occupied}
  def relocate_unit_for_test(world, unit_id, tile_id),
    do: WorldServer.call(world, {:relocate_unit_for_test, unit_id, tile_id})

  @doc """
  Test-only: instantly place a COMPLETE improvement of `kind` on
  `tile_id`, bypassing the real build — see `BrokenOaths.Game.WorldServer`'s
  `:complete_improvement_for_test` handler for the same documented,
  narrow-exception status. Returns the improvement's map (`tile_id`,
  `kind`, `progress`, `status`, `builder_unit_id`).
  """
  @spec complete_improvement_for_test(map(), term(), atom()) :: map()
  def complete_improvement_for_test(world, tile_id, kind),
    do: WorldServer.call(world, {:complete_improvement_for_test, tile_id, kind})

  @doc """
  Test-only: grant `city_id` Copper access (story 911) by appending a
  real Copper tile onto its own territory — see
  `BrokenOaths.Game.WorldServer`'s `:grant_copper_access_for_test`
  handler for the same documented, narrow-exception status
  `complete_improvement_for_test/3` already has. `:ok`, or
  `{:error, :no_copper_on_map}` if this world's own placement rolled
  no Copper anywhere.
  """
  @spec grant_copper_access_for_test(map(), term()) ::
          :ok | {:error, :no_copper_on_map | :not_found}
  def grant_copper_access_for_test(world, city_id),
    do: WorldServer.call(world, {:grant_copper_access_for_test, city_id})

  @doc """
  Test-only: move a barbarian directly onto `tile_id`, applying
  `Turn`'s own pillage-on-entry rule as a single isolated write rather
  than a full tick boundary — see `BrokenOaths.Game.WorldServer`'s
  `:move_barbarian_for_test` handler for the same documented,
  narrow-exception status. `:ok` or `{:error, :occupied}`.
  """
  @spec move_barbarian_for_test(map(), term(), term()) :: :ok | {:error, :occupied}
  def move_barbarian_for_test(world, barbarian_id, tile_id),
    do: WorldServer.call(world, {:move_barbarian_for_test, barbarian_id, tile_id})

  @doc """
  Test-only: destroy every camp except `keep_camp_id` and hard-delete
  every unit already tied to one of those other camps — see
  `BrokenOaths.Game.WorldServer`'s `:isolate_camp_for_test` handler for
  the same documented, narrow-exception status.
  """
  @spec isolate_camp_for_test(map(), term()) :: :ok
  def isolate_camp_for_test(world, keep_camp_id),
    do: WorldServer.call(world, {:isolate_camp_for_test, keep_camp_id})

  @doc """
  Test-only: hard-delete every warrior currently tied to `camp_id`,
  without touching the camp itself — see `BrokenOaths.Game.WorldServer`'s
  `:clear_camp_warriors_for_test` handler for the same documented,
  narrow-exception status.
  """
  @spec clear_camp_warriors_for_test(map(), term()) :: :ok
  def clear_camp_warriors_for_test(world, camp_id),
    do: WorldServer.call(world, {:clear_camp_warriors_for_test, camp_id})

  @doc """
  Test-only: resolve an attack FROM a barbarian (no owning player/session
  exists to drive this through `attack/4`) — see
  `BrokenOaths.Game.WorldServer`'s `:resolve_barbarian_attack_for_test`
  handler for the same documented, narrow-exception status
  `spawn_barbarian_for_test/2` has.
  """
  @spec resolve_barbarian_attack_for_test(map(), term(), term()) ::
          {:ok, %{damage_dealt: pos_integer(), damage_taken: pos_integer()}} | {:error, atom()}
  def resolve_barbarian_attack_for_test(world, attacker_unit_id, target_unit_id),
    do:
      WorldServer.call(
        world,
        {:resolve_barbarian_attack_for_test, attacker_unit_id, target_unit_id}
      )

  @doc """
  Dev-only QA control surface: place a REAL player-owned unit
  (`:warrior | :worker | :settler | :lord`) at `tile_id` with that
  type's starting stats (`BrokenOaths.Game.Production.unit_stats/1`) —
  see `BrokenOaths.Game.WorldServer`'s `:spawn_unit_for_test` handler
  for the same documented, narrow-exception status
  `spawn_barbarian_for_test/2` has. Returns the spawned unit's map
  (`id`, `tile_id`, `hp`, ...).
  """
  @spec spawn_unit_for_test(map(), term(), atom(), term()) :: map()
  def spawn_unit_for_test(world, player_id, type, tile_id),
    do: WorldServer.call(world, {:spawn_unit_for_test, player_id, type, tile_id})

  @doc """
  Dev-only QA control surface: hard-delete `unit_id` outright — needed
  to clear a camp's barbarian garrison without waiting for combat. See
  `BrokenOaths.Game.WorldServer`'s `:remove_unit_for_test` handler for
  the same documented, narrow-exception status.
  """
  @spec remove_unit_for_test(map(), term()) :: :ok
  def remove_unit_for_test(world, unit_id),
    do: WorldServer.call(world, {:remove_unit_for_test, unit_id})

  @doc """
  Dev-only QA control surface: set `camp_id`'s HP directly, bypassing
  combat — see `BrokenOaths.Game.WorldServer`'s `:set_camp_hp_for_test`
  handler for the same documented, narrow-exception status
  `set_unit_hp_for_test/3` has.
  """
  @spec set_camp_hp_for_test(map(), term(), non_neg_integer()) :: :ok
  def set_camp_hp_for_test(world, camp_id, hp),
    do: WorldServer.call(world, {:set_camp_hp_for_test, camp_id, hp})

  # -------------------------------------------------------------------
  # Research (story 902)
  # -------------------------------------------------------------------

  @doc """
  The Stone Age tech catalog: `%{tech => %{cost:, unlock:}}` — every
  tech's science cost and unlock description, unrelated to any single
  world (`BrokenOaths.Game.Research.catalog/0`). What a future
  TechPanel lists.
  """
  @spec tech_catalog() :: map()
  def tech_catalog, do: BrokenOaths.Game.Research.catalog()

  @doc """
  `user`'s research state in `world` (story 902, expanded to the
  eleven-tech Ancient-era tree per issue 133b4893): `%{completed_techs:,
  current_research:, banked_science:, progress:, science_per_turn:}`,
  or `nil` if `user` hasn't joined `world` — `progress` is
  `%{tech:, banked:, cost:}` for `current_research`, or `nil` with
  nothing selected (see `BrokenOaths.Game.Research.progress/1`).
  `science_per_turn` is `2 * population` summed over every one of
  `user`'s cities, right now (`BrokenOaths.Game.Research.science_per_turn/1`).
  `banked_science` and `completed_techs` are both keyed/valued by tech
  atom (`BrokenOaths.Game.Research.techs/0` names the full eleven-tech
  set).
  """
  @spec player_research(map(), map()) :: map() | nil
  def player_research(world, user), do: WorldServer.call(world, {:player_research, user})

  @doc """
  Select `tech` as `user`'s `current_research` in `world`, retaining
  whatever science was already banked toward it
  (`BrokenOaths.Game.Research.set_research/2`). Refuses an unknown tech,
  one already completed, or — since the tree grew prerequisite edges —
  one whose prerequisites aren't all completed yet
  (`{:error, :prereqs_not_met}`, see `BrokenOaths.Game.Research.prereqs_met?/2`).
  Persists immediately, like `rename_city/4` — no turn boundary required.
  """
  @spec set_research(map(), map(), atom()) ::
          :ok
          | {:error, :not_a_player | :invalid_tech | :already_completed | :prereqs_not_met}
  def set_research(world, user, tech), do: WorldServer.call(world, {:set_research, user, tech})

  # -------------------------------------------------------------------
  # Progress panel (story 904)
  # -------------------------------------------------------------------

  @doc """
  `user`'s lifetime combat totals in `world` (story 904): `%{
  barbarians_killed:, camps_destroyed:}`, or `nil` if `user` hasn't
  joined `world` — the two running counts a `BrokenOaths.Game.Player`
  row itself has to carry (unlike cities founded, which is just
  `length(player_cities/2)`; no city is ever deleted in this
  codebase). Bumped alongside the gold a barbarian bounty or a camp's
  destroy-reward already pays (`attack/4`, `attack_camp/4`, and
  `Turn`'s own barbarian-initiated exchanges), so this always stays in
  lockstep with `gold/2`.
  """
  @spec player_stats(map(), map()) ::
          %{barbarians_killed: non_neg_integer(), camps_destroyed: non_neg_integer()} | nil
  def player_stats(world, user), do: WorldServer.call(world, {:player_stats, user})
end
