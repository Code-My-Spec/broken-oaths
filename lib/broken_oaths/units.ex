defmodule BrokenOaths.Units do
  @moduledoc """
  Unit reads and movement orders. Thin `GenServer.call` wrappers onto
  each world's `BrokenOaths.Simulation.WorldServer`; see `BrokenOaths.Game`'s
  own moduledoc for the process architecture every function here
  round-trips through.

  Extracted from `BrokenOaths.Game` (see
  `.code_my_spec/knowledge/genserver_decomposition.md`'s "Game API
  (973) → split by domain" target) — every function below is
  `defdelegate`d back onto `BrokenOaths.Game` unchanged, so no caller
  needs to know this module exists.
  """

  alias BrokenOaths.Simulation.WorldServer

  @doc "All of `user`'s units in `world`, each carrying its queued order (if any)."
  def player_units(world, user), do: WorldServer.call(world, {:player_units, user})

  @doc """
  Queue a move order for `unit_id` to `to_tile`, replacing any existing
  order. Validates ownership and a passable (`:land`), unoccupied
  destination, then computes a shortest path over land tiles.
  """
  @spec queue_move(map(), map(), term(), term()) :: {:ok, %{path: [term()]}} | {:error, atom()}
  def queue_move(world, user, unit_id, to_tile),
    do: WorldServer.call(world, {:queue_move, user, unit_id, to_tile})

  @doc """
  Queue a `:road_to` order (story 929) for `unit_id` — `user`'s own
  worker — to `destination`: walk the cheapest owned-territory route
  and lay road tile-by-tile as it arrives. Validates ownership, worker
  type, The Wheel research, and an in-territory destination, then
  computes the route the same weighted cheapest-path model `queue_move/4`
  uses. See `BrokenOaths.Units.Unit.build_road_to/4` for the full
  contract and `BrokenOaths.Simulation.Turn.RoadBuilder` for how it
  resolves, one segment per tick.
  """
  @spec build_road_to(map(), map(), term(), term()) ::
          {:ok, %{route: [term()]}} | {:error, atom()}
  def build_road_to(world, user, unit_id, destination),
    do: WorldServer.call(world, {:build_road_to, user, unit_id, destination})

  @doc """
  Fortify `unit_id` (story 920): grants the caller's own unit the
  defensive stance immediately, no dig-in turn. Legal for any
  `:defend`-capable type; idempotent. See `BrokenOaths.Units.Unit.
  fortify/3` for the full contract and `BrokenOaths.Combat.Resolver`'s
  own "Fortify" doc for the bonus the flag drives.
  """
  @spec fortify(map(), map(), term()) :: :ok | {:error, :not_owner | :not_fortifiable}
  def fortify(world, user, unit_id),
    do: WorldServer.call(world, {:fortify, user, unit_id})

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
  `BrokenOaths.Simulation.WorldServer`'s `:recharge_unit_for_test` handler for
  the same documented, narrow-exception status.
  """
  @spec recharge_unit_for_test(map(), term()) :: :ok
  def recharge_unit_for_test(world, unit_id),
    do: WorldServer.call(world, {:recharge_unit_for_test, unit_id})

  @doc """
  Test-only: instantly relocate `unit_id` to `tile_id`, bypassing
  movement/pathing/turn boundaries — see `BrokenOaths.Simulation.WorldServer`'s
  `:relocate_unit_for_test` handler for the same documented,
  narrow-exception status. `:ok` or `{:error, :occupied}`.
  """
  @spec relocate_unit_for_test(map(), term(), term()) :: :ok | {:error, :occupied}
  def relocate_unit_for_test(world, unit_id, tile_id),
    do: WorldServer.call(world, {:relocate_unit_for_test, unit_id, tile_id})

  @doc """
  Dev-only QA control surface: place a REAL player-owned unit
  (`:warrior | :worker | :settler | :lord`) at `tile_id` with that
  type's starting stats (`BrokenOaths.Cities.Production.unit_stats/1`) —
  see `BrokenOaths.Simulation.WorldServer`'s `:spawn_unit_for_test` handler
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
  `BrokenOaths.Simulation.WorldServer`'s `:remove_unit_for_test` handler for
  the same documented, narrow-exception status.
  """
  @spec remove_unit_for_test(map(), term()) :: :ok
  def remove_unit_for_test(world, unit_id),
    do: WorldServer.call(world, {:remove_unit_for_test, unit_id})
end
