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
end
