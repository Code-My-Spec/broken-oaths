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

  alias BrokenOaths.Game.{
    BarbarianAI,
    Camp,
    Camps,
    City,
    Combat,
    Exploration,
    Improvement,
    Order,
    Player,
    Production,
    ProductionItem,
    Spawner,
    Turn,
    Unit,
    Visibility,
    Yields
  }

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

  def handle_call({:attack, user, unit_id, target_unit_id}, _from, state) do
    case do_attack(state, user, unit_id, target_unit_id) do
      {:ok, result, new_state} ->
        case persist_tick(state, new_state) do
          :ok ->
            broadcast(new_state.world.id, [:units_changed])
            {:reply, {:ok, result}, new_state}

          :stale ->
            {:reply, {:error, :stale}, resync(state)}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:attack_camp, user, unit_id, camp_id}, _from, state) do
    case do_attack_camp(state, user, unit_id, camp_id) do
      {:ok, result, new_state} ->
        case persist_tick(state, new_state) do
          :ok ->
            broadcast(new_state.world.id, [:units_changed])
            {:reply, {:ok, result}, new_state}

          :stale ->
            {:reply, {:error, :stale}, resync(state)}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:found_city, user, unit_id}, _from, state) do
    case do_found_city(state, user, unit_id) do
      {:ok, new_state} ->
        # A single event, not both — every `handle_info` clause below
        # (`:units_changed`/`:cities_changed`/`:improvements_changed`)
        # calls the same unconditional `refresh_board/1`, so founding
        # (which changes both units — the consumed settler — and
        # cities at once) only needs to say so once. Two identical
        # broadcasts would double-push every "game:*" event for the
        # same instant, and for a fog-gated one like "game:camps" (see
        # `GameLive.Play`), a spec's own single drain right after
        # founding leaves the second copy sitting in the mailbox as a
        # stale message ahead of every later turn's push — corrupting
        # exact per-turn assertions (story 892, criteria 7547-7550).
        broadcast(new_state.world.id, [:cities_changed])
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:queue_production, user, city_id, type}, _from, state) do
    case do_queue_production(state, user, city_id, type) do
      {:ok, new_state} ->
        broadcast(new_state.world.id, [:cities_changed])
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:reorder_production_item, user, city_id, item_id}, _from, state) do
    case do_reorder_production_item(state, user, city_id, item_id) do
      {:ok, new_state} ->
        broadcast(new_state.world.id, [:cities_changed])
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:cancel_production_item, user, city_id, item_id}, _from, state) do
    case do_cancel_production_item(state, user, city_id, item_id) do
      {:ok, new_state} ->
        broadcast(new_state.world.id, [:cities_changed])
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:assign_worked_tile, user, city_id, from_tile, to_tile}, _from, state) do
    case do_assign_worked_tile(state, user, city_id, from_tile, to_tile) do
      {:ok, new_state} ->
        broadcast(new_state.world.id, [:cities_changed])
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:rename_city, user, city_id, name}, _from, state) do
    case do_rename_city(state, user, city_id, name) do
      {:ok, new_state} ->
        broadcast(new_state.world.id, [:cities_changed])
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:start_improvement, user, unit_id, kind}, _from, state) do
    case do_start_improvement(state, user, unit_id, kind) do
      {:ok, new_state} ->
        broadcast(new_state.world.id, [:improvements_changed])
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:player_cities, user}, _from, state) do
    {:reply, player_cities(state, user), state}
  end

  # Ground truth, unfiltered — see `BrokenOathsSpex.Fixtures.list_camps/1`'s
  # doc for why this is a sanctioned exception to the fog-filtered board
  # surface (region math has the same status).
  def handle_call(:list_camps, _from, state) do
    {:reply, Enum.map(Map.values(state.camps), &format_camp(&1, state)), state}
  end

  def handle_call({:camps_visible_to, user}, _from, state) do
    {:reply, visible_camps(state, user), state}
  end

  def handle_call({:tile_improvement, tile_id}, _from, state) do
    {:reply, tile_improvement_at(state, tile_id), state}
  end

  def handle_call({:set_unit_hp_for_test, unit_id, hp}, _from, state) do
    Repo.update_all(from(u in Unit, where: u.id == ^unit_id), set: [hp: hp])
    unit = Map.fetch!(state.units, unit_id)
    new_state = %{state | units: Map.put(state.units, unit_id, %{unit | hp: hp})}
    {:reply, :ok, new_state}
  end

  # Test-only: instantly restore `unit_id`'s movement to its own max,
  # bypassing the turn boundary that would normally do it
  # (`reset_movement/1` in `Turn.tick/1`) — same narrow, documented-bridge
  # status as `:set_unit_hp_for_test` above. A scenario whose SUBJECT is
  # repeated attacks from the SAME unit (e.g. story 894 criterion 7559's
  # "every hit deals exactly its strength, no random roll") needs that
  # unit to recharge between swings, but a REAL turn boundary exposes it
  # to a full tick's worth of barbarian AI activity it has no relation
  # to — including outright death, which no post-hoc HP fixture can
  # undo. This sidesteps the tick (and its exposure) entirely for the
  # one narrow thing the scenario actually needs from it.
  def handle_call({:recharge_unit_for_test, unit_id}, _from, state) do
    unit = Map.fetch!(state.units, unit_id)
    Repo.update_all(from(u in Unit, where: u.id == ^unit_id), set: [movement: unit.max_movement])
    new_state = %{state | units: Map.put(state.units, unit_id, %{unit | movement: unit.max_movement})}
    {:reply, :ok, new_state}
  end

  # Test-only: place a real barbarian warrior directly on `tile_id` — no
  # cadence, no waiting for movement. `camp_id` (nil by default) is the
  # same narrow, documented-bridge extension `insert_unit/7` already
  # supports: passing a REAL camp's id makes this warrior indistinguishable
  # from one the camp spawned naturally, so `Turn`'s barbarian AI loop
  # (story 893) picks it up and drives it for real from the very next
  # boundary — the sanctioned way a spec gets a REAL, AI-controlled
  # warrior at an exact, controlled tile without marching anything
  # through a live hostile world to find it (same status as
  # `:set_unit_hp_for_test` above). Omitting `camp_id` keeps story 891's
  # original "ownerless target, no AI" behavior unchanged.
  def handle_call({:spawn_barbarian_for_test, tile_id, camp_id}, _from, state) do
    stats = Production.unit_stats(:barbarian_warrior)

    {:ok, unit} =
      insert_unit(state.world.id, nil, :barbarian_warrior, tile_id, stats.hp, stats.movement, camp_id)

    unit_data = unit_map(unit)
    new_state = %{state | units: Map.put(state.units, unit.id, unit_data)}
    {:reply, unit_data, new_state}
  end

  # Test-only: instantly relocate `unit_id` (any player's own unit) to
  # `tile_id`, bypassing movement points, pathing, and turn boundaries
  # entirely. A scenario that needs a unit standing at a specific,
  # possibly-distant spot (e.g. "adjacent to this real, naturally-placed
  # camp") no longer has to march it there over dozens of exposed turns
  # to get it there — same narrow, documented-bridge status as
  # `:spawn_barbarian_for_test` above. Refuses a tile already held by
  # another unit (one unit per hex is a hard rule everywhere else too).
  def handle_call({:relocate_unit_for_test, unit_id, tile_id}, _from, state) do
    if Enum.any?(state.units, fn {id, u} -> id != unit_id and u.tile_id == tile_id end) do
      {:reply, {:error, :occupied}, state}
    else
      unit = Map.fetch!(state.units, unit_id)
      Repo.update_all(from(u in Unit, where: u.id == ^unit_id), set: [tile_id: tile_id])
      new_state = %{state | units: Map.put(state.units, unit_id, %{unit | tile_id: tile_id})}
      {:reply, :ok, new_state}
    end
  end

  # Test-only: instantly place a COMPLETE improvement of `kind` on
  # `tile_id`, bypassing the real build (a worker standing still for
  # `Improvement.duration/1` real turns) entirely — same narrow,
  # documented-bridge status as `:spawn_barbarian_for_test` above. A
  # scenario whose SUBJECT is what happens to an ALREADY-FINISHED
  # improvement (pillage, story 893 criterion 7556) has no structural
  # need to expose a worker to a live, spawning camp for the several
  # real turns a build would otherwise take just to get there — that
  # exposure risks a genuine (if incidental) death to the very AI this
  # story is testing elsewhere, unrelated to what THIS criterion means
  # to exercise.
  def handle_call({:complete_improvement_for_test, tile_id, kind}, _from, state) do
    duration = Improvement.duration(kind)

    improvement =
      case Repo.get_by(Improvement, world_id: state.world.id, tile_id: tile_id) do
        nil ->
          {:ok, improvement} =
            %Improvement{}
            |> Improvement.changeset(%{
              world_id: state.world.id,
              tile_id: tile_id,
              kind: kind,
              progress: duration,
              status: :complete,
              builder_unit_id: nil
            })
            |> Repo.insert()

          improvement

        existing ->
          {:ok, improvement} =
            existing
            |> Improvement.changeset(%{
              kind: kind,
              progress: duration,
              status: :complete,
              builder_unit_id: nil
            })
            |> Repo.update()

          improvement
      end

    improvement_data = improvement_map(improvement)
    new_state = %{state | improvements: Map.put(state.improvements, tile_id, improvement_data)}
    {:reply, improvement_data, new_state}
  end

  # Test-only: move a barbarian warrior directly onto `tile_id`,
  # applying `Turn`'s own pillage-on-entry rule (`maybe_pillage/2`)
  # exactly as `apply_barbarian_decision({:move, tile}, ...)` would —
  # but as a single, isolated write rather than a full `Turn.tick/1`
  # boundary. Story 893 criterion 7556's own SUBJECT is what happens
  # WHEN a barbarian enters a tile with a completed improvement, not
  # the AI's path-finding/target-selection that gets it there (already
  # covered by criteria 7551/7554) — driving that arrival through a
  # real multi-camp tick made this scenario hostage to every OTHER
  # camp's own independent, same-tick spawn/movement cadence, which can
  # (and empirically did, often) land an unrelated warrior on the exact
  # bridge tile this scenario needs clear at the exact moment its own
  # decision is computed, no matter how thoroughly the tile is cleared
  # beforehand. Same narrow, documented-bridge status as
  # `:spawn_barbarian_for_test`/`:relocate_unit_for_test` above; refuses
  # a tile already held by another unit, the same "one unit per hex"
  # rule those two already enforce.
  def handle_call({:move_barbarian_for_test, barbarian_id, tile_id}, _from, state) do
    if Enum.any?(state.units, fn {id, u} -> id != barbarian_id and u.tile_id == tile_id end) do
      {:reply, {:error, :occupied}, state}
    else
      barbarian = Map.fetch!(state.units, barbarian_id)
      Repo.update_all(from(u in Unit, where: u.id == ^barbarian_id), set: [tile_id: tile_id])

      new_state = %{
        state
        | units: Map.put(state.units, barbarian_id, %{barbarian | tile_id: tile_id}),
          improvements: maybe_pillage_for_test(state.improvements, tile_id)
      }

      case Repo.get_by(Improvement, world_id: state.world.id, tile_id: tile_id) do
        nil -> :ok
        improvement -> persist_pillage_for_test(improvement, new_state.improvements[tile_id])
      end

      {:reply, :ok, new_state}
    end
  end

  # Test-only: destroy EVERY camp except `keep_camp_id` (`Camps.advance/2`
  # never spawns from a destroyed camp) and hard-delete every unit
  # already tied to one of those other camps — not just relocate them
  # elsewhere, since a merely-relocated warrior is still a live, roaming
  # actor that could wander back into range. A scenario testing ONE
  # camp's decision (target selection, pillage-on-entry) in a world
  # that always ships with several OTHER independently-roaming camps
  # (criterion 7543) needs to eliminate those other actors outright
  # rather than tolerate their incidental interference — same narrow,
  # documented-bridge status as `:spawn_barbarian_for_test` above, and
  # the same "sanctioned ground-truth write" class as that fixture's
  # own direct placement. The kept camp is untouched and keeps spawning/
  # fighting normally; nothing about `keep_camp_id`'s own warriors is
  # affected here.
  def handle_call({:isolate_camp_for_test, keep_camp_id}, _from, state) do
    destroyed_at = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    other_camp_ids = state.camps |> Map.keys() |> Enum.reject(&(&1 == keep_camp_id))

    new_camps =
      Map.new(state.camps, fn {id, camp} ->
        if id in other_camp_ids, do: {id, %{camp | destroyed_at: destroyed_at}}, else: {id, camp}
      end)

    Repo.update_all(from(c in Camp, where: c.id in ^other_camp_ids), set: [destroyed_at: destroyed_at])

    removed_unit_ids =
      for {id, u} <- state.units, Map.get(u, :camp_id) in other_camp_ids, do: id

    Repo.delete_all(from(u in Unit, where: u.id in ^removed_unit_ids))

    new_state = %{state | camps: new_camps, units: Map.drop(state.units, removed_unit_ids)}
    {:reply, :ok, new_state}
  end

  # Test-only: hard-delete every warrior currently tied to `camp_id`,
  # WITHOUT touching the camp itself (still alive, still spawning
  # normally afterward) — the complement to `:isolate_camp_for_test`
  # above. That fixture only ever eliminates OTHER camps; it
  # deliberately leaves the kept camp's own warriors alone, since the
  # whole point is to keep exercising that camp's real spawn/AI loop.
  # But letting a real scenario's long setup wait (city growth,
  # production banking — no shortcut exists for those) run for dozens
  # of turns means that SAME camp's own natural cadence can accumulate
  # sibling warriors before the scenario ever deliberately places its
  # OWN tracked one — a sibling that's still a live, path-blocking actor
  # this criterion never asked for. Calling this immediately before
  # `:spawn_barbarian_for_test` places the scenario's actual warrior
  # guarantees it's the ONLY warrior anywhere in the world at that
  # decision boundary — same narrow, documented-bridge status as
  # `:isolate_camp_for_test`.
  def handle_call({:clear_camp_warriors_for_test, camp_id}, _from, state) do
    removed_unit_ids = for {id, u} <- state.units, Map.get(u, :camp_id) == camp_id, do: id
    Repo.delete_all(from(u in Unit, where: u.id in ^removed_unit_ids))
    new_state = %{state | units: Map.drop(state.units, removed_unit_ids)}
    {:reply, :ok, new_state}
  end

  # Test-only: resolve an attack FROM a barbarian, bypassing the
  # player-ownership check `do_attack/4` requires (a barbarian has no
  # owning player/session to drive it through the ordinary "attack"
  # event). Story 893 (barbarian AI) is what will drive this for real;
  # until then this reuses the exact same validate+resolve pipeline
  # `do_attack/4` uses, same narrow, documented-bridge status as
  # `:spawn_barbarian_for_test` above.
  def handle_call({:resolve_barbarian_attack_for_test, attacker_id, target_id}, _from, state) do
    attacker = Map.fetch!(state.units, attacker_id)
    defender = Map.fetch!(state.units, target_id)
    adjacent_tile_ids = Regions.adjacent_tiles(state.world, attacker.tile_id)

    case Combat.validate_attack(attacker, defender, adjacent_tile_ids) do
      :ok ->
        {result, new_state} = resolve_attack(state, attacker, defender)

        case persist_tick(state, new_state) do
          :ok ->
            broadcast(new_state.world.id, [:units_changed])
            {:reply, {:ok, result}, new_state}

          :stale ->
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
    {events, ticked} = materialize_spawns(events, ticked)
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

  # `Turn.tick/1` can never allocate a real, persisted unit id — a
  # completed production item that found a landing tile comes back as
  # a `{:unit_spawned, spawn_event}` intent instead. This is the one
  # place that turns those intents into real `Unit` rows, folding each
  # into `state.units` before `persist_tick` runs so the rest of the
  # delta (and any later event in this same batch) sees it.
  defp materialize_spawns(events, state) do
    Enum.map_reduce(events, state, fn
      {:unit_spawned, spawn_event}, acc_state ->
        unit = insert_spawned_unit!(acc_state.world.id, spawn_event)

        {{:unit_spawned, Map.put(spawn_event, :unit_id, unit.id)},
         %{acc_state | units: Map.put(acc_state.units, unit.id, unit)}}

      other_event, acc_state ->
        {other_event, acc_state}
    end)
  end

  defp insert_spawned_unit!(world_id, %{player_id: player_id, type: type, tile_id: tile_id} = event) do
    stats = Production.unit_stats(type)
    camp_id = Map.get(event, :camp_id)
    {:ok, unit} = insert_unit(world_id, player_id, type, tile_id, stats.hp, stats.movement, camp_id)
    unit_map(unit)
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

        lord_stats = Production.unit_stats(:lord)

        {:ok, lord} =
          insert_unit(
            state.world.id,
            player.id,
            :lord,
            spawn.lord_tile,
            lord_stats.hp,
            lord_stats.movement
          )

        settler_stats = Production.unit_stats(:settler)

        {:ok, settler} =
          insert_unit(
            state.world.id,
            player.id,
            :settler,
            spawn.settler_tile,
            settler_stats.hp,
            settler_stats.movement
          )

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

  defp insert_unit(world_id, player_id, type, tile_id, hp, movement, camp_id \\ nil) do
    %Unit{}
    |> Unit.changeset(%{
      world_id: world_id,
      player_id: player_id,
      camp_id: camp_id,
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
        # Cascades at the DB level (game_units, game_cities, and
        # game_production_items all FK to game_players/game_cities with
        # on_delete: :delete_all) — mirror it in memory so a re-founded
        # city on the same tile isn't rejected by a stale in-memory
        # unique-tile check. Improvements aren't player-owned
        # (builder_unit_id nilifies instead) and outlive their builder.
        Player |> Repo.get!(player.id) |> Repo.delete!()

        unit_ids = for {id, u} <- state.units, u.player_id == player.id, do: id
        city_ids = for {id, c} <- state.cities, c.player_id == player.id, do: id

        %{
          state
          | players: Map.delete(state.players, player.id),
            units: Map.drop(state.units, unit_ids),
            orders: Map.drop(state.orders, unit_ids),
            explored: Map.delete(state.explored, player.id),
            cities: Map.drop(state.cities, city_ids)
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
  # Attack
  # -------------------------------------------------------------------

  # Resolves like a move order: immediately, against whatever movement
  # the attacker has left right now (see `Combat`'s moduledoc for the
  # damage math and target-legality rules this delegates to).
  defp do_attack(state, user, unit_id, target_unit_id) do
    player = find_player(state, user.id)
    attacker = Map.get(state.units, unit_id)
    defender = Map.get(state.units, target_unit_id)

    cond do
      is_nil(player) or is_nil(attacker) or attacker.player_id != player.id ->
        {:error, :not_owner}

      is_nil(defender) ->
        {:error, :invalid_target}

      true ->
        adjacent_tile_ids = Regions.adjacent_tiles(state.world, attacker.tile_id)

        case Combat.validate_attack(attacker, defender, adjacent_tile_ids) do
          :ok ->
            {result, new_state} = resolve_attack(state, attacker, defender)
            {:ok, result, new_state}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp resolve_attack(state, attacker, defender) do
    seed = {state.world.seed, state.turn, attacker.id, defender.id}

    %{damage_to_defender: dealt, damage_to_attacker: taken} =
      Combat.resolve(attacker, defender,
        seed: seed,
        attacker_aura?: lord_adjacent?(state, attacker),
        defender_aura?: lord_adjacent?(state, defender)
      )

    new_attacker = %{attacker | hp: max(attacker.hp - taken, 0), movement: 0}
    new_defender = %{defender | hp: max(defender.hp - dealt, 0)}

    units =
      state.units
      |> apply_combat_unit(attacker.id, new_attacker)
      |> apply_combat_unit(defender.id, new_defender)

    state =
      %{state | units: units}
      |> schedule_heir_if_lord_fell(attacker, new_attacker)
      |> schedule_heir_if_lord_fell(defender, new_defender)
      |> pay_bounty_if_barbarian_fell(new_attacker, defender)
      |> pay_bounty_if_barbarian_fell(new_defender, attacker)

    {%{damage_dealt: dealt, damage_taken: taken}, state}
  end

  defp apply_combat_unit(units, id, %{hp: 0}), do: Map.delete(units, id)
  defp apply_combat_unit(units, id, unit), do: Map.put(units, id, unit)

  # Story 893, criterion 7557: whichever side of a resolved exchange was
  # a barbarian (`player_id: nil`) and reached 0 HP pays the OTHER
  # side's owner the bounty — covers both a player's own "attack" (the
  # barbarian is always the defender there) and a barbarian-initiated
  # exchange resolved by `Turn`'s own AI loop through this same
  # function's sibling in that module (the barbarian is the attacker
  # there, killed by the defender's counter-blow).
  defp pay_bounty_if_barbarian_fell(state, %{player_id: nil, hp: 0}, %{player_id: payee_id})
       when not is_nil(payee_id) do
    update_in(state.players[payee_id].gold, &(&1 + BarbarianAI.bounty_gold()))
  end

  defp pay_bounty_if_barbarian_fell(state, _fallen, _other), do: state

  # -------------------------------------------------------------------
  # Camp assault (story 894)
  # -------------------------------------------------------------------

  # Resolves immediately, like `do_attack/4` — flat damage, no counter
  # (see `Combat.camp_damage/2`). An already-destroyed (or nonexistent)
  # camp is refused the same way an already-dead unit target is.
  defp do_attack_camp(state, user, unit_id, camp_id) do
    player = find_player(state, user.id)
    attacker = Map.get(state.units, unit_id)
    camp = Map.get(state.camps, camp_id)

    cond do
      is_nil(player) or is_nil(attacker) or attacker.player_id != player.id ->
        {:error, :not_owner}

      is_nil(camp) or not is_nil(camp.destroyed_at) ->
        {:error, :invalid_target}

      true ->
        adjacent_tile_ids = Regions.adjacent_tiles(state.world, attacker.tile_id)

        case Combat.validate_camp_attack(attacker, camp, adjacent_tile_ids) do
          :ok ->
            {result, new_state} = resolve_camp_attack(state, attacker, camp)
            {:ok, result, new_state}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp resolve_camp_attack(state, attacker, camp) do
    dealt = Combat.camp_damage(attacker, lord_adjacent?(state, attacker))
    new_camp = %{camp | hp: max(camp.hp - dealt, 0)}
    new_attacker = %{attacker | movement: 0}

    state =
      %{state | units: Map.put(state.units, attacker.id, new_attacker)}
      |> apply_camp_damage(new_camp, attacker.player_id)

    {%{damage_dealt: dealt, damage_taken: 0}, state}
  end

  # Story 894, criterion 7560: 0 HP destroys the camp — `destroyed_at`
  # stops `Camps.advance/2` from ever spawning again (already handled,
  # story 892) and drops it from `visible_camps/2`'s fog-filtered
  # surface; the destroying player's owner is paid `Camps.destroy_reward/0`.
  # Orphaned warriors are untouched — they're separate `Unit` rows, not
  # nested under the camp in `state.units` (criterion 7561).
  defp apply_camp_damage(state, %{hp: 0} = camp, payee_id) do
    destroyed = %{camp | destroyed_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)}
    state = %{state | camps: Map.put(state.camps, camp.id, destroyed)}
    update_in(state.players[payee_id].gold, &(&1 + Camps.destroy_reward()))
  end

  defp apply_camp_damage(state, camp, _payee_id) do
    %{state | camps: Map.put(state.camps, camp.id, camp)}
  end

  # A living unit of the SAME player standing next door — dead units
  # are already gone from `state.units`, so presence alone means
  # living, and a lord's own tile is never its own neighbor, so this
  # never accidentally self-buffs the lord.
  defp lord_adjacent?(state, unit) do
    adjacent_tile_ids = Regions.adjacent_tiles(state.world, unit.tile_id)

    state.units
    |> Map.values()
    |> Enum.any?(
      &(&1.type == :lord and &1.player_id == unit.player_id and &1.tile_id in adjacent_tile_ids)
    )
  end

  # Schedules the heir 10 turn boundaries out (story 896, criterion
  # 7573) — kept only in memory (`state.pending_heirs`), never
  # persisted to the DB. Known, narrow limitation: a `WorldServer`
  # restart mid-wait drops the pending heir; nothing in the current
  # schema tracks scheduled future spawns the way `Order`/`Improvement`
  # do, and no spec exercises a restart during the wait. `Turn.tick/1`
  # resolves this map every boundary (see its "Heir succession" phase).
  defp schedule_heir_if_lord_fell(state, %{type: :lord, player_id: player_id}, %{hp: 0}) do
    pending_heirs =
      state
      |> Map.get(:pending_heirs, %{})
      |> Map.put(player_id, state.turn + 10)

    Map.put(state, :pending_heirs, pending_heirs)
  end

  defp schedule_heir_if_lord_fell(state, _original, _new), do: state

  # -------------------------------------------------------------------
  # Found city
  # -------------------------------------------------------------------

  defp do_found_city(state, user, unit_id) do
    player = find_player(state, user.id)
    unit = Map.get(state.units, unit_id)

    cond do
      is_nil(player) or is_nil(unit) or unit.player_id != player.id ->
        {:error, :not_owner}

      unit.type != :settler ->
        {:error, :not_settler}

      true ->
        case Production.validate_founding(state.world, Map.values(state.cities), unit.tile_id) do
          {:error, reason} ->
            {:error, reason}

          :ok ->
            first_founding? = not Enum.any?(state.cities, fn {_id, c} -> c.player_id == player.id end)
            {:ok, city} = persist_found_city!(state, player, unit)

            new_state = %{
              state
              | cities: Map.put(state.cities, city.id, city),
                units: Map.delete(state.units, unit_id),
                orders: Map.delete(state.orders, unit_id)
            }

            new_state =
              if first_founding?,
                do: spawn_wilderness_camps(new_state, player, unit.tile_id),
                else: new_state

            {:ok, new_state}
        end
    end
  end

  # Story 892: a player's FIRST city (never a second, third, ...) seeds
  # the wilderness around it — see `Camps.place_wilderness/6`'s doc for
  # the near/far split. Placement is pure and deterministic; this is
  # just the imperative shell turning its tile picks into real,
  # immediately persisted `Camp` rows (same "persist right away, tick
  # only diffs later" pattern `persist_found_city!/3` already uses for
  # the city itself).
  defp spawn_wilderness_camps(state, player, city_tile_id) do
    home_region = player_region_tiles(state.world, player.region_id)
    explored = Map.get(state.explored, player.id, MapSet.new())
    occupied = state.units |> Map.values() |> Enum.map(& &1.tile_id) |> MapSet.new()
    seed = {state.world.seed, city_tile_id}

    tiles = Camps.place_wilderness(state.world, city_tile_id, home_region, explored, occupied, seed)
    camps = Enum.map(tiles, &persist_camp!(state.world.id, &1))

    %{state | camps: Enum.reduce(camps, Map.get(state, :camps, %{}), &Map.put(&2, &1.id, &1))}
  end

  defp persist_camp!(world_id, tile_id) do
    {:ok, camp} =
      %Camp{}
      |> Camp.changeset(%{world_id: world_id, tile_id: tile_id, hp: Camp.max_hp(), spawn_counter: 0})
      |> Repo.insert()

    camp_map(camp)
  end

  # The settler is consumed and a working city stands in its place
  # immediately (story 878, criterion 7463) — both writes happen in one
  # transaction. The founding pop's worked-tile pick uses the exact
  # same deterministic scoring growth uses later, computed in memory
  # before insert since a size-1 city needs it from turn zero.
  defp persist_found_city!(state, player, unit) do
    territory =
      state.world
      |> Production.founding_territory(unit.tile_id)
      |> MapSet.to_list()
      |> Enum.sort()

    worked =
      case Yields.pick_worked_tile(
             %{tile_id: unit.tile_id, territory: territory, worked_tiles: []},
             state.world
           ) do
        nil -> []
        tile -> [tile]
      end

    Repo.transaction(fn ->
      {:ok, city} =
        %City{}
        |> City.changeset(%{
          world_id: state.world.id,
          player_id: player.id,
          tile_id: unit.tile_id,
          name: default_city_name(state, player),
          size: 1,
          food: 0,
          territory: territory,
          worked_tiles: worked
        })
        |> Repo.insert()

      Unit |> Repo.get!(unit.id) |> Repo.delete!()

      city_map(%{city | production_items: []})
    end)
  end

  defp default_city_name(state, player) do
    count = state.cities |> Map.values() |> Enum.count(&(&1.player_id == player.id))
    "City #{count + 1}"
  end

  # -------------------------------------------------------------------
  # Production queue
  # -------------------------------------------------------------------

  defp do_queue_production(state, user, city_id, type) do
    with {:ok, city} <- owned_city(state, user, city_id),
         {:ok, type} <- parse_item_type(type),
         :ok <- Production.can_queue?(city, type) do
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
      {:ok, %{state | cities: Map.put(state.cities, city_id, new_city)}}
    end
  end

  # Move a queued item one slot toward the head by swapping positions
  # with its predecessor. The head (current) item can't move; item
  # identity — and its banked progress — stays put, only order changes.
  defp do_reorder_production_item(state, user, city_id, item_id) do
    with {:ok, city} <- owned_city(state, user, city_id) do
      case Enum.find_index(city.queue, &(&1.id == item_id)) do
        nil ->
          {:error, :not_found}

        0 ->
          {:error, :invalid_item}

        idx ->
          above = Enum.at(city.queue, idx - 1)
          item = Enum.at(city.queue, idx)

          Repo.update_all(from(p in ProductionItem, where: p.id == ^item.id),
            set: [position: above.position]
          )

          Repo.update_all(from(p in ProductionItem, where: p.id == ^above.id),
            set: [position: item.position]
          )

          swapped = %{item | position: above.position}
          swapped_above = %{above | position: item.position}

          new_queue =
            city.queue
            |> List.replace_at(idx - 1, swapped)
            |> List.replace_at(idx, swapped_above)

          new_city = %{city | queue: new_queue}
          {:ok, %{state | cities: Map.put(state.cities, city_id, new_city)}}
      end
    end
  end

  defp do_cancel_production_item(state, user, city_id, item_id) do
    with {:ok, city} <- owned_city(state, user, city_id) do
      if Enum.any?(city.queue, &(&1.id == item_id)) do
        Repo.delete_all(from(p in ProductionItem, where: p.id == ^item_id))
        new_city = %{city | queue: Enum.reject(city.queue, &(&1.id == item_id))}
        {:ok, %{state | cities: Map.put(state.cities, city_id, new_city)}}
      else
        {:error, :not_found}
      end
    end
  end

  defp owned_city(state, user, city_id) do
    player = find_player(state, user.id)
    city = Map.get(state.cities, city_id)

    if is_nil(player) or is_nil(city) or city.player_id != player.id do
      {:error, :not_owner}
    else
      {:ok, city}
    end
  end

  defp parse_item_type(type) when type in [:settler, :worker, :warrior], do: {:ok, type}
  defp parse_item_type("settler"), do: {:ok, :settler}
  defp parse_item_type("worker"), do: {:ok, :worker}
  defp parse_item_type("warrior"), do: {:ok, :warrior}
  defp parse_item_type(_other), do: {:error, :invalid_item}

  # -------------------------------------------------------------------
  # Worked tiles
  # -------------------------------------------------------------------

  # `from_tile`/`to_tile` are each optionally `nil`: unassigning alone
  # drops a citizen to idle, assigning alone fills an open slot, and
  # both together is the panel's ordinary reassignment.
  defp do_assign_worked_tile(state, user, city_id, from_tile, to_tile) do
    with {:ok, city} <- owned_city(state, user, city_id),
         :ok <- validate_unassign(city, from_tile),
         :ok <- validate_assign(state.world, city, to_tile) do
      worked = city.worked_tiles |> maybe_remove(from_tile) |> maybe_add(to_tile)
      persist_worked_tiles!(city_id, worked)
      {:ok, %{state | cities: Map.put(state.cities, city_id, %{city | worked_tiles: worked})}}
    end
  end

  defp maybe_remove(tiles, nil), do: tiles
  defp maybe_remove(tiles, tile), do: List.delete(tiles, tile)

  defp maybe_add(tiles, nil), do: tiles
  defp maybe_add(tiles, tile), do: tiles ++ [tile]

  defp validate_unassign(_city, nil), do: :ok

  defp validate_unassign(city, tile) do
    if tile in city.worked_tiles, do: :ok, else: {:error, :not_worked}
  end

  defp validate_assign(_world, _city, nil), do: :ok

  defp validate_assign(world, city, tile) do
    cond do
      tile == city.tile_id -> {:error, :invalid_tile}
      tile not in city.territory -> {:error, :not_territory}
      tile in city.worked_tiles -> {:error, :already_worked}
      not Yields.workable?(Regions.terrain(world, tile)) -> {:error, :invalid_terrain}
      true -> :ok
    end
  end

  defp persist_worked_tiles!(city_id, worked_tiles) do
    Repo.update_all(from(c in City, where: c.id == ^city_id), set: [worked_tiles: worked_tiles])
  end

  # -------------------------------------------------------------------
  # Rename city
  # -------------------------------------------------------------------

  defp do_rename_city(state, user, city_id, name) do
    with {:ok, city} <- owned_city(state, user, city_id),
         :ok <- validate_name(name) do
      trimmed = String.trim(name)
      Repo.update_all(from(c in City, where: c.id == ^city_id), set: [name: trimmed])
      {:ok, %{state | cities: Map.put(state.cities, city_id, %{city | name: trimmed})}}
    end
  end

  defp validate_name(name) when is_binary(name) do
    trimmed = String.trim(name)
    if trimmed != "" and String.length(trimmed) <= 100, do: :ok, else: {:error, :invalid_name}
  end

  defp validate_name(_other), do: {:error, :invalid_name}

  # -------------------------------------------------------------------
  # Improvements
  # -------------------------------------------------------------------

  defp do_start_improvement(state, user, unit_id, kind) do
    with {:ok, unit} <- owned_worker(state, user, unit_id),
         {:ok, kind} <- parse_kind(kind),
         :ok <- validate_improvement_terrain(state.world, unit.tile_id, kind),
         :ok <- validate_improvement_slot(state.improvements, unit.tile_id, kind) do
      improvement = persist_start_improvement!(state, unit, kind)
      {:ok, %{state | improvements: Map.put(state.improvements, unit.tile_id, improvement)}}
    end
  end

  defp owned_worker(state, user, unit_id) do
    player = find_player(state, user.id)
    unit = Map.get(state.units, unit_id)

    cond do
      is_nil(player) or is_nil(unit) or unit.player_id != player.id -> {:error, :not_owner}
      unit.type != :worker -> {:error, :not_worker}
      true -> {:ok, unit}
    end
  end

  defp parse_kind(kind) when kind in [:farm, :mine, :road], do: {:ok, kind}
  defp parse_kind("farm"), do: {:ok, :farm}
  defp parse_kind("mine"), do: {:ok, :mine}
  defp parse_kind("road"), do: {:ok, :road}
  defp parse_kind(_other), do: {:error, :invalid_improvement}

  defp validate_improvement_terrain(world, tile_id, kind) do
    cond do
      Regions.tile_class(world, tile_id) != :land ->
        {:error, :invalid_terrain}

      not Improvement.allowed?(kind, Regions.terrain(world, tile_id)) ->
        {:error, :invalid_terrain}

      true ->
        :ok
    end
  end

  # A completed improvement refuses any second dig. An in-progress one
  # of the SAME kind just reattaches (any worker may resume a frozen
  # dig — improvements aren't owned); a DIFFERENT kind already
  # mid-build on this tile is refused rather than silently switched.
  # A pillaged one (story 893) is the same "resume the same kind"
  # story, just entered from `:pillaged` instead of `:building`.
  defp validate_improvement_slot(improvements, tile_id, kind) do
    case Map.get(improvements, tile_id) do
      nil -> :ok
      %{status: :complete} -> {:error, :occupied_improvement}
      %{status: :building, kind: ^kind} -> :ok
      %{status: :building} -> {:error, :invalid_improvement}
      %{status: :pillaged, kind: ^kind} -> :ok
      %{status: :pillaged} -> {:error, :invalid_improvement}
    end
  end

  defp persist_start_improvement!(state, unit, kind) do
    case Repo.get_by(Improvement, world_id: state.world.id, tile_id: unit.tile_id) do
      nil ->
        {:ok, improvement} =
          %Improvement{}
          |> Improvement.changeset(%{
            world_id: state.world.id,
            tile_id: unit.tile_id,
            kind: kind,
            progress: 0,
            status: :building,
            builder_unit_id: unit.id
          })
          |> Repo.insert()

        improvement_map(improvement)

      existing ->
        {:ok, improvement} =
          existing |> Improvement.changeset(%{builder_unit_id: unit.id}) |> Repo.update()

        improvement_map(improvement)
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

  defp player_cities(state, user) do
    case find_player(state, user.id) do
      nil ->
        []

      player ->
        for {_id, city} <- state.cities,
            city.player_id == player.id,
            do: format_city(state, city)
    end
  end

  # `production` is an informational per-turn RATE (flat base + worked
  # production), separate from `queue`'s own `banked`/`cost` progress —
  # useful for a "5/turn" readout alongside the current build's bar.
  defp format_city(state, city) do
    worked_production =
      city
      |> Yields.worked_yields(state.world, state.improvements)
      |> Enum.map(& &1.production)
      |> Enum.sum()

    %{
      id: city.id,
      name: city.name,
      tile_id: city.tile_id,
      size: city.size,
      food: city.food,
      food_threshold: Yields.threshold(city.size),
      production: Production.flat_base() + worked_production,
      queue: city.queue,
      territory: city.territory,
      worked_tiles: city.worked_tiles
    }
  end

  defp tile_improvement_at(state, tile_id) do
    case Map.get(state.improvements, tile_id) do
      %{status: :complete, kind: kind} -> kind
      _other -> nil
    end
  end

  # Fog filter for camps (story 892, criterion 7546 — HARD constraint):
  # a camp is known the moment it's inside the player's own claimed
  # region (immediately, no scouting needed — the region-boundary bias
  # criterion 7543 relies on) OR once its tile enters the player's
  # ordinary explored set (the ONLY way a far camp is ever revealed —
  # criterion 7545). Never the raw `state.camps` — that's
  # `Fixtures.list_camps/1`'s sanctioned, ground-truth-only status.
  defp visible_camps(state, user) do
    case find_player(state, user.id) do
      nil ->
        []

      player ->
        home = player_region_tiles(state.world, player.region_id)
        explored = Map.get(state.explored, player.id, MapSet.new())

        state.camps
        |> Map.values()
        |> Enum.reject(&(!is_nil(&1.destroyed_at)))
        |> Enum.filter(&(MapSet.member?(home, &1.tile_id) or MapSet.member?(explored, &1.tile_id)))
        |> Enum.map(&format_camp(&1, state))
    end
  end

  defp player_region_tiles(world, region_id) do
    world |> Regions.partition() |> Map.fetch!(:regions) |> Map.fetch!(region_id) |> MapSet.new()
  end

  # `warriors` nests the camp's own spawned units (matched by
  # `camp_id`, never by tile — a second warrior can land on an
  # adjacent tile, not the camp's own) — attack/defense both read off
  # `Combat.base_strength/1` rather than a second hardcoded 15, so the
  # combat curve and this display can never drift apart.
  defp format_camp(camp, state) do
    strength = Combat.base_strength(:barbarian_warrior)

    warriors =
      for {_id, unit} <- state.units, Map.get(unit, :camp_id) == camp.id do
        %{id: unit.id, tile_id: unit.tile_id, hp: unit.hp, attack: strength, defense: strength}
      end

    %{id: camp.id, tile_id: camp.tile_id, hp: camp.hp, warriors: warriors}
  end

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
          persist_city_changes(old_state.cities, new_state.cities)
          persist_production_item_changes(old_state.cities, new_state.cities)
          persist_camp_changes(Map.get(old_state, :camps, %{}), Map.get(new_state, :camps, %{}))
          persist_player_changes(old_state.players, new_state.players)

          persist_improvement_changes(
            new_state.world.id,
            old_state.improvements,
            new_state.improvements
          )

        :stale ->
          Repo.rollback(:stale)
      end
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, :stale} -> :stale
    end
  end

  # A unit missing from `new_units` that was present in `old_units` was
  # destroyed this delta (combat, currently the only path that removes
  # a unit outside of `found_city`'s own dedicated delete) — swept from
  # the DB here rather than left as a zombie row. `found_city` still
  # deletes its consumed settler immediately, in its own transaction,
  # same as before; this only ever catches removals this generic diff
  # would otherwise silently miss.
  defp persist_unit_changes(old_units, new_units) do
    removed_ids = Map.keys(old_units) -- Map.keys(new_units)
    if removed_ids != [], do: Repo.delete_all(from(u in Unit, where: u.id in ^removed_ids))

    for {id, unit} <- new_units, Map.get(old_units, id) != unit do
      Repo.update_all(from(u in Unit, where: u.id == ^id),
        set: [tile_id: unit.tile_id, movement: unit.movement, hp: unit.hp]
      )
    end
  end

  # Newly founded/renamed/reassigned cities are already persisted
  # immediately by their own command (see "Found city"/"Worked tiles"/
  # "Rename city" above) — this only ever catches what the TICK itself
  # changes: size, food, territory (growth), worked_tiles (a settler's
  # pop cost un-working a tile).
  defp persist_city_changes(old_cities, new_cities) do
    for {id, city} <- new_cities, Map.get(old_cities, id) != city do
      Repo.update_all(from(c in City, where: c.id == ^id),
        set: [
          size: city.size,
          food: city.food,
          territory: city.territory,
          worked_tiles: city.worked_tiles
        ]
      )
    end
  end

  # Items are only ever CREATED (queue_production) or DELETED
  # (cancel_production_item, or consumed on completion) outside a
  # tick's diff; here we only reconcile `banked` changing (accrual,
  # overflow carry) and completed items disappearing from the queue.
  defp persist_production_item_changes(old_cities, new_cities) do
    old_items = queue_items_by_id(old_cities)
    new_items = queue_items_by_id(new_cities)

    for id <- Map.keys(old_items) -- Map.keys(new_items) do
      Repo.delete_all(from(p in ProductionItem, where: p.id == ^id))
    end

    for {id, item} <- new_items, Map.get(old_items, id) != item do
      Repo.update_all(from(p in ProductionItem, where: p.id == ^id),
        set: [banked: item.banked, position: Map.get(item, :position, 0)]
      )
    end
  end

  defp queue_items_by_id(cities) do
    cities |> Map.values() |> Enum.flat_map(& &1.queue) |> Map.new(&{&1.id, &1})
  end

  # New camps are persisted immediately at founding (see
  # `spawn_wilderness_camps/3`) — this only reconciles what the tick
  # itself advances: `spawn_counter` (every camp, every tick), `hp`
  # (story 894's camp assault), and `destroyed_at` (also story 894 — a
  # camp reduced to 0 HP, both via `do_attack_camp/4` immediately and
  # via `Turn`'s barbarian AI loop pillaging nothing of the camp itself,
  # only ever set here).
  defp persist_camp_changes(old_camps, new_camps) do
    for {id, camp} <- new_camps, Map.get(old_camps, id) != camp do
      Repo.update_all(from(c in Camp, where: c.id == ^id),
        set: [hp: camp.hp, spawn_counter: camp.spawn_counter, destroyed_at: camp.destroyed_at]
      )
    end
  end

  # Gold is the only mutable field on a player once joined — bounty
  # kills (story 893, criterion 7557) and camp-destroy rewards (story
  # 894, criterion 7560) are the first things that ever change it after
  # `spawn_new_player/2`'s initial 50.
  defp persist_player_changes(old_players, new_players) do
    for {id, player} <- new_players, Map.get(old_players, id) != player do
      Repo.update_all(from(p in Player, where: p.id == ^id), set: [gold: player.gold])
    end
  end

  # Starting/attaching an improvement is persisted immediately (see
  # "Improvements" above) — this only reconciles what the tick itself
  # advances: progress, completion, and a builder walking away.
  defp persist_improvement_changes(world_id, old_improvements, new_improvements) do
    for {tile_id, improvement} <- new_improvements,
        Map.get(old_improvements, tile_id) != improvement do
      Repo.update_all(
        from(i in Improvement, where: i.world_id == ^world_id and i.tile_id == ^tile_id),
        set: [
          progress: improvement.progress,
          status: improvement.status,
          builder_unit_id: improvement.builder_unit_id
        ]
      )
    end
  end

  # Test-only helpers for `:move_barbarian_for_test` — mirrors `Turn`'s
  # own `maybe_pillage/2` (in-memory) and then a targeted DB write
  # (rather than a full `persist_tick`, since this is a single isolated
  # move, not a tick boundary).
  defp maybe_pillage_for_test(improvements, tile_id) do
    case Map.get(improvements, tile_id) do
      nil -> improvements
      %{status: :complete} = improvement -> Map.put(improvements, tile_id, Improvement.pillage(improvement))
      improvement -> Map.put(improvements, tile_id, improvement)
    end
  end

  defp persist_pillage_for_test(%{status: :complete} = existing, %{status: :pillaged} = pillaged) do
    existing
    |> Improvement.changeset(%{status: pillaged.status, progress: pillaged.progress, builder_unit_id: nil})
    |> Repo.update()
  end

  defp persist_pillage_for_test(_existing, _unchanged), do: :ok

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
      explored: load_explored(world.id),
      cities: load_cities(world.id),
      improvements: load_improvements(world.id),
      camps: load_camps(world.id),
      # Not persisted — see `schedule_heir_if_lord_fell/3`'s doc for the
      # known, narrow restart limitation this implies.
      pending_heirs: %{}
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

  defp load_cities(world_id) do
    items_query = from(p in ProductionItem, order_by: [p.position, p.id])

    from(c in City, where: c.world_id == ^world_id)
    |> Repo.all()
    |> Repo.preload(production_items: items_query)
    |> Map.new(&{&1.id, city_map(&1)})
  end

  defp load_improvements(world_id) do
    from(i in Improvement, where: i.world_id == ^world_id)
    |> Repo.all()
    |> Map.new(&{&1.tile_id, improvement_map(&1)})
  end

  defp load_camps(world_id) do
    from(c in Camp, where: c.world_id == ^world_id)
    |> Repo.all()
    |> Map.new(&{&1.id, camp_map(&1)})
  end

  defp player_map(%Player{} = p),
    do: %{id: p.id, user_id: p.user_id, region_id: p.region_id, gold: p.gold}

  defp unit_map(%Unit{} = u) do
    %{
      id: u.id,
      player_id: u.player_id,
      camp_id: u.camp_id,
      type: u.type,
      tile_id: u.tile_id,
      hp: u.hp,
      max_hp: u.max_hp,
      movement: u.movement,
      max_movement: u.max_movement
    }
  end

  defp city_map(%City{} = c) do
    %{
      id: c.id,
      player_id: c.player_id,
      tile_id: c.tile_id,
      name: c.name,
      size: c.size,
      food: c.food,
      territory: c.territory,
      worked_tiles: c.worked_tiles,
      queue: Enum.map(c.production_items, &queue_item_map/1)
    }
  end

  defp queue_item_map(%ProductionItem{} = item),
    do: %{
      id: item.id,
      type: item.type,
      banked: item.banked,
      cost: item.cost,
      position: item.position
    }

  defp improvement_map(%Improvement{} = i) do
    %{
      tile_id: i.tile_id,
      kind: i.kind,
      progress: i.progress,
      status: i.status,
      builder_unit_id: i.builder_unit_id
    }
  end

  defp camp_map(%Camp{} = c) do
    %{id: c.id, tile_id: c.tile_id, hp: c.hp, spawn_counter: c.spawn_counter, destroyed_at: c.destroyed_at}
  end
end
