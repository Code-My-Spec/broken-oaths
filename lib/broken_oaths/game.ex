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

  @doc "Run one deterministic turn tick — exactly what the 60s timer fires."
  def advance_turn(world), do: WorldServer.call(world, :advance_turn)

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
  both for an ordinary reassignment).
  """
  @spec assign_worked_tile(map(), map(), term(), term() | nil, term() | nil) ::
          :ok
          | {:error,
             :not_owner
             | :not_worked
             | :invalid_tile
             | :not_territory
             | :already_worked
             | :invalid_terrain}
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

  @doc "All of `user`'s cities in `world` (see `BrokenOaths.Game.WorldServer` for the shape)."
  def player_cities(world, user), do: WorldServer.call(world, {:player_cities, user})

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
end
