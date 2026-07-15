defmodule BrokenOaths.Game.WorldServer do
  @moduledoc """
  One GenServer per world — the imperative shell around the pure
  `BrokenOaths.Game.Turn` core (see `.code_my_spec/architecture/decisions/world-process-architecture.md`).

  Holds the canonical tick-state (see `BrokenOaths.Game.Turn`'s moduledoc)
  in memory, addressed via `BrokenOaths.GameRegistry` and started lazily
  under `BrokenOaths.GameSupervisor`. All reads and writes for a given
  world funnel through its single process, so joins, moves, and turn
  boundaries are naturally serialized — the DB's unique indexes are only
  a backstop, not the primary race guard.

  ## Turn persistence

  A world's `turn` and `turn_started_at` are columns on `worlds` (see
  migration `20260714031000`), read at `init/1` and written back after
  every tick inside the same transaction as the rest of that tick's
  delta. `turn_started_at` is the wall-clock moment the current turn
  began; `turn_ends_at` (exposed via `BrokenOaths.Game`) is always
  `turn_started_at + 60s`.

  ## Ticking

  In every environment except test, `init/1` schedules a
  `Process.send_after(self(), :tick, 60_000)` self-loop, and if
  `turn_started_at` is more than 60s stale on boot (the world was
  dormant), missed ticks are run synchronously before the server
  accepts requests — wall-clock catch-up. Test env sets
  `config :broken_oaths, :game_auto_tick, false`, which disables both
  the self-loop and catch-up: `advance_turn/1` (called by
  `BrokenOathsSpex.Fixtures.advance_turn/1`) is the only tick source,
  exactly mirroring what the timer would have fired.
  """

  use GenServer

  import Ecto.Query

  alias BrokenOaths.Game.{Exploration, Order, Player, Spawner, Turn, Unit, Visibility}
  alias BrokenOaths.Repo
  alias BrokenOaths.Worlds
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.World

  @tick_seconds 60
  @tick_ms @tick_seconds * 1_000

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  @doc "PubSub topic a world's server broadcasts turn events on."
  def topic(world_id), do: "game:world:#{world_id}"

  def via_tuple(world_id), do: {:via, Registry, {BrokenOaths.GameRegistry, world_id}}

  @doc "Look up or lazily start the server for `world`."
  @spec ensure_started(World.t()) :: {:ok, pid()}
  def ensure_started(world) do
    case Registry.lookup(BrokenOaths.GameRegistry, world.id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        case DynamicSupervisor.start_child(BrokenOaths.GameSupervisor, {__MODULE__, world}) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          other -> other
        end
    end
  end

  def start_link(world) do
    GenServer.start_link(__MODULE__, world, name: via_tuple(world.id))
  end

  def child_spec(world) do
    %{id: {__MODULE__, world.id}, start: {__MODULE__, :start_link, [world]}, restart: :transient}
  end

  @doc "Ensure the server is running, then make a synchronous request against it."
  def call(world, message), do: call(world, message, _retries_left = 5)

  defp call(world, message, retries_left) do
    {:ok, pid} = ensure_started(world)
    GenServer.call(pid, message)
  catch
    # The server can die between lookup and call (a restart, an idle
    # shutdown) — and the Registry unregisters asynchronously after the
    # process exits, so an immediate retry can still resolve the dead
    # pid. Short backoff, then re-resolve.
    :exit, {reason, {GenServer, :call, _}}
    when retries_left > 0 and reason in [:noproc, :normal, :shutdown] ->
      Process.sleep(25)
      call(world, message, retries_left - 1)
  end

  @doc "Stop and lazily-restart the server, forcing a fresh rehydrate from the DB."
  def restart(world) do
    case Registry.lookup(BrokenOaths.GameRegistry, world.id) do
      [{pid, _}] -> GenServer.stop(pid, :normal)
      [] -> :ok
    end

    {:ok, _pid} = ensure_started(world)
    :ok
  end

  # -------------------------------------------------------------------
  # Callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(world) do
    world = Worlds.get_world!(world.id)

    state = load_state(world) |> catch_up()
    if auto_tick?(), do: schedule_tick()

    {:ok, state}
  end

  @impl true
  def handle_call({:join, user}, _from, state) do
    case do_join(state, user) do
      {:ok, player, new_state} ->
        if new_state != state, do: broadcast(new_state.world.id, [:units_changed])
        {:reply, {:ok, player}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:world_full?, _from, state) do
    {:reply, world_full?(state), state}
  end

  def handle_call({:claimed_region, user}, _from, state) do
    region = state |> find_player(user.id) |> region_of()
    {:reply, region, state}
  end

  def handle_call({:player_units, user}, _from, state) do
    {:reply, player_units(state, user), state}
  end

  def handle_call({:units_visible_to, user}, _from, state) do
    {:reply, visible_units(state, user), state}
  end

  def handle_call({:visibility, user}, _from, state) do
    {:reply, visibility(state, user), state}
  end

  def handle_call(:turn_number, _from, state), do: {:reply, state.turn, state}

  def handle_call(:turn_ends_at, _from, state) do
    {:reply, DateTime.add(state.turn_started_at, @tick_seconds, :second), state}
  end

  def handle_call({:gold, user}, _from, state) do
    gold = state |> find_player(user.id) |> gold_of()
    {:reply, gold, state}
  end

  def handle_call({:queue_move, user, unit_id, to_tile}, _from, state) do
    case do_queue_move(state, user, unit_id, to_tile) do
      {:ok, _path, queued} ->
        # Orders execute immediately with whatever movement the unit has
        # left; the turn boundary only recharges and continues.
        moved = Turn.move_now(queued, unit_id)

        case persist_tick(queued, moved) do
          :ok ->
            broadcast(moved.world.id, [:units_changed])

            remaining =
              case Map.get(moved.orders, unit_id) do
                %{path: rest} -> rest
                nil -> []
              end

            {:reply, {:ok, %{path: remaining}}, moved}

          :stale ->
            # A competing instance advanced the world under us — drop the
            # move, resync, and let the player retry against fresh state.
            {:reply, {:error, :stale}, resync(state)}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:advance_turn, _from, state) do
    {:reply, :ok, run_tick(state)}
  end

  def handle_call({:abandon, user}, _from, state) do
    new_state = do_abandon(state, user)
    broadcast(new_state.world.id, [:units_changed])
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:tick, state) do
    new_state = run_tick(state)
    schedule_tick()
    {:noreply, new_state}
  end

  # -------------------------------------------------------------------
  # Ticking
  # -------------------------------------------------------------------

  defp auto_tick?, do: Application.get_env(:broken_oaths, :game_auto_tick, true)

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_ms)

  defp catch_up(state) do
    if auto_tick?() do
      elapsed = DateTime.diff(DateTime.utc_now(), state.turn_started_at, :second)
      run_missed(state, div(elapsed, @tick_seconds))
    else
      state
    end
  end

  defp run_missed(state, missed) when missed <= 0, do: state
  defp run_missed(state, missed), do: run_missed(run_tick(state), missed - 1)

  defp run_tick(state) do
    {ticked, events} = Turn.tick(state)
    new_state = %{ticked | turn_started_at: DateTime.utc_now()}

    case persist_tick(state, new_state) do
      :ok ->
        broadcast(new_state.world.id, events)
        new_state

      :stale ->
        # Another WorldServer instance for this world (e.g. a second BEAM
        # node running a mix script — issue 07ee50d1) advanced the turn
        # first. Our write lost the optimistic race; discard in-memory
        # state and resync from the row instead of clobbering it.
        resync(state)
    end
  end

  defp resync(state) do
    load_state(Worlds.get_world!(state.world.id))
  end

  # -------------------------------------------------------------------
  # Join
  # -------------------------------------------------------------------

  defp do_join(state, user) do
    case find_player(state, user.id) do
      %{} = existing -> {:ok, existing, state}
      nil -> spawn_new_player(state, user)
    end
  end

  defp spawn_new_player(state, user) do
    with :ok <- check_membership_cap(user),
         {:ok, spawn} <- Spawner.spawn_player(state.world, taken_region_ids(state)) do
      {player, units, explored} = persist_join!(state, user, spawn)

      new_state = %{
        state
        | players: Map.put(state.players, player.id, player),
          units: Enum.reduce(units, state.units, &Map.put(&2, &1.id, &1)),
          explored: Map.put(state.explored, player.id, explored)
      }

      {:ok, player, new_state}
    end
  end

  defp check_membership_cap(user) do
    count = Repo.aggregate(from(p in Player, where: p.user_id == ^user.id), :count)
    if count >= 3, do: {:error, :membership_limit}, else: :ok
  end

  defp taken_region_ids(state), do: state.players |> Map.values() |> Enum.map(& &1.region_id)

  defp persist_join!(state, user, spawn) do
    {:ok, result} =
      Repo.transaction(fn ->
        {:ok, player} =
          %Player{}
          |> Player.changeset(%{
            world_id: state.world.id,
            user_id: user.id,
            region_id: spawn.region_id,
            gold: 50,
            joined_turn: state.turn
          })
          |> Repo.insert()

        {:ok, lord} = insert_unit(state.world.id, player.id, :lord, spawn.lord_tile, 20, 2)

        {:ok, settler} =
          insert_unit(state.world.id, player.id, :settler, spawn.settler_tile, 10, 2)

        explored = Visibility.visible_tiles(state.world, [lord, settler])

        {:ok, _exploration} =
          %Exploration{}
          |> Exploration.changeset(%{
            world_id: state.world.id,
            player_id: player.id,
            explored: MapSet.to_list(explored)
          })
          |> Repo.insert()

        {player_map(player), [unit_map(lord), unit_map(settler)], explored}
      end)

    result
  end

  defp insert_unit(world_id, player_id, type, tile_id, hp, movement) do
    %Unit{}
    |> Unit.changeset(%{
      world_id: world_id,
      player_id: player_id,
      type: type,
      tile_id: tile_id,
      hp: hp,
      max_hp: hp,
      movement: movement,
      max_movement: movement
    })
    |> Repo.insert()
  end

  defp world_full?(state) do
    match?({:error, :world_full}, Spawner.spawn_player(state.world, taken_region_ids(state)))
  end

  # -------------------------------------------------------------------
  # Abandon
  # -------------------------------------------------------------------

  defp do_abandon(state, user) do
    case find_player(state, user.id) do
      nil ->
        state

      player ->
        Player |> Repo.get!(player.id) |> Repo.delete!()

        unit_ids = for {id, u} <- state.units, u.player_id == player.id, do: id

        %{
          state
          | players: Map.delete(state.players, player.id),
            units: Map.drop(state.units, unit_ids),
            orders: Map.drop(state.orders, unit_ids),
            explored: Map.delete(state.explored, player.id)
        }
    end
  end

  # -------------------------------------------------------------------
  # Queue move
  # -------------------------------------------------------------------

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

      occupied_by_own?(state, to_tile, player.id) ->
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
  # tile is still occupied when they actually arrive.
  defp occupied_by_own?(state, tile_id, player_id) do
    state.units
    |> Map.values()
    |> Enum.any?(&(&1.tile_id == tile_id and &1.player_id == player_id))
  end

  defp persist_order!(unit_id, path) do
    attrs = %{unit_id: unit_id, kind: :move, path: path, status: :pending}

    case Repo.get_by(Order, unit_id: unit_id) do
      nil -> %Order{} |> Order.changeset(attrs) |> Repo.insert!()
      existing -> existing |> Order.changeset(attrs) |> Repo.update!()
    end
  end

  # Shortest path over :land tiles, excluding `from`, including `to`.
  # Plan around units that are on the board RIGHT NOW: occupied tiles
  # are impassable as intermediate steps (an equally short free path
  # must be preferred; a knowingly-blocked plan would interrupt on step
  # one). The DESTINATION may be occupied — approaching another player's
  # tile is legal; Turn's dynamic collision check is what stops the
  # mover adjacent to it.
  defp bfs_path(state, from, to) do
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
  # Reads
  # -------------------------------------------------------------------

  defp find_player(state, user_id) do
    state.players |> Map.values() |> Enum.find(&(&1.user_id == user_id))
  end

  defp region_of(nil), do: nil
  defp region_of(player), do: player.region_id

  defp gold_of(nil), do: 0
  defp gold_of(player), do: player.gold

  defp player_units(state, user) do
    case find_player(state, user.id) do
      nil ->
        []

      player ->
        for {_id, unit} <- state.units,
            unit.player_id == player.id,
            do: format_unit(state, unit, player.id)
    end
  end

  defp visible_units(state, user) do
    case find_player(state, user.id) do
      nil ->
        []

      player ->
        %{units: units} = Visibility.filter(state, player.id)
        for unit <- units, do: format_unit(state, unit, player.id)
    end
  end

  defp visibility(state, user) do
    case find_player(state, user.id) do
      nil -> %{visible: [], explored: []}
      player -> state |> Visibility.filter(player.id) |> Map.take([:visible, :explored])
    end
  end

  # Orders are private intent — only a unit's own player ever sees it.
  defp format_unit(state, unit, viewer_player_id) do
    order =
      if unit.player_id == viewer_player_id do
        format_order(Map.get(state.orders, unit.id))
      end

    %{
      id: unit.id,
      type: unit.type,
      tile_id: unit.tile_id,
      hp: unit.hp,
      max_hp: unit.max_hp,
      movement: unit.movement,
      max_movement: unit.max_movement,
      order: order
    }
  end

  defp format_order(nil), do: nil

  # The remaining path travels with the order (owner-only, see above) so
  # the board can render the route from the unit to its destination and
  # keep it current as movement consumes steps (story 875 rule).
  defp format_order(%{path: path, status: status}),
    do: %{target_tile: List.last(path), status: status, path: path}

  # -------------------------------------------------------------------
  # Persistence — tick delta
  # -------------------------------------------------------------------

  # Optimistically guarded: the world-turn write only lands if the row
  # still holds the turn this state was loaded from. A competing
  # WorldServer (second BEAM node) that advanced the row first makes
  # this return :stale with NOTHING persisted — the caller resyncs.
  defp persist_tick(old_state, new_state) do
    Repo.transaction(fn ->
      case persist_world_turn(old_state.turn, new_state) do
        :ok ->
          persist_unit_changes(old_state.units, new_state.units)
          persist_order_changes(old_state.orders, new_state.orders)
          persist_explored_changes(old_state.explored, new_state.explored)

        :stale ->
          Repo.rollback(:stale)
      end
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, :stale} -> :stale
    end
  end

  defp persist_unit_changes(old_units, new_units) do
    for {id, unit} <- new_units, Map.get(old_units, id) != unit do
      Repo.update_all(from(u in Unit, where: u.id == ^id),
        set: [tile_id: unit.tile_id, movement: unit.movement]
      )
    end
  end

  defp persist_order_changes(old_orders, new_orders) do
    case Map.keys(old_orders) -- Map.keys(new_orders) do
      [] -> :ok
      removed_ids -> Repo.delete_all(from(o in Order, where: o.unit_id in ^removed_ids))
    end

    for {id, order} <- new_orders, Map.get(old_orders, id) != order do
      Repo.update_all(from(o in Order, where: o.unit_id == ^id),
        set: [path: order.path, status: order.status]
      )
    end
  end

  defp persist_explored_changes(old_explored, new_explored) do
    for {player_id, tiles} <- new_explored, Map.get(old_explored, player_id) != tiles do
      Repo.update_all(from(e in Exploration, where: e.player_id == ^player_id),
        set: [explored: MapSet.to_list(tiles)]
      )
    end
  end

  defp persist_world_turn(expected_turn, state) do
    {count, _} =
      Repo.update_all(
        from(w in World, where: w.id == ^state.world.id and w.turn == ^expected_turn),
        set: [turn: state.turn, turn_started_at: state.turn_started_at]
      )

    if count == 1, do: :ok, else: :stale
  end

  defp broadcast(world_id, events) do
    Enum.each(events, &Phoenix.PubSub.broadcast(BrokenOaths.PubSub, topic(world_id), &1))
  end

  # -------------------------------------------------------------------
  # Rehydration
  # -------------------------------------------------------------------

  defp load_state(world) do
    %{
      world: world,
      turn: world.turn,
      turn_started_at: world.turn_started_at || persist_initial_turn_started_at(world),
      units: load_units(world.id),
      orders: load_orders(world.id),
      players: load_players(world.id),
      explored: load_explored(world.id)
    }
  end

  defp persist_initial_turn_started_at(world) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    Repo.update_all(from(w in World, where: w.id == ^world.id), set: [turn_started_at: now])
    now
  end

  defp load_players(world_id) do
    from(p in Player, where: p.world_id == ^world_id)
    |> Repo.all()
    |> Map.new(&{&1.id, player_map(&1)})
  end

  defp load_units(world_id) do
    from(u in Unit, where: u.world_id == ^world_id)
    |> Repo.all()
    |> Map.new(&{&1.id, unit_map(&1)})
  end

  defp load_orders(world_id) do
    from(o in Order,
      join: u in Unit,
      on: o.unit_id == u.id,
      where: u.world_id == ^world_id,
      select: o
    )
    |> Repo.all()
    |> Map.new(&{&1.unit_id, %{kind: &1.kind, path: &1.path, status: &1.status}})
  end

  defp load_explored(world_id) do
    from(e in Exploration, where: e.world_id == ^world_id)
    |> Repo.all()
    |> Map.new(&{&1.player_id, MapSet.new(&1.explored)})
  end

  defp player_map(%Player{} = p),
    do: %{id: p.id, user_id: p.user_id, region_id: p.region_id, gold: p.gold}

  defp unit_map(%Unit{} = u) do
    %{
      id: u.id,
      player_id: u.player_id,
      type: u.type,
      tile_id: u.tile_id,
      hp: u.hp,
      max_hp: u.max_hp,
      movement: u.movement,
      max_movement: u.max_movement
    }
  end
end
