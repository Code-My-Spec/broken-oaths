defmodule BrokenOaths.Cities do
  @moduledoc """
  City founding/renaming, worked tiles, the production queue, and
  improvements (worker digs). Thin `GenServer.call` wrappers onto each
  world's `BrokenOaths.Simulation.WorldServer`; see `BrokenOaths.Game`'s own
  moduledoc for the process architecture every function here
  round-trips through.

  Extracted from `BrokenOaths.Game` (see
  `.code_my_spec/knowledge/genserver_decomposition.md`'s "Game API
  (973) → split by domain" target) — every function below is
  `defdelegate`d back onto `BrokenOaths.Game` unchanged, so no caller
  needs to know this module exists.
  """

  alias BrokenOaths.Simulation.WorldServer

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
  `:building` gate `BrokenOathsWeb.GameLive.Play`'s own `worker_current_dig/2`
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

  @doc "All of `user`'s cities in `world` (see `BrokenOaths.Simulation.WorldServer` for the shape)."
  def player_cities(world, user), do: WorldServer.call(world, {:player_cities, user})

  @doc """
  Whether `user`'s player currently has Copper access (story 911
  rework, QA issue 3e6c124c "Copper availability wrong"): PLAYER-WIDE
  — true once they have at least one COMPLETED Mine improvement
  sitting on a Copper tile within territory ANY of their own cities
  controls, regardless of which city's panel happens to be open. See
  `BrokenOaths.Cities.Production.player_copper_access?/2` for the
  actual rule.
  """
  @spec copper_access?(map(), map()) :: boolean()
  def copper_access?(world, user), do: WorldServer.call(world, {:copper_access?, user})

  @doc """
  Whether the Pyramids/Hanging Gardens wonder has already been claimed
  (built or queued) ANYWHERE in `world`, by ANY player (story 933) —
  `%{pyramids: boolean(), hanging_gardens: boolean()}`, WORLD-level
  unlike `copper_access?/2` above (no `user` — a wonder's claimed
  status is the same fact for every player looking at it). See
  `BrokenOaths.Cities.Production.pyramids_claimed?/1`/
  `hanging_gardens_claimed?/1` for the actual rule.
  """
  @spec wonders_claimed(map()) :: %{pyramids: boolean(), hanging_gardens: boolean()}
  def wonders_claimed(world), do: WorldServer.call(world, {:wonders_claimed})

  @doc "A tile's completed improvement (`nil | :farm | :mine | :road`)."
  def tile_improvement(world, tile_id), do: WorldServer.call(world, {:tile_improvement, tile_id})

  @doc """
  Test-only: instantly place a COMPLETE improvement of `kind` on
  `tile_id`, bypassing the real build — see `BrokenOaths.Simulation.WorldServer`'s
  `:complete_improvement_for_test` handler for the same documented,
  narrow-exception status. Returns the improvement's map (`tile_id`,
  `kind`, `progress`, `status`, `builder_unit_id`).
  """
  @spec complete_improvement_for_test(map(), term(), atom()) :: map()
  def complete_improvement_for_test(world, tile_id, kind),
    do: WorldServer.call(world, {:complete_improvement_for_test, tile_id, kind})

  @doc """
  Test-only: grant `city_id`'s owning PLAYER Copper access (story 911,
  reworked for QA issue 3e6c124c "Copper availability wrong") by
  appending a real Copper tile onto `city_id`'s own territory AND
  instantly completing a Mine on it — see
  `BrokenOaths.Simulation.WorldServer`'s `:grant_copper_access_for_test`
  handler for the same documented, narrow-exception status
  `complete_improvement_for_test/3` already has. Copper access is now
  PLAYER-WIDE, so this grants it to every city that player owns, not
  only `city_id`. `:ok`, or `{:error, :no_copper_on_map}` if this
  world's own placement rolled no Copper anywhere.
  """
  @spec grant_copper_access_for_test(map(), term()) ::
          :ok | {:error, :no_copper_on_map | :not_found}
  def grant_copper_access_for_test(world, city_id),
    do: WorldServer.call(world, {:grant_copper_access_for_test, city_id})
end
