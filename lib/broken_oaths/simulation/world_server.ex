defmodule BrokenOaths.Simulation.WorldServer do
  @moduledoc """
  One GenServer per world — the imperative shell around the pure
  `BrokenOaths.Simulation.Turn` core (see `.code_my_spec/architecture/decisions/world-process-architecture.md`).

  Holds the canonical tick-state (see `BrokenOaths.Simulation.Turn`'s moduledoc)
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
  `turn_started_at + world.turn_seconds`.

  ## Ticking

  Story 897: each world carries its own `turn_seconds` (a `worlds`
  column, default 60, immutable after creation — see
  `BrokenOaths.Worlds.World`) rather than every world in the process
  sharing one hardcoded cadence. In every environment except test,
  `init/1` schedules a `Process.send_after(self(), :tick, turn_seconds
  * 1_000)` self-loop, and if `turn_started_at` is more than
  `turn_seconds` stale on boot (the world was dormant), missed ticks
  are run synchronously before the server accepts requests — wall-clock
  catch-up. Test env sets `config :broken_oaths, :game_auto_tick,
  false`, which disables both the self-loop and catch-up: `advance_turn/1`
  (called by `BrokenOathsSpex.Fixtures.advance_turn/1`) is the only
  tick source, exactly mirroring what the timer would have fired.
  """

  use GenServer

  import Ecto.Query

  alias BrokenOaths.Cities.{Buildings, City, Improvement, Production, ProductionItem, Yields}

  alias BrokenOaths.Combat.{Camp, Camps, CityDefense, Siege}
  alias BrokenOaths.Combat.Resolver

  alias BrokenOaths.Diplomacy.{Cooperation, Discovery, KnownPlayer}

  alias BrokenOaths.Feudal.{
    Bank,
    GoldLog,
    Levy,
    OathStrain.Ledger,
    ProtectionPact,
    Rebellion,
    Rebellion.Resolution,
    Rebellion.War,
    RebellionPact,
    RebellionPact.Conspiracy,
    Stewardship,
    Tribute,
    Vassalage,
    Vassalization
  }

  alias BrokenOaths.Simulation.{Spawner, Turn}

  alias BrokenOaths.Game
  alias BrokenOaths.Players.{Player, Presence}
  alias BrokenOaths.Repo
  alias BrokenOaths.Technology.{PlayerResearch, Research}
  alias BrokenOaths.Units.{Order, Unit}
  alias BrokenOaths.Users
  alias BrokenOaths.Users.User
  alias BrokenOaths.Vision.{Exploration, Visibility}
  alias BrokenOaths.Worlds
  alias BrokenOaths.Worlds.ClearedFeature
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.World

  # Story 897: no more single process-wide cadence — every tick/catch-up/
  # countdown computation below reads `state.world.turn_seconds` instead.

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

    tick_timer =
      if auto_tick?() and not state.world.paused, do: schedule_tick(state.world.turn_seconds)

    {:ok, Map.put(state, :tick_timer, tick_timer)}
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
    {:reply, Visibility.player_units(state, user), state}
  end

  def handle_call({:units_visible_to, user}, _from, state) do
    {:reply, Visibility.visible_units(state, user), state}
  end

  def handle_call({:visibility, user}, _from, state) do
    {:reply, Visibility.visibility(state, user), state}
  end

  def handle_call(:turn_number, _from, state), do: {:reply, state.turn, state}

  def handle_call(:turn_ends_at, _from, state) do
    {:reply, DateTime.add(state.turn_started_at, state.world.turn_seconds, :second), state}
  end

  def handle_call({:gold, user}, _from, state) do
    gold = state |> find_player(user.id) |> gold_of()
    {:reply, gold, state}
  end

  # Story 904: the progress panel's career totals — `nil` for a user
  # who hasn't joined this world, same "no player, no data" shape
  # `player_research_summary/2` already returns.
  def handle_call({:player_stats, user}, _from, state) do
    {:reply, player_stats(state, user), state}
  end

  def handle_call({:queue_move, user, unit_id, to_tile}, _from, state) do
    case Unit.queue_move(state, user, unit_id, to_tile) do
      {:ok, result, queued, moved, capture_events} ->
        case persist_tick(queued, moved) do
          :ok ->
            broadcast(
              moved.world.id,
              [:units_changed | approach_alert_events(state, moved)] ++ capture_events
            )

            {:reply, {:ok, result}, moved}

          :stale ->
            # A competing instance advanced the world under us — drop the
            # move, resync, and let the player retry against fresh state.
            {:reply, {:error, :stale}, resync(state)}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Story 929 "Build road to a destination" — queues a `:road_to` order
  # (see `Units.Unit.build_road_to/4`'s own doc); unlike `:queue_move`
  # above, there's no immediate partial resolution to push back — the
  # order always waits for the next tick boundary to take its first
  # step (`Simulation.Turn.RoadBuilder.resolve/1`). `result` carries
  # `route:` (the full planned path), which `GameLive.Play`'s own
  # `"build_road_to"` handler pushes straight to `"game:path"` the same
  # immediate way `:queue_move`'s own reply already does, so the ghost
  # route appears in the SAME render as the click rather than waiting
  # on the `:units_changed` broadcast round trip.
  def handle_call({:build_road_to, user, unit_id, destination}, _from, state) do
    case Unit.build_road_to(state, user, unit_id, destination) do
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

  # Playtest issue 50a0c866 "all unit actions cancellable from the units
  # pane" — the move/road-to sibling of `:cancel_improvement` below:
  # drops whichever order `unit_id` currently holds
  # (`Unit.cancel_order/3`) from `state.orders`; `persist_tick/2`'s own
  # generic `persist_order_changes/2` diff is what actually deletes the
  # DB row — the same path `:queue_move`/`:build_road_to` above already
  # lean on to WRITE one.
  def handle_call({:cancel_move, user, unit_id}, _from, state) do
    case Unit.cancel_order(state, user, unit_id) do
      {:ok, new_state} ->
        case persist_tick(state, new_state) do
          :ok ->
            broadcast(new_state.world.id, [:units_changed])
            {:reply, :ok, new_state}

          :stale ->
            {:reply, {:error, :stale}, resync(state)}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:attack, user, unit_id, target_unit_id}, _from, state) do
    case Resolver.attack(state, user, unit_id, target_unit_id) do
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
    case Camps.attack_camp(state, user, unit_id, camp_id) do
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

  # Story 895: attacking a city reuses the "attack" hook, with
  # `target_city_id` instead of `target_unit_id` (a city is not a
  # `Game.Unit`) — same immediate-resolution shape as `:attack_camp`
  # above. `result` carries `damage_dealt` (to the city's HP) and
  # `damage_taken` (counter-attack damage the attacker takes from the
  # city's strongest garrisoned defender — 0 if undefended). Also
  # pushes the "under attack" alert straight to the city owner, same
  # direct-push pattern `:lineage_continued` uses for a player-scoped
  # notification.
  def handle_call({:attack_city, user, unit_id, city_id}, _from, state) do
    case Siege.attack_city(state, user, unit_id, city_id) do
      {:ok, result, new_state, alert} ->
        case persist_tick(state, new_state) do
          :ok ->
            broadcast(new_state.world.id, [:units_changed, :cities_changed, alert])
            {:reply, {:ok, result}, new_state}

          :stale ->
            {:reply, {:error, :stale}, resync(state)}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # QA issue 12bed1e4 — the Archer's own ranged "shoot" surface: same
  # immediate-resolution, persist+broadcast shape as `:attack` above,
  # just routed through `Resolver.shoot/4` instead of `Resolver.attack/4`.
  def handle_call({:shoot, user, unit_id, target_unit_id}, _from, state) do
    case Resolver.shoot(state, user, unit_id, target_unit_id) do
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

  # QA issue 12bed1e4 — the ranged sibling of `:attack_camp` above.
  def handle_call({:shoot_camp, user, unit_id, camp_id}, _from, state) do
    case Camps.shoot_camp(state, user, unit_id, camp_id) do
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

  # QA issue 12bed1e4 — the ranged sibling of `:attack_city` above.
  def handle_call({:shoot_city, user, unit_id, city_id}, _from, state) do
    case Siege.shoot_city(state, user, unit_id, city_id) do
      {:ok, result, new_state, alert} ->
        case persist_tick(state, new_state) do
          :ok ->
            broadcast(new_state.world.id, [:units_changed, :cities_changed, alert])
            {:reply, {:ok, result}, new_state}

          :stale ->
            {:reply, {:error, :stale}, resync(state)}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Story 920 — the Fortify stance's own single-target, no-result
  # command: same immediate-resolution, persist+broadcast shape as
  # `:attack` above (setting `fortified_turns` to 1 is still a
  # unit-only diff `persist_tick` picks up now that
  # `persist_unit_changes/2` writes back `Units.Unit`'s own
  # `fortified_turns` field).
  def handle_call({:fortify, user, unit_id}, _from, state) do
    case Unit.fortify(state, user, unit_id) do
      {:ok, new_state} ->
        case persist_tick(state, new_state) do
          :ok ->
            broadcast(new_state.world.id, [:units_changed])
            {:reply, :ok, new_state}

          :stale ->
            {:reply, {:error, :stale}, resync(state)}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Playtest issue 50a0c866 — the un-fortify sibling of `:fortify`
  # above: same immediate-resolution, persist+broadcast shape, just
  # resetting `fortified_turns` back to 0 instead of setting it.
  def handle_call({:unfortify, user, unit_id}, _from, state) do
    case Unit.unfortify(state, user, unit_id) do
      {:ok, new_state} ->
        case persist_tick(state, new_state) do
          :ok ->
            broadcast(new_state.world.id, [:units_changed])
            {:reply, :ok, new_state}

          :stale ->
            {:reply, {:error, :stale}, resync(state)}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:found_city, user, unit_id}, _from, state) do
    case City.found_city(state, user, unit_id) do
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
    case Production.queue_production(state, user, city_id, type) do
      {:ok, new_state} ->
        broadcast(new_state.world.id, [:cities_changed])
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:reorder_production_item, user, city_id, item_id}, _from, state) do
    case Production.reorder_production_item(state, user, city_id, item_id) do
      {:ok, new_state} ->
        broadcast(new_state.world.id, [:cities_changed])
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:cancel_production_item, user, city_id, item_id}, _from, state) do
    case Production.cancel_production_item(state, user, city_id, item_id) do
      {:ok, new_state} ->
        broadcast(new_state.world.id, [:cities_changed])
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:assign_worked_tile, user, city_id, from_tile, to_tile}, _from, state) do
    case City.assign_worked_tile(state, user, city_id, from_tile, to_tile) do
      {:ok, new_state} ->
        broadcast(new_state.world.id, [:cities_changed])
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:rename_city, user, city_id, name}, _from, state) do
    case City.rename_city(state, user, city_id, name) do
      {:ok, new_state} ->
        broadcast(new_state.world.id, [:cities_changed])
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:start_improvement, user, unit_id, kind}, _from, state) do
    case Improvement.start_improvement(state, user, unit_id, kind) do
      {:ok, new_state} ->
        broadcast(new_state.world.id, [:improvements_changed])
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # QA issue 8aa2c571 — see `BrokenOaths.Game.cancel_improvement/3`'s doc.
  def handle_call({:cancel_improvement, user, unit_id}, _from, state) do
    case Improvement.cancel_improvement(state, user, unit_id) do
      {:ok, new_state} ->
        broadcast(new_state.world.id, [:improvements_changed])
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Story 927 "Workers chop woods and rainforest" — resolves immediately,
  # like `:start_improvement`/`:cancel_improvement`'s own tile-state
  # writes, but through `persist_tick/2` (not a bare inline write) since
  # a chop also touches `state.units` (a spent build charge, possibly
  # expending the worker) and `state.cities` (the production credit) —
  # both of which `persist_tick/2`'s own generic diff already knows how
  # to reconcile. `:improvements_changed` doubles as "terrain changed"
  # here: `BrokenOathsWeb.GameLive.Play`'s own board refresh re-derives
  # the board's rendered terrain (and a selected worker's own Chop
  # button) from `state.cleared_features` on every one of its handlers,
  # `:improvements_changed` included.
  def handle_call({:chop, user, unit_id}, _from, state) do
    case Improvement.chop(state, user, unit_id) do
      {:ok, new_state} ->
        case persist_tick(state, new_state) do
          :ok ->
            broadcast(new_state.world.id, [:units_changed, :cities_changed, :improvements_changed])
            {:reply, :ok, new_state}

          :stale ->
            {:reply, {:error, :stale}, resync(state)}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Story 927 — the tile ids a worker has permanently chopped, world-
  # wide: not fog-filtered (same "cheap, derived, no separate secrecy"
  # status `state.roads`/`state.improvements` themselves have before
  # `visible_improvements/2` filters them for a client) — the ONE place
  # this ever gets fog-gated is the `known` tile window the client's
  # board painter already reads from.
  def handle_call(:cleared_features, _from, state) do
    {:reply, Map.get(state, :cleared_features, MapSet.new()), state}
  end

  def handle_call({:player_cities, user}, _from, state) do
    {:reply, City.player_cities(state, user), state}
  end

  # Story 899: every civilization `user` has discovered in this world —
  # permanent once recorded, unrelated to current fog of war (see
  # `Discovery`'s and `KnownPlayer`'s docs). Ordered by `viewer_player_id`'s
  # own directional `KnownPlayer` rows, not fog-filtered current
  # visibility.
  def handle_call({:known_players, user}, _from, state) do
    {:reply, Discovery.known_players(state, user), state}
  end

  # Story 901: every alliance `user` is a party to — reads straight from
  # `Repo` rather than an in-memory `state` cache the way `known_players`
  # does, since (unlike discovery) nothing on the tick hot-path ever
  # needs to check alliance status — `Cooperation.split_bounty/3`
  # explicitly does NOT gate on one (criterion 7624).
  def handle_call({:alliances, user}, _from, state) do
    {:reply, Stewardship.list_alliances(state, user), state}
  end

  # Builds (or updates, if a `:proposed` row already exists for this
  # pair) an `Alliance` changeset via `Cooperation.propose/4` and
  # persists it directly — an alliance is world-membership-scoped
  # coordination state, not tick-state, so unlike a move/attack/build
  # order this never touches `persist_tick/2` or the optimistic
  # turn-guard those use.
  def handle_call({:propose_alliance, user, other_user}, _from, state) do
    case Cooperation.propose_alliance(state, user, other_user) do
      {:ok, _alliance} ->
        broadcast(state.world.id, [:alliances_changed])
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Same non-tick-state status as `:propose_alliance` above.
  def handle_call({:accept_alliance, user, alliance_id}, _from, state) do
    case Cooperation.accept_alliance(state, user, alliance_id) do
      {:ok, _alliance} ->
        broadcast(state.world.id, [:alliances_changed])
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # -------------------------------------------------------------------
  # Vassalage / Tribute (stories 907/908)
  # -------------------------------------------------------------------

  # Story 907: the lord's own "Vassals" list — world-membership-scoped
  # coordination state, same non-tick-state status `list_alliances/2`
  # already has for `Alliance`.
  def handle_call({:vassals, user}, _from, state) do
    {:reply, vassals(state, user), state}
  end

  # Story 907/908: the VASSAL's own read of their oath — who they're
  # sworn to, the current tribute rate, whether the Oath screen is
  # still pending, and their own levy status.
  def handle_call({:vassal_status, user}, _from, state) do
    {:reply, vassal_status(state, user), state}
  end

  # Story 917: whether `lord_user_id`'s own Lord unit is currently dead
  # on the board — the "seize the moment" trigger. Read fresh off
  # `state.units` every call (never cached on a socket assign) since
  # `"declare_independence"` (`GameLive.Play`) needs this to be
  # up-to-the-instant accurate even against an ALREADY-connected
  # socket whose own `vassal_status` assign may not have refreshed yet
  # (no `:vassals_changed` broadcast fires from the immediate,
  # out-of-tick combat path that can kill a lord).
  def handle_call({:lord_fallen?, lord_user_id}, _from, state) do
    {:reply, lord_fallen?(state, lord_user_id), state}
  end

  # Story 907: the vassal's own secret Hidden Agenda pick, closing the
  # Oath screen — never reaches the lord's own view (`vassals/2` never
  # reads `hidden_agenda` at all).
  def handle_call({:choose_hidden_agenda, user, agenda}, _from, state) do
    case do_choose_hidden_agenda(state, user, agenda) do
      {:ok, _vassalage} ->
        broadcast(state.world.id, [:vassals_changed])
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Story 908: the lord-set, per-vassal, adjustable tribute rate —
  # persisted immediately, same non-tick-state status `:set_research`
  # already has, takes effect on the vassal's next turn boundary
  # tribute (`apply_tribute/1`, below).
  def handle_call({:set_tribute_rate, user, vassal_user_id, rate}, _from, state) do
    case do_set_tribute_rate(state, user, vassal_user_id, rate) do
      {:ok, _vassalage} ->
        broadcast(state.world.id, [:vassals_changed])
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Story 906: the conqueror's own execute-or-release choice for a
  # captured, still-living garrison — persisted via `persist_tick/2`
  # like every other in-place unit mutation (`persist_unit_changes/2`
  # already deletes any unit missing from the new map).
  def handle_call({:resolve_garrison_fate, user, city_id, choice}, _from, state) do
    case Siege.apply_garrison_fate(state, user, city_id, choice) do
      {:ok, new_state} ->
        case persist_tick(state, new_state) do
          :ok ->
            broadcast(new_state.world.id, [:units_changed])
            {:reply, :ok, new_state}

          :stale ->
            {:reply, {:error, :stale}, resync(state)}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Story 908: the lord's own call to arms — a fresh, `:pending` `Levy`
  # against a third player, persisted immediately (not tick-state, same
  # status every other Vassalage/Levy mutation in this section has).
  def handle_call({:issue_levy, user, vassal_user_id, target_user_id, share}, _from, state) do
    case Levy.issue(state, user, vassal_user_id, target_user_id, share) do
      {:ok, _levy} ->
        broadcast(state.world.id, [:vassals_changed])
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Story 908: the vassal answering their own lord's pending call —
  # they keep command of the pledged units; nothing about answering
  # moves a single one.
  def handle_call({:answer_levy, user, lord_user_id}, _from, state) do
    case Levy.answer(state, user, lord_user_id) do
      {:ok, _levy} ->
        broadcast(state.world.id, [:vassals_changed])
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Story 908: the refusal branch — marks the levy refused, spikes the
  # vassal's own Oath Strain (`Tribute.spike_oath_strain/1`), AND dings
  # their own Honor (`Tribute.apply_refusal_honor_penalty/1`, QA issue
  # c0ec53ed — criterion 7678's "strain and Honor hits" was only
  # half-wired before this fix), "a publicly-legible broken obligation."
  # The Honor half lives on `state.players` (in-memory tick-state, NOT
  # a Repo-backed changeset the way Levy/Vassalage are) — persisted via
  # `persist_tick/2`, the same shape `resolve_steward_defend/5`'s own
  # sabotage-penalty write and `apply_garrison_fate_honor/2` already
  # establish for an in-place Honor-only state change.
  def handle_call({:refuse_levy, user, lord_user_id}, _from, state) do
    case Levy.refuse(state, user, lord_user_id) do
      {:ok, _levy, new_state} ->
        case persist_tick(state, new_state) do
          :ok ->
            # `:vassals_changed` refreshes the levy status badge,
            # `:units_changed` refreshes the Honor figure (`refresh_board/1`
            # re-pulls `Game.honor/2`; `refresh_vassalage/1` alone does
            # not) — the same two-broadcast pairing a Honor-bearing
            # change needs whenever it rides alongside a Vassalage-only
            # mutation.
            broadcast(new_state.world.id, [:vassals_changed, :units_changed])
            {:reply, :ok, new_state}

          :stale ->
            {:reply, {:error, :stale}, resync(state)}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Story 913: a lord's one-off gift to `vassal_user_id` — eases their
  # Oath Strain (`OathStrain.ease_gift/1`), persisted immediately, same
  # non-tick-state status `:set_tribute_rate` above already has.
  def handle_call({:gift_vassal, user, vassal_user_id}, _from, state) do
    case Ledger.gift_vassal(state, user, vassal_user_id) do
      {:ok, _vassalage} ->
        broadcast(state.world.id, [:vassals_changed])
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Story 913: a lord and `vassal_user_id` declaring a shared enemy
  # (`enemy_user_id`) — eases the vassal's Oath Strain (`OathStrain.
  # ease_shared_enemy/1`), same immediate-persist status as
  # `:gift_vassal` above.
  def handle_call({:declare_shared_enemy, user, vassal_user_id, enemy_user_id}, _from, state) do
    case Ledger.declare_shared_enemy(state, user, vassal_user_id, enemy_user_id) do
      {:ok, _vassalage} ->
        broadcast(state.world.id, [:vassals_changed])
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Story 913 (criterion 7722): the vassal's own narrow seam for
  # marking their lord's Protection Pact unhonored — spikes their own
  # Oath Strain (`OathStrain.spike_broken_protection_pact/1`). Distinct
  # from the REAL Protection Pact engine (story 914, `resolve_broken/3`,
  # a window genuinely expiring unanswered) — this handler only ever
  # touches Oath Strain, never the lord's Honor or fellow-vassal
  # contagion, exactly the narrower scope criterion 7722's own moduledoc
  # describes for this invented hook.
  def handle_call({:mark_pact_unhonored, user, lord_user_id}, _from, state) do
    case Ledger.mark_pact_unhonored(state, user, lord_user_id) do
      {:ok, _vassalage} ->
        broadcast(state.world.id, [:vassals_changed])
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # -------------------------------------------------------------------
  # Rebellion (stories 915/919)
  # -------------------------------------------------------------------

  # Story 915 (criterion 7732): read-only, no side effect — see
  # `Rebellion.War.independence_preview/3`'s own doc.
  def handle_call({:independence_preview, user, lord_user_id}, _from, state) do
    {:reply, War.independence_preview(state, user, lord_user_id), state}
  end

  # Story 915: severs the oath, resolves risings, spawns the temporary
  # army, and opens the war — see `Rebellion.War.declare_independence/3`'s own
  # doc. Bypasses `persist_tick/2`'s own generic diff (which never
  # tracks a unit's own `player_id` changing, the defecting-garrison
  # case) in favor of its own immediate, targeted Repo writes — the
  # SAME "immediate, not tick-state" status `Vassalization.
  # apply_captures/1`'s own persistence already has for the sibling
  # vassalization write.
  def handle_call({:declare_independence, user, lord_user_id}, _from, state) do
    case War.declare_independence(state, user, lord_user_id) do
      {:ok, result, new_state, lord_events} ->
        broadcast(
          new_state.world.id,
          [:vassals_changed, :units_changed, :cities_changed] ++ lord_events
        )

        {:reply, {:ok, result}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # `user`'s own active-or-most-recent Rebellion as REBEL.
  def handle_call({:rebellion_status, user}, _from, state) do
    {:reply, rebellion_status(state, user), state}
  end

  # Every Rebellion raised against `user` as the FORMER LORD.
  def handle_call({:rebellions_as_lord, user}, _from, state) do
    {:reply, rebellions_as_lord(state, user), state}
  end

  # Story 919: either side offers a negotiated peace — persisted only
  # as in-memory tick-state (`state.peace_offers`), the same "no
  # restart survival needed" status `state.protection_calls` already
  # has, until `accept_peace/3` actually closes it.
  def handle_call(
        {:offer_peace, user, counterparty_user_id, outcome, reparations_gold},
        _from,
        state
      ) do
    case War.offer_peace(state, user, counterparty_user_id, outcome, reparations_gold) do
      {:ok, new_state} ->
        broadcast(new_state.world.id, [:vassals_changed])
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:accept_peace, user, counterparty_user_id}, _from, state) do
    case War.accept_peace(state, user, counterparty_user_id) do
      {:ok, new_state} ->
        broadcast(new_state.world.id, [:vassals_changed, :units_changed, :cities_changed])
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:reject_peace, user, counterparty_user_id}, _from, state) do
    case War.reject_peace(state, user, counterparty_user_id) do
      {:ok, new_state} ->
        broadcast(new_state.world.id, [:vassals_changed])
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # -------------------------------------------------------------------
  # Coordinated Rebellion — Pact of Broken Oaths (story 916)
  # -------------------------------------------------------------------

  # Read-only, world-membership-scoped coordination state, same
  # non-tick-state status `list_alliances/2`/`vassals/2` already have —
  # `pact_view/2` masks every OTHER member's own commit status before
  # it ever reaches this reply (criterion 7738).
  def handle_call({:pact_view, user}, _from, state) do
    {:reply, Conspiracy.pact_view(state, user), state}
  end

  def handle_call({:pact_candidates, user}, _from, state) do
    {:reply, Conspiracy.pact_candidates(state, user), state}
  end

  # Persisted directly (never `persist_tick/2`) — same status
  # `do_propose_alliance/3` already has, since nothing about opening a
  # pact chat touches the tick-state hot path.
  def handle_call({:open_pact_chat, user, strike_turn, invitee_user_ids}, _from, state) do
    case Conspiracy.open_pact_chat(state, user, strike_turn, invitee_user_ids) do
      {:ok, pact} ->
        broadcast(state.world.id, [:pact_changed])
        {:reply, {:ok, pact}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:pact_commit, user}, _from, state) do
    case Conspiracy.pact_answer(state, user, :committed) do
      {:ok, member} ->
        broadcast(state.world.id, [:pact_changed])
        {:reply, {:ok, member}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:pact_decline, user}, _from, state) do
    case Conspiracy.pact_answer(state, user, :declined) do
      {:ok, member} ->
        broadcast(state.world.id, [:pact_changed])
        {:reply, {:ok, member}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Criterion 7741 — flips this member's own row `informer: true`,
  # never touching `commit_status`: informing changes no odds.
  def handle_call({:pact_inform, user}, _from, state) do
    case Conspiracy.pact_inform(state, user) do
      {:ok, member} ->
        broadcast(state.world.id, [:pact_changed])
        {:reply, {:ok, member}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:pact_informed_notice, user}, _from, state) do
    {:reply, pact_informed_notice(state, user), state}
  end

  def handle_call({:conspiracy_heat, user}, _from, state) do
    {:reply, Conspiracy.conspiracy_heat(state, user), state}
  end

  # Immediate, targeted Repo writes (`state.cities`/`state.units`
  # updated in-place) — same "bypasses `persist_tick/2`'s own generic
  # diff" status `rise_cities/5` already has, since neither a city's
  # nor a unit's own HP is otherwise ever mutated outside a tick.
  def handle_call({:brace_defenses, user}, _from, state) do
    case Conspiracy.brace_defenses(state, user) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:reposition_lord, user}, _from, state) do
    case Conspiracy.reposition_lord(state, user) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:buy_off_conspirators, user}, _from, state) do
    case Conspiracy.buy_off_conspirators(state, user) do
      :ok ->
        broadcast(state.world.id, [:vassals_changed])
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:honor_protection_call, user, vassal_user_id}, _from, state) do
    case ProtectionPact.honor_protection_call(state, user, vassal_user_id) do
      {:ok, _vassalage} ->
        broadcast(state.world.id, [:vassals_changed])
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # -------------------------------------------------------------------
  # Gold Bank (story 909)
  # -------------------------------------------------------------------

  # `%{gold:, cap:}` — `Bank.status/1` over `banked_gold`/`bank_cap`,
  # the pair `GameLive.Play` renders as `bank-gold`/`bank-cap`.
  def handle_call({:bank, user}, _from, state) do
    {:reply, Bank.status_for(state, user), state}
  end

  # Stories 922/923 — `user`'s own live `%{income:, upkeep:, net:}`
  # readout: gross REAL city income (`gold_income_by_player/1`, the same
  # figure `apply_tribute/1`/`apply_bank/1` already use) against total
  # unit+building upkeep (`Bank.maintenance_by_player/1`) — the figure
  # `GameLive.ProgressPanel`'s own "Gold/turn" line renders. A pure read,
  # never gated on `Game.feudal_enabled?/0` — unlike `apply_bank/1`'s own
  # tick-time SWEEP, a player can see what their economy would net
  # before the flag ever turns the sweep itself on, same "reads stay
  # live, only writes gate" status `Bank.status_for/2` already has
  # relative to `collect_for/2`/`upgrade_for/2`.
  def handle_call({:gold_per_turn, user}, _from, state) do
    case find_player(state, user.id) do
      nil ->
        {:reply, %{income: 0, upkeep: 0, net: 0}, state}

      player ->
        income = state |> gold_income_by_player() |> Map.get(player.id, 0)
        upkeep = state |> Bank.maintenance_by_player() |> Map.get(player.id, 0)
        {:reply, %{income: income, upkeep: upkeep, net: income - upkeep}, state}
    end
  end

  # The deliberate engagement tap: sweep the ENTIRE bank into the
  # treasury (`Bank.collect/1`) — a no-op (empties nothing, moves
  # nothing) against an already-empty bank, never refused outright.
  def handle_call({:collect_bank, user}, _from, state) do
    case Bank.collect_for(state, user) do
      {:ok, new_state} ->
        case persist_tick(state, new_state) do
          :ok -> {:reply, :ok, new_state}
          :stale -> {:reply, {:error, :stale}, resync(state)}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Raises the bank's own cap for `Bank.upgrade_cost/1`'s own gold
  # price — refused outright (no partial charge) when unaffordable.
  def handle_call({:upgrade_bank, user}, _from, state) do
    case Bank.upgrade_for(state, user) do
      {:ok, new_state} ->
        case persist_tick(state, new_state) do
          :ok -> {:reply, :ok, new_state}
          :stale -> {:reply, {:error, :stale}, resync(state)}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # -------------------------------------------------------------------
  # Feudal Stewardship (story 910)
  # -------------------------------------------------------------------

  # The world-visible Honor reputation figure (`Player.honor`) — `0`
  # for a user who hasn't joined this world, same "no player, no data"
  # shape `gold_of/1` already has.
  def handle_call({:honor, user}, _from, state) do
    {:reply, state |> find_player(user.id) |> honor_of(), state}
  end

  # The owner's own full steward-action audit trail (criterion 7695) —
  # every `StewardLog` row where THIS player is the one being
  # stewarded, freshest first.
  def handle_call({:steward_log, user}, _from, state) do
    {:reply, Stewardship.steward_log(state, user), state}
  end

  # `Bank.steward_collect/1` — sweeps the offline owner's ENTIRE bank
  # into their own treasury, pure stewardship (the steward's own
  # treasury never moves). Refused unless `steward_user` is eligible
  # (`Stewardship.eligible?/1`) and `owner_user_id` is genuinely
  # offline (`Presence.online?/2`).
  def handle_call({:steward_collect_bank, steward_user, owner_user_id}, _from, state) do
    case Stewardship.collect_bank(state, steward_user, owner_user_id) do
      {:ok, new_state} ->
        case persist_tick(state, new_state) do
          :ok -> {:reply, :ok, new_state}
          :stale -> {:reply, {:error, :stale}, resync(state)}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Sets the offline owner's own production queue — the SAME
  # constructive-only catalog `queue_production` itself already builds
  # from (`Stewardship.constructive_item?/1`), scoped through
  # stewardship eligibility instead of ownership. Persisted immediately,
  # same "not tick-state" status `Production.queue_production/4` already has.
  def handle_call(
        {:steward_queue_production, steward_user, owner_user_id, city_id, type},
        _from,
        state
      ) do
    case Stewardship.queue_production(state, steward_user, owner_user_id, city_id, type) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  # "No cancel-griefing" — a steward's cancel attempt is refused
  # structurally: no path anywhere in this module ever reaches the
  # real `Production.cancel_production_item/4`. Same discipline
  # `:steward_disband_unit`/`:steward_queue_move`/`:steward_attack`
  # share below — each a permanent, unconditional refusal, not a
  # permission check that could someday pass.
  def handle_call(
        {:steward_cancel_production_item, _steward_user, _owner_user_id, _city_id, _item_id},
        _from,
        state
      ) do
    {:reply, {:error, :not_constructive}, state}
  end

  # "No disbanding" — see `:steward_cancel_production_item` above; no
  # disband mechanic exists anywhere in this codebase yet, for anyone,
  # owner or steward.
  def handle_call({:steward_disband_unit, _steward_user, _owner_user_id, _unit_id}, _from, state) do
    {:reply, {:error, :not_constructive}, state}
  end

  # "Normally stewards CANNOT move the offline player's units" — the
  # default-closed baseline `:steward_defend`'s own emergency exception
  # opens against below. Always refused, regardless of eligibility or
  # attack status.
  def handle_call(
        {:steward_queue_move, _steward_user, _owner_user_id, _unit_id, _to_tile},
        _from,
        state
      ) do
    {:reply, {:error, :not_allowed}, state}
  end

  # "Never to launch aggression" — a steward's attack order is refused
  # structurally, same "no path to the real command" discipline as
  # cancel/disband above, even mid-emergency.
  def handle_call(
        {:steward_attack, _steward_user, _owner_user_id, _unit_id, _target_camp_id},
        _from,
        state
      ) do
    {:reply, {:error, :not_allowed}, state}
  end

  # EMERGENCY DEFENSE (story 910): the one sanctioned exception to
  # "stewards can't move units" — only while the offline owner is
  # `Stewardship.under_attack?/1`, and only for a genuinely defensive
  # reposition (`Stewardship.defend_target_allowed?/3`, strictly
  # adjacent to the unit's own current tile). An eligible steward who
  # abuses the window (attacked, but the destination overreaches) is
  # provable sabotage — refused AND dinged on Honor, both persisted.
  def handle_call({:steward_defend, steward_user, owner_user_id, unit_id, to_tile}, _from, state) do
    case Stewardship.defend(state, steward_user, owner_user_id, unit_id, to_tile) do
      {:ok, new_state} ->
        case persist_tick(state, new_state) do
          :ok ->
            broadcast(new_state.world.id, [:units_changed])
            {:reply, :ok, new_state}

          :stale ->
            {:reply, {:error, :stale}, resync(state)}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Story 902: `user`'s research state, plus their CURRENT science
  # income (`Research.science_per_turn/1` over their own cities right
  # now — not a value banked anywhere, so this is always freshly
  # computed, never persisted).
  def handle_call({:player_research, user}, _from, state) do
    {:reply, player_research_summary(state, user), state}
  end

  # Story 902: selecting/switching research is not tick-state the way
  # science accrual is — same non-tick-state status as
  # `:propose_alliance`/`:accept_alliance` above, persisted immediately
  # via its own changeset rather than waiting for a turn boundary.
  def handle_call({:set_research, user, tech}, _from, state) do
    case do_set_research(state, user, tech) do
      {:ok, new_state} ->
        broadcast(new_state.world.id, [:research_changed])
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Ground truth, unfiltered — see `BrokenOathsSpex.Fixtures.list_camps/1`'s
  # doc for why this is a sanctioned exception to the fog-filtered board
  # surface (region math has the same status).
  def handle_call(:list_camps, _from, state) do
    {:reply, Visibility.list_camps(state), state}
  end

  def handle_call({:camps_visible_to, user}, _from, state) do
    {:reply, Visibility.visible_camps(state, user), state}
  end

  # QA issue 56ee521a: fog-filtered ENEMY (another player's own) cities
  # — the same "own region OR explored" rule `visible_camps/2` already
  # uses, minus every city already occupied by the VIEWER themselves
  # (their own captured holding isn't a fresh attack target — see
  # `captured_cities_visible_to/2`'s own doc for where THAT surfaces
  # instead). Empty unless `Game.feudal_enabled?/0` — belt-and-
  # suspenders alongside `Siege.attack_city/4`'s own gate, matching
  # `Vassalization.apply_captures/1`'s own posture.
  def handle_call({:enemy_cities_visible_to, user}, _from, state) do
    {:reply, Visibility.visible_enemy_cities(state, user), state}
  end

  # QA issue ffa66192: cities the VIEWER has personally captured
  # (`occupied_by_player_id == their own player id`), each carrying
  # `fallen_garrison?` — whether `Siege.fallen_garrison/2` still finds a
  # living defender awaiting the execute/release choice. Powers
  # `GameLive.Play`'s own "Captured Cities" panel. Empty unless `Game.
  # feudal_enabled?/0`, same belt-and-suspenders status as
  # `visible_enemy_cities/2` above.
  def handle_call({:captured_cities_visible_to, user}, _from, state) do
    {:reply, Visibility.captured_cities(state, user), state}
  end

  def handle_call({:tile_improvement, tile_id}, _from, state) do
    {:reply, Improvement.tile_improvement_at(state, tile_id), state}
  end

  def handle_call({:improvements_visible_to, user}, _from, state) do
    {:reply, Improvement.visible_improvements(state, user), state}
  end

  # Playtest issue 4 — "click a known player to center the globe on
  # them": the tile of THEIR nearest city/unit `user` can currently see.
  def handle_call({:visible_tile_of, user, target_user_id}, _from, state) do
    {:reply, Visibility.visible_tile_of(state, user, target_user_id), state}
  end

  def handle_call({:set_unit_hp_for_test, unit_id, hp}, _from, state) do
    Repo.update_all(from(u in Unit, where: u.id == ^unit_id), set: [hp: hp])
    unit = Map.fetch!(state.units, unit_id)
    new_state = %{state | units: Map.put(state.units, unit_id, %{unit | hp: hp})}
    {:reply, :ok, new_state}
  end

  # Test-only: instantly sets `user`'s own treasury to `gold`, same
  # narrow, documented-bridge status as `:set_unit_hp_for_test` above.
  # Stand-in for a per-turn city GOLD YIELD this codebase doesn't have
  # yet at all (`BrokenOaths.Cities.Yields` only ever produces food/
  # production; a player's `gold` column only ever moves via
  # `BarbarianAI.bounty_gold/0` and `Camps.destroy_reward/0`, both
  # one-off rewards, never a recurring per-turn income) — the exact
  # same "no real source exists yet" gap `:set_unit_hp_for_test` already
  # papers over for healing (story 881, before any combat existed to
  # produce a damaged unit). Feudal batch tribute specs (story 908) use
  # this to put a vassal's treasury at a controlled figure immediately
  # before the one turn boundary tribute is expected to skim against —
  # standing in for "this turn's gold income" since nothing in the
  # schema distinguishes accrued income from total balance either.
  def handle_call({:set_player_gold_for_test, user_id, gold}, _from, state) do
    player = find_player(state, user_id)
    Repo.update_all(from(p in Player, where: p.id == ^player.id), set: [gold: gold])
    new_state = put_in(state.players[player.id].gold, gold)
    {:reply, :ok, new_state}
  end

  # Test-only: instantly sets `user`'s own world-visible Honor
  # (`Player.honor`) to `honor`, same narrow, documented-bridge status as
  # `:set_player_gold_for_test` above — a direct precondition setter, not
  # a stand-in for any computed RESULT (`Rebellion.Resolution.
  # city_rises?/4` still computes whether a city actually rises from
  # whatever Honor this sets, same as it would from Honor moved by the
  # real `apply_execute_honor_penalty/1` path).
  def handle_call({:set_player_honor_for_test, user_id, honor}, _from, state) do
    player = find_player(state, user_id)
    Repo.update_all(from(p in Player, where: p.id == ^player.id), set: [honor: honor])
    new_state = put_in(state.players[player.id].honor, honor)
    {:reply, :ok, new_state}
  end

  # Test-only: declares `user`'s per-turn gold INCOME — originally
  # story 908's own tribute-spec seam, deliberately SEPARATE from
  # `:set_player_gold_for_test` above (the player's actual treasury
  # BALANCE), since "insufficient gold -> debt"
  # (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Round-5
  # decisions") only makes sense if tribute is computed from an INCOME
  # figure distinct from whatever the treasury already holds. Held
  # purely in ephemeral `WorldServer` state (`state.test_gold_income`,
  # never persisted — there is no DB column for it, the same way a
  # pending heir is tracked in `state.pending_heirs` only).
  #
  # Story 912 shipped a REAL per-turn city gold income mechanic
  # (`Yields.city_gold_income/2`), and `apply_tribute/1`/`apply_bank/1`
  # (below) now compute their own `income_by_player` straight from it
  # every turn boundary — `state.test_gold_income` is no longer read by
  # either phase at all. This handler (and the state it writes) is kept
  # only for narrower test scenarios that still want a hand-declared
  # income independent of any real city; it never mutates `gold`
  # itself, and setting it no longer has any effect on a real turn
  # boundary's tribute/bank math.
  def handle_call({:set_player_gold_income_for_test, user_id, income}, _from, state) do
    player = find_player(state, user_id)
    existing = Map.get(state, :test_gold_income, %{})
    new_state = Map.put(state, :test_gold_income, Map.put(existing, player.id, income))
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

    new_state = %{
      state
      | units: Map.put(state.units, unit_id, %{unit | movement: unit.max_movement})
    }

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
      insert_unit(
        state.world.id,
        nil,
        :barbarian_warrior,
        tile_id,
        stats.hp,
        stats.movement,
        camp_id
      )

    unit_data = unit_map(unit)
    new_state = %{state | units: Map.put(state.units, unit.id, unit_data)}
    {:reply, unit_data, new_state}
  end

  # Dev-only QA control surface (see `BrokenOathsWeb.DevQaController`):
  # place a REAL player-owned unit at `tile_id` with `type`'s starting
  # stats (`Production.unit_stats/1`) — mirrors `:spawn_barbarian_for_test`
  # above, but owned by `player_id` instead of ownerless/camp-tied.
  # Returns the spawned unit's map (`id`, `tile_id`, `hp`, ...).
  def handle_call({:spawn_unit_for_test, player_id, type, tile_id}, _from, state) do
    stats = Production.unit_stats(type)
    {:ok, unit} = insert_unit(state.world.id, player_id, type, tile_id, stats.hp, stats.movement)

    unit_data = unit_map(unit)
    new_state = %{state | units: Map.put(state.units, unit.id, unit_data)}
    {:reply, unit_data, new_state}
  end

  # Dev-only QA control surface: hard-delete `unit_id` outright (a
  # player's unit or a barbarian) — needed to clear a camp's garrison
  # without waiting for combat. Unlike `:clear_camp_warriors_for_test`
  # (camp-scoped, clears every warrior tied to one camp), this targets
  # exactly one unit by id.
  def handle_call({:remove_unit_for_test, unit_id}, _from, state) do
    Repo.delete_all(from(u in Unit, where: u.id == ^unit_id))
    {:reply, :ok, %{state | units: Map.delete(state.units, unit_id)}}
  end

  # Dev-only QA control surface: set `camp_id`'s HP directly, bypassing
  # combat entirely — same narrow, documented-bridge status as
  # `:set_unit_hp_for_test` above.
  def handle_call({:set_camp_hp_for_test, camp_id, hp}, _from, state) do
    Repo.update_all(from(c in Camp, where: c.id == ^camp_id), set: [hp: hp])
    camp = Map.fetch!(state.camps, camp_id)
    new_state = %{state | camps: Map.put(state.camps, camp_id, %{camp | hp: hp})}
    {:reply, :ok, new_state}
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
    {improvement_data, new_state} = persist_complete_improvement_for_test(state, tile_id, kind)
    {:reply, improvement_data, new_state}
  end

  # Test-only: grant `city_id` Copper access (story 911, reworked for
  # QA issue 3e6c124c "Copper availability wrong") by appending a REAL
  # Copper tile's id (found anywhere on the map via `Resources.at/2`)
  # onto that city's own `territory` AND instantly completing a Mine on
  # it (`persist_complete_improvement_for_test/3`, the same bridge
  # `:complete_improvement_for_test` above uses) — same narrow,
  # documented-bridge status as that handler. Copper access is now a
  # PLAYER-wide, MINE-based fact (`Production.player_copper_access?/2`
  # — a bare Copper tile in territory is no longer enough on its own),
  # which most specs have no reason to steer deterministically — a
  # scenario whose SUBJECT is something else entirely (e.g. story 903's
  # "the Spearman outfights a barbarian" combat spec) still needs a
  # real, spawned Bronze Spearman to exist, and story 911 makes that
  # now depend on an access fact no earlier story had to arrange. This
  # sidesteps hunting for (or engineering a founding spot near) a real
  # Copper tile AND standing a worker on it for a real Mine's own
  # `Improvement.duration/1` turns, the way `:relocate_unit_for_test`
  # sidesteps a real march. Refuses with `{:error, :no_copper_on_map}`
  # if the world's own placement rolled no Copper anywhere
  # (vanishingly rare at real gameplay scale, but a possible outcome of
  # any seed-deterministic placement).
  def handle_call({:grant_copper_access_for_test, city_id}, _from, state) do
    case Map.get(state.cities, city_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      city ->
        case Production.find_any_copper_tile(state.world) do
          nil ->
            {:reply, {:error, :no_copper_on_map}, state}

          tile_id ->
            new_territory = Enum.uniq([tile_id | city.territory])
            new_city = %{city | territory: new_territory}
            state_with_territory = %{state | cities: Map.put(state.cities, city_id, new_city)}

            {_improvement_data, new_state} =
              persist_complete_improvement_for_test(state_with_territory, tile_id, :mine)

            {:reply, :ok, new_state}
        end
    end
  end

  # Story 911 rework (QA issue 3e6c124c) — Copper access is now
  # PLAYER-wide: whether `user` currently has at least one completed
  # Mine on a Copper tile anywhere across ALL of their own cities'
  # territory (`Production.player_copper_access?/2`), independent of
  # which city's panel happens to be open. `false` for a `user` with no
  # player in this world yet, the same "absent reads as not unlocked"
  # posture `:player_research` above already has.
  def handle_call({:copper_access?, user}, _from, state) do
    access? =
      case find_player(state, user.id) do
        nil -> false
        player -> Production.player_copper_access?(state, player.id)
      end

    {:reply, access?, state}
  end

  # Story 933 — WORLD-level (no `user`, unlike `:copper_access?` above):
  # `GameLive.CityPanel`'s own Build catalog needs to know whether the
  # Pyramids/Hanging Gardens has already been claimed ANYWHERE in the
  # world, by ANY player, to hide an offered-but-already-gone wonder
  # (`Production.available_items/1`'s own `wonder_offerable?/3`) —
  # information no single player's own `player_research`/`copper_access?`
  # read could ever carry.
  def handle_call({:wonders_claimed}, _from, state) do
    claimed = %{
      pyramids: Production.pyramids_claimed?(state),
      hanging_gardens: Production.hanging_gardens_claimed?(state)
    }

    {:reply, claimed, state}
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
          improvements: maybe_pillage_for_test(state.improvements, tile_id),
          roads: maybe_pillage_for_test(state.roads, tile_id)
      }

      persist_pillage_for_test(state.world.id, tile_id, new_state.improvements[tile_id])
      persist_pillage_for_test(state.world.id, tile_id, new_state.roads[tile_id])

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

    Repo.update_all(from(c in Camp, where: c.id in ^other_camp_ids),
      set: [destroyed_at: destroyed_at]
    )

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
  # player-ownership check `Resolver.attack/4` requires (a barbarian has no
  # owning player/session to drive it through the ordinary "attack"
  # event). Story 893 (barbarian AI) is what will drive this for real;
  # until then this reuses the exact same validate+resolve pipeline
  # `Resolver.attack/4` uses, same narrow, documented-bridge status as
  # `:spawn_barbarian_for_test` above.
  def handle_call({:resolve_barbarian_attack_for_test, attacker_id, target_id}, _from, state) do
    attacker = Map.fetch!(state.units, attacker_id)
    defender = Map.fetch!(state.units, target_id)
    adjacent_tile_ids = Regions.adjacent_tiles(state.world, attacker.tile_id)

    case Resolver.validate_attack(attacker, defender, adjacent_tile_ids) do
      :ok ->
        {result, new_state} = Resolver.resolve_attack(state, attacker, defender)

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

  # Dev-only QA control surface (see `BrokenOathsWeb.DevQaController`):
  # freeze this world's turn clock. Cancels any pending `:tick` timer
  # and persists `paused: true` so a restart mid-pause stays frozen —
  # `catch_up/1` and `handle_info(:tick, ...)` below both check
  # `state.world.paused` before ever advancing. `:advance_turn` (the
  # manual step, right below) is a SEPARATE handler unaffected by this
  # flag — pausing only stops the AUTOMATIC clock.
  def handle_call(:pause_ticks, _from, state) do
    cancel_tick_timer(state)
    persist_paused(state.world.id, true)
    new_state = %{state | world: %{state.world | paused: true}, tick_timer: nil}
    {:reply, :ok, new_state}
  end

  # Resets `turn_started_at` to now — rather than leaving it however
  # stale it went into the pause — so resuming does NOT trigger a big
  # catch-up; the paused interval is deliberately never "owed" time.
  def handle_call(:resume_ticks, _from, state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    persist_resumed(state.world.id, now)
    new_world = %{state.world | paused: false}
    timer = if auto_tick?(), do: schedule_tick(new_world.turn_seconds)

    new_state = %{state | world: new_world, turn_started_at: now, tick_timer: timer}
    {:reply, :ok, new_state}
  end

  def handle_call(:paused?, _from, state), do: {:reply, state.world.paused, state}

  def handle_call(:advance_turn, _from, state) do
    {:reply, :ok, run_tick(state)}
  end

  def handle_call({:abandon, user}, _from, state) do
    new_state = do_abandon(state, user)
    broadcast(new_state.world.id, [:units_changed])
    {:reply, :ok, new_state}
  end

  # Shared by `:complete_improvement_for_test` and
  # `:grant_copper_access_for_test` above: instantly place a COMPLETE
  # improvement of `kind` on `tile_id`, bypassing the real build (a
  # worker standing still for `Improvement.duration/1` real turns)
  # entirely. A scenario whose SUBJECT is what happens to an
  # ALREADY-FINISHED improvement (pillage, story 893 criterion 7556; or
  # — story 911 rework — Copper access) has no structural need to
  # expose a worker to a live, spawning camp for the several real turns
  # a build would otherwise take just to get there.
  defp persist_complete_improvement_for_test(state, tile_id, kind) do
    duration = Improvement.duration(kind)

    improvement =
      case Repo.get_by(Improvement, world_id: state.world.id, tile_id: tile_id, kind: kind) do
        nil ->
          {:ok, improvement} =
            %Improvement{}
            |> Improvement.changeset(%{
              world_id: state.world.id,
              tile_id: tile_id,
              kind: kind,
              progress: duration,
              status: :complete,
              duration: duration,
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
              duration: duration,
              builder_unit_id: nil
            })
            |> Repo.update()

          improvement
      end

    improvement_data = improvement_map(improvement)
    new_state = Improvement.put_improvement(state, kind, tile_id, improvement_data)
    {improvement_data, new_state}
  end

  @impl true
  def handle_info(:tick, state) do
    if state.world.paused do
      {:noreply, %{state | tick_timer: nil}}
    else
      new_state = run_tick(state)
      {:noreply, %{new_state | tick_timer: schedule_tick(new_state.world.turn_seconds)}}
    end
  end

  # -------------------------------------------------------------------
  # Ticking
  # -------------------------------------------------------------------

  defp auto_tick?, do: Application.get_env(:broken_oaths, :game_auto_tick, true)

  defp schedule_tick(turn_seconds), do: Process.send_after(self(), :tick, turn_seconds * 1_000)

  # Story: dev-only QA control surface — a paused world's boot-time
  # dormancy catch-up must NEVER replay missed turns (checked first,
  # independent of `auto_tick?/0`), so a paused QA world stays frozen
  # across a server restart exactly like it was before the restart.
  defp catch_up(state) do
    cond do
      state.world.paused ->
        state

      auto_tick?() ->
        elapsed = DateTime.diff(DateTime.utc_now(), state.turn_started_at, :second)
        run_missed(state, div(elapsed, state.world.turn_seconds))

      true ->
        state
    end
  end

  defp run_missed(state, missed) when missed <= 0, do: state
  defp run_missed(state, missed), do: run_missed(run_tick(state), missed - 1)

  defp cancel_tick_timer(%{tick_timer: ref}) when is_reference(ref), do: Process.cancel_timer(ref)
  defp cancel_tick_timer(_state), do: :ok

  defp persist_paused(world_id, paused?) do
    Repo.update_all(from(w in World, where: w.id == ^world_id), set: [paused: paused?])
  end

  defp persist_resumed(world_id, turn_started_at) do
    Repo.update_all(from(w in World, where: w.id == ^world_id),
      set: [paused: false, turn_started_at: turn_started_at]
    )
  end

  defp run_tick(state) do
    {gated_state, deferred_heirs} = War.defer_gated_heirs(state)
    {ticked, events} = Turn.tick(gated_state)
    ticked = War.restore_gated_heirs(ticked, deferred_heirs)
    {events, ticked} = materialize_spawns(events, ticked)
    # Story 929 — see `Simulation.Turn.RoadBuilder`'s own "Pure core,
    # impure shell" moduledoc section: the ONE real `Repo.insert` a
    # brand-new road needs, deferred out of pure `Turn.tick/1` the same
    # way `materialize_spawns/2` above already defers a freshly-spawned
    # unit's own real id allocation.
    {events, ticked} = materialize_road_starts(events, ticked)
    ticked = %{ticked | turn_started_at: DateTime.utc_now()}
    {ticked, capture_events} = Vassalization.apply_captures(ticked)
    {ticked, tribute_logs} = apply_tribute(ticked)
    ticked = Ledger.apply_oath_strain_drift(ticked)
    ticked = ProtectionPact.apply_protection_pact_ticks(ticked)
    {ticked, upkeep_alerts} = apply_bank(ticked)
    ticked = War.process_rebellion_endings(ticked)
    ticked = reconcile_heir_vassals(ticked, events)
    ticked = Conspiracy.apply_rebellion_pact_strikes(ticked)
    {new_state, discovery_events} = Discovery.apply_discoveries(state, ticked)

    case persist_tick(state, new_state) do
      :ok ->
        persist_gold_logs(tribute_logs)

        broadcast(
          new_state.world.id,
          [:vassals_changed] ++
            events ++
            discovery_events ++
            approach_alert_events(state, new_state) ++ capture_events ++ upkeep_alerts
        )

        new_state

      :stale ->
        # Another WorldServer instance for this world (e.g. a second BEAM
        # node running a mix script — issue 07ee50d1) advanced the turn
        # first. Our write lost the optimistic race; discard in-memory
        # state and resync from the row instead of clobbering it.
        resync(state)
    end
  end

  # -------------------------------------------------------------------
  # Heir succession, reconciled with Rebellion (story 917)
  # -------------------------------------------------------------------

  # Story 917 (criterion 7749) — once a gated heir actually resolves
  # (this tick's own `events`, straight off `Turn.tick/1`, carries the
  # `{:lineage_continued, user_id, _}` that phase fires the instant it
  # does), the realm keeps lordship over exactly `Resolution.
  # heir_retained_vassals/3` — every vassal who did NOT win
  # independence during the leaderless window. Defensive, not
  # load-bearing for the common "never rebelled" case: a `Vassalage`
  # row is keyed on `player_id`, never on the specific Lord UNIT that
  # died, so it already reads `:active` straight through the whole
  # death/heir cycle untouched on its own — this only re-asserts that
  # same intent (a no-op `maybe_revassalize/3` call) for a
  # `:crushed`/`:peace` rebel whose own re-vassalization write might
  # not have landed by this exact tick.
  defp reconcile_heir_vassals(state, events) do
    for {:lineage_continued, user_id, _message} <- events do
      reconcile_heir_vassals_for_user(state, user_id)
    end

    state
  end

  defp reconcile_heir_vassals_for_user(state, user_id) do
    case find_player(state, user_id) do
      nil ->
        :ok

      lord_player ->
        vassal_player_ids = historical_vassal_player_ids(state, lord_player.id)
        rebellions = rebellions_against_player(state, lord_player.id)

        lord_player.id
        |> Resolution.heir_retained_vassals(vassal_player_ids, rebellions)
        |> Enum.each(&Vassalization.maybe_revassalize(state, lord_player.id, &1))
    end
  end

  defp historical_vassal_player_ids(state, lord_player_id) do
    Vassalage
    |> where([v], v.world_id == ^state.world.id and v.lord_player_id == ^lord_player_id)
    |> select([v], v.vassal_player_id)
    |> distinct(true)
    |> Repo.all()
  end

  defp rebellions_against_player(state, former_lord_player_id) do
    Rebellion
    |> where(
      [r],
      r.world_id == ^state.world.id and r.former_lord_player_id == ^former_lord_player_id
    )
    |> Repo.all()
  end

  # Story 895: any foreign unit (barbarian, or per this story's own
  # spec convention, another player's stand-in) newly within
  # `CityDefense.approach_range/0` hexes of a city — pushed straight to
  # that city's owner, same direct-push pattern `:lineage_continued`
  # uses. Edge-triggered against `old_state`: a (city, threat) pair
  # already in range before this operation doesn't re-alert, only one
  # that's in range now and WASN'T a moment ago — otherwise a threat
  # that merely lingers nearby across many boundaries would re-push
  # the identical message every single tick, burying a later, DIFFERENT
  # alert (e.g. "under attack") behind a backlog of stale "approaching"
  # ones in the client's own event queue.
  defp approach_alert_events(old_state, new_state) do
    old_pairs = threat_pairs(old_state)

    for {city_id, _unit_id} <- MapSet.difference(threat_pairs(new_state), old_pairs),
        uniq: true do
      city = Map.fetch!(new_state.cities, city_id)

      {:city_alert, owner_user_id(new_state, city.player_id),
       CityDefense.approach_alert(city.name)}
    end
  end

  defp threat_pairs(state) do
    for {_id, city} <- state.cities,
        threat <- Map.values(state.units),
        threat.player_id != city.player_id,
        CityDefense.approaching?(state.world, city.tile_id, threat.tile_id),
        into: MapSet.new() do
      {city.id, threat.id}
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
        unit = insert_spawned_unit!(acc_state, spawn_event)

        {{:unit_spawned, Map.put(spawn_event, :unit_id, unit.id)},
         %{acc_state | units: Map.put(acc_state.units, unit.id, unit)}}

      other_event, acc_state ->
        {other_event, acc_state}
    end)
  end

  # Story 929 — see `Simulation.Turn.RoadBuilder`'s own "Pure core,
  # impure shell" moduledoc: the ONE real `Repo.insert` a brand-new
  # road needs, deferred out of pure `Turn.tick/1` the exact same way
  # `materialize_spawns/2` above defers a freshly-spawned unit's own
  # real id allocation. Every `{:road_start_needed, ...}` event is
  # purely internal plumbing — dropped here (mapped to `nil`, filtered
  # out below) rather than passed through, unlike `materialize_spawns/2`'s
  # own `{:unit_spawned, ...}` (which a client DOES care about).
  defp materialize_road_starts(events, state) do
    {mapped, new_state} =
      Enum.map_reduce(events, state, fn
        {:road_start_needed, tile_id, unit_id}, acc_state ->
          {nil, materialize_road_start(acc_state, tile_id, unit_id)}

        other_event, acc_state ->
          {other_event, acc_state}
      end)

    {Enum.reject(mapped, &is_nil/1), new_state}
  end

  # The worker that requested this segment may have died between
  # `RoadBuilder.resolve/1`'s own check and here — nothing later in
  # `Turn.tick/1`'s own pipeline kills a unit, but `Repo`-materializing
  # against a unit id that's no longer in `state.units` at all would
  # crash `Improvement.ensure_building/3`'s own `unit.player_id` read,
  # so this is the same defensive "shouldn't happen, but don't crash
  # the whole tick over it" posture the rest of this module already
  # takes for a road-to order's own tick-time seams.
  defp materialize_road_start(state, _tile_id, unit_id) do
    case Map.get(state.units, unit_id) do
      nil ->
        state

      unit ->
        case Improvement.ensure_building(state, unit, :road) do
          {:ok, new_state} -> new_state
          {:error, _reason} -> state
        end
    end
  end

  defp insert_spawned_unit!(state, %{player_id: player_id, type: type, tile_id: tile_id} = event) do
    stats = Production.unit_stats(type)
    camp_id = Map.get(event, :camp_id)
    charges = worker_charges(state, player_id, type)

    {:ok, unit} =
      insert_unit(state.world.id, player_id, type, tile_id, stats.hp, stats.movement, camp_id, charges)

    unit_map(unit)
  end

  # Story 933 — the Pyramids' own Civ 6 "+1 Builder charge": a Worker
  # spawned while its owner holds the Pyramids (ANY of their own
  # cities — `Buildings.player_has?/3`, the same player-wide read
  # `Production.player_copper_access?/2` already established for
  # Copper) starts with 4 charges instead of the schema's own default
  # of 3. Reads `state.cities` as handed in — for the Pyramids' OWN
  # free-Worker spawn event this is already the POST-completion state
  # (`Production.resolve_completions/1`'s own city update runs before
  # its `spawn_event` is ever returned), so that very first Worker
  # already enjoys the bonus its own wonder just granted. Every other
  # unit type (and a Worker for a Pyramids-less owner) gets `nil`
  # here, which leaves `insert_unit/8`'s own `charges` arg — and, in
  # turn, `Unit.changeset/2`'s struct default (3) — untouched.
  defp worker_charges(state, player_id, :worker) do
    if Buildings.player_has?(Map.values(state.cities), player_id, :pyramids), do: 4, else: nil
  end

  defp worker_charges(_state, _player_id, _type), do: nil

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
      {player, units, explored, player_research} = persist_join!(state, user, spawn)

      new_state = %{
        state
        | players: Map.put(state.players, player.id, player),
          units: Enum.reduce(units, state.units, &Map.put(&2, &1.id, &1)),
          explored: Map.put(state.explored, player.id, explored),
          player_research: Map.put(state.player_research, player.id, player_research)
      }

      {:ok, player, new_state}
    end
  end

  defp check_membership_cap(user) do
    count = Repo.aggregate(from(p in Player, where: p.user_id == ^user.id), :count)
    if count >= 3, do: {:error, :membership_limit}, else: :ok
  end

  # A region counts as taken if a player HOMES there (their spawn region) OR
  # has spilled a city into it. Folding in city regions means a new player is
  # never dropped into settled territory just because that region wasn't
  # someone's original spawn, and a carved-up world reports full on real
  # occupancy rather than a raw home-region count. Used by both the live spawn
  # placement and `world_full?`.
  defp taken_region_ids(state) do
    home_regions = state.players |> Map.values() |> Enum.map(& &1.region_id)

    city_regions =
      for {_id, city} <- state.cities,
          rid = Regions.region_of(state.world, city.tile_id),
          not is_nil(rid),
          do: rid

    Enum.uniq(home_regions ++ city_regions)
  end

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

        {:ok, player_research} =
          %PlayerResearch{}
          |> PlayerResearch.changeset(%{world_id: state.world.id, player_id: player.id})
          |> Repo.insert()

        {player_map(player), [unit_map(lord), unit_map(settler)], explored,
         player_research_map(player_research)}
      end)

    result
  end

  defp insert_unit(world_id, player_id, type, tile_id, hp, movement, camp_id \\ nil, charges \\ nil) do
    attrs =
      %{
        world_id: world_id,
        player_id: player_id,
        camp_id: camp_id,
        type: type,
        tile_id: tile_id,
        hp: hp,
        max_hp: hp,
        movement: movement,
        max_movement: movement
      }
      |> maybe_put_charges(charges)

    %Unit{}
    |> Unit.changeset(attrs)
    |> Repo.insert()
  end

  # `charges` only ever OVERRIDES `Unit.changeset/2`'s own struct
  # default (3) — story 933's Pyramids bonus (`worker_charges/3`
  # above) is the one caller that ever passes a real value; every
  # other `insert_unit/8` call site passes `nil` (its own default) and
  # gets the ordinary 3.
  defp maybe_put_charges(attrs, nil), do: attrs
  defp maybe_put_charges(attrs, charges), do: Map.put(attrs, :charges, charges)

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
  # Queue move (stories 875/899/919) — the "queue_move" `handle_call` is
  # a thin delegation into `BrokenOaths.Units.Unit.queue_move/4`
  # (`.code_my_spec/knowledge/genserver_decomposition.md`), which now
  # owns `do_queue_move/4`, `occupied_by_own?/4`, `field_stack_room?/2`,
  # `persist_order!/2`, `bfs_path/3`, and `bfs_loop/5` — all public
  # (pragdave decomposition, slice 6) since `BrokenOaths.Game.
  # Stewardship`'s own emergency-defense move now calls
  # `Unit.bfs_path/3`/`Unit.persist_order!/2` directly rather than
  # WorldServer keeping a second, duplicate copy of either.
  # -------------------------------------------------------------------

  # -------------------------------------------------------------------
  # Attack (story 891/893/896/899/914) — the "attack" `handle_call` is a
  # thin delegation into `BrokenOaths.Combat.Resolver.attack/4`
  # (`.code_my_spec/knowledge/genserver_decomposition.md`).
  # -------------------------------------------------------------------

  # -------------------------------------------------------------------
  # Camp assault (story 894) — the "attack_camp" `handle_call` is a thin
  # delegation into `BrokenOaths.Combat.Camps.attack_camp/4`
  # (`.code_my_spec/knowledge/genserver_decomposition.md`).
  # -------------------------------------------------------------------

  # -------------------------------------------------------------------
  # City assault (story 895/906) — the "attack_city"/"resolve_garrison_fate"
  # `handle_call`s are thin delegations into `BrokenOaths.Combat.Siege`
  # (`.code_my_spec/knowledge/genserver_decomposition.md`).
  # -------------------------------------------------------------------

  defp owner_user_id(state, player_id), do: Map.fetch!(state.players, player_id).user_id

  # -------------------------------------------------------------------
  # Capture & Vassalization (stories 906/907) — the capture/occupy ->
  # swear-fealty flow is a thin delegation into
  # `BrokenOaths.Feudal.Vassalization.apply_captures/1`
  # (`.code_my_spec/knowledge/genserver_decomposition.md`).
  # -------------------------------------------------------------------

  # -------------------------------------------------------------------
  # Tribute (story 908)
  # -------------------------------------------------------------------

  # Runs every turn boundary, alongside every other tick phase — reads
  # every ACTIVE vassalage in this world fresh from `Repo` (vassalage
  # itself is world-membership-scoped coordination state, not
  # tick-state, the same status `list_alliances/2` already documents
  # for `Alliance`) and each vassal's own gold INCOME this turn from
  # `gold_income_by_player/1` (story 912): every REAL city gold income
  # (`Yields.city_gold_income/2`) summed per owning player, off THIS
  # tick's own `state.cities` — the test-only `state.test_gold_income`
  # seam (`:set_player_gold_income_for_test`) is no longer this phase's
  # basis at all; it stays wired for narrower test scenarios that still
  # call it directly, but the turn-boundary tribute/bank phases never
  # read it again. `Tribute.collect_all/5` moves gold in-memory; the
  # caller (`run_tick/1`) is responsible for persisting the resulting
  # `state.players` diff (via `persist_tick/2`, same as every other
  # in-tick gold change) and the returned `GoldLog` rows
  # (`persist_gold_logs/1`, immediately after). A no-op while `Game.
  # feudal_enabled?/0` reads `false` — belt-and-suspenders alongside
  # `Vassalization.apply_captures/1`'s own gate, which already keeps
  # `active_vassalages/1` from ever finding a row to collect against.
  defp apply_tribute(state) do
    if Game.feudal_enabled?() do
      case active_vassalages(state.world.id) do
        [] ->
          {state, []}

        vassalages ->
          income_by_player = gold_income_by_player(state)

          {new_players, logs} =
            Tribute.collect_all(
              vassalages,
              state.players,
              income_by_player,
              state.world.id,
              state.turn
            )

          {%{state | players: new_players}, logs}
      end
    else
      {state, []}
    end
  end

  defp active_vassalages(world_id) do
    Vassalage
    |> where([v], v.world_id == ^world_id and v.status == :active)
    |> Repo.all()
  end

  # -------------------------------------------------------------------
  # Protection Pact (story 914)
  # -------------------------------------------------------------------

  # `state.protection_calls` (`%{vassal_player_id => ProtectionPact.call()}`)
  # and `state.protection_honored_counts` (`%{vassal_player_id =>
  # non_neg_integer()}`) are purely in-memory tick-state — same "no
  # restart survival needed" status `state.camp_contributions` already
  # has (`ProtectionPact`'s own moduledoc: "nothing about it needs to
  # survive a WorldServer restart any more than an in-flight combat
  # resolution does") — never initialized in `load_state/1`, always
  # read through these two accessors' own `Map.get(state, key, %{})`
  # default.
  defp protection_calls(state), do: Map.get(state, :protection_calls, %{})
  defp protection_honored_counts(state), do: Map.get(state, :protection_honored_counts, %{})

  # The lord/vassal-facing read both `format_vassal/2` and
  # `vassal_status/2` share: `nil` while no call is active, or a plain
  # `%{window_remaining:}` otherwise — deliberately narrower than the
  # full `ProtectionPact.call()` map (the UI only ever needs the
  # countdown; `attacker_unit_id` is this module's own bookkeeping).
  defp protection_call_view(state, vassal_player_id) do
    case Map.get(protection_calls(state), vassal_player_id) do
      nil -> nil
      call -> %{window_remaining: call.window_remaining}
    end
  end

  # Story 912: every player's own REAL per-turn gold income —
  # `Yields.city_gold_income/2` per city, grouped by `player_id` and
  # summed, off THIS tick's own `state.cities`/`state.world` (never a
  # stale/cached figure — a city's income is recomputed from its
  # CURRENT size/worked_tiles every boundary, same "always live" rule
  # `Yields.worked_yields/3` already keeps for food/production). A
  # player who owns no city at all simply has no entry here — both
  # `apply_tribute/1` (via `Map.get(income_by_player, id, 0)`) and
  # `apply_bank/1` (which only ever iterates entries actually present)
  # already treat a missing player the same as an explicit `0`.
  defp gold_income_by_player(state) do
    state.cities
    |> Map.values()
    |> Enum.group_by(& &1.player_id)
    |> Map.new(fn {player_id, cities} ->
      income = cities |> Enum.map(&Yields.city_gold_income(&1, state.world)) |> Enum.sum()
      {player_id, income}
    end)
  end

  defp persist_gold_logs([]), do: :ok

  defp persist_gold_logs(logs) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      Enum.map(logs, &Map.merge(&1, %{inserted_at: now, updated_at: now}))

    Repo.insert_all(GoldLog, rows)
    :ok
  end

  # -------------------------------------------------------------------
  # Gold Bank (story 909)
  # -------------------------------------------------------------------

  # Runs every turn boundary, alongside `apply_tribute/1` — settles
  # EVERY player's own per-turn gold income (story 912: every REAL
  # city gold income, `gold_income_by_player/1`, the SAME figure
  # `apply_tribute/1` taxes) NET of upkeep (stories 922/923: every owned
  # unit's/city's own gold maintenance) via `Bank.apply_upkeep/2`
  # (pragdave decomposition, slice 6: the settle-and-write iteration
  # itself moved home to `Bank`; `gold_income_by_player/1` stays here
  # since `apply_tribute/1`'s own tribute phase reads the exact same
  # figure). Returns `{state, alert_events}` now — `alert_events` one
  # `{:city_alert, user_id, message}` per player who got a unit
  # disbanded for missing upkeep this tick, threaded into `run_tick/1`'s
  # own end-of-tick broadcast alongside every other tick alert. A no-op
  # (empty alert list) while `Game.feudal_enabled?/0` reads `false` —
  # same belt-and-suspenders status `Vassalization.apply_captures/1`/
  # `apply_tribute/1` already carry, so prod's own gold economy (bounty
  # kills, camp rewards — the only things that ever moved `gold` before
  # this story) stays exactly as it was until the flag flips on for
  # real (v0.3.0).
  #
  # Timer inversion — the income/upkeep sweep is part of the ECONOMY, not
  # the fast tick, so it's gated on the SAME `economy?` formula
  # `BrokenOaths.Simulation.Turn.tick/1`'s own `economy_tick?/2` uses
  # (recomputed here, off `state.turn`/`state.world`, since `run_tick/1`
  # calls this well after `tick/1` already returned — see that module's
  # own "Timer inversion" doc for why a matching recompute is fine here).
  defp apply_bank(state) do
    if Game.feudal_enabled?() and economy_tick?(state) do
      income_by_player = gold_income_by_player(state)
      Bank.apply_upkeep(state, income_by_player)
    else
      {state, []}
    end
  end

  defp economy_tick?(state) do
    economy_turns = Map.get(state.world, :economy_turns, 10) || 10
    rem(state.turn, economy_turns) == 0
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

  # -------------------------------------------------------------------
  # Alliances (story 901) — `:alliances`'s own `handle_call` is a thin
  # delegation into `BrokenOaths.Feudal.Stewardship.list_alliances/2`
  # (pragdave decomposition, slice 6 — moved alongside `steward_view/2`,
  # the payload `format_alliance/3` itself carries).
  # -------------------------------------------------------------------

  # -------------------------------------------------------------------
  # Vassalage / Tribute (stories 907/908)
  # -------------------------------------------------------------------

  # The lord's own "Vassals" list — every ACTIVE vassalage they hold,
  # each row carrying the ONE forward-looking field this batch actually
  # surfaces end-to-end (tribute rate), Oath Strain (story 908's own
  # refusal consequence), and the vassal's own latest levy status.
  # Deliberately never reads `hidden_agenda` — the Oath screen's own
  # pick stays secret from the lord (`BrokenOathsSpex.Story907.
  # Criterion7668Spex`).
  defp vassals(state, user) do
    case find_player(state, user.id) do
      nil ->
        []

      player ->
        Vassalage
        |> where(
          [v],
          v.world_id == ^state.world.id and v.lord_player_id == ^player.id and
            v.status == :active
        )
        |> Repo.all()
        |> Enum.map(&format_vassal(state, &1))
    end
  end

  defp format_vassal(state, vassalage) do
    vassal_player = Map.fetch!(state.players, vassalage.vassal_player_id)
    vassal_user = Users.get_user!(vassal_player.user_id)
    online? = Presence.online?(state.world, %{id: vassal_user.id})

    %{
      vassal_user_id: vassal_user.id,
      display_name: User.display_name(vassal_user),
      tribute_rate: vassalage.tribute_rate,
      oath_strain: vassalage.oath_strain,
      levy_status:
        Levy.status_for(state.world.id, vassalage.lord_player_id, vassalage.vassal_player_id),
      # Story 910: whether this vassal is currently reachable to steward
      # — `GameLive.VassalsPanel`'s own Steward affordance only offers
      # itself against an OFFLINE household member.
      online?: online?,
      # QA issue bd93cc0a: the production-stewardship + emergency-defend
      # click-through's own data source — `nil` while online (nothing to
      # steward yet), `Stewardship.steward_view/2`'s real payload once
      # offline.
      steward: if(online?, do: nil, else: Stewardship.steward_view(state, vassal_player)),
      # Story 914: `nil` while no Protection Pact call is active for
      # this vassal, `%{window_remaining:}` otherwise.
      protection_call: protection_call_view(state, vassalage.vassal_player_id),
      # Story 914 (criterion 7730): a running count of calls honored FOR
      # this vassal — never resets, survives the underlying call itself
      # being resolved and removed from `state.protection_calls`.
      protection_honored_count:
        Map.get(protection_honored_counts(state), vassalage.vassal_player_id, 0)
    }
  end

  # The vassal's own read of their oath: who they're sworn to, the
  # current rate ("the vassal sees the rate and feels the pressure"),
  # whether the Oath screen is still owed (`Vassalization.
  # agenda_pending?/1`), and their own latest levy status. `nil` for a
  # free player — no Oath screen, no "Sworn to" badge.
  defp vassal_status(state, user) do
    case find_player(state, user.id) do
      nil ->
        nil

      player ->
        case active_vassalage_for_vassal(state, player.id) do
          nil ->
            nil

          vassalage ->
            lord_player = Map.fetch!(state.players, vassalage.lord_player_id)
            lord_user = Users.get_user!(lord_player.user_id)

            %{
              lord_user_id: lord_user.id,
              lord_name: User.display_name(lord_user),
              tribute_rate: vassalage.tribute_rate,
              oath_strain: vassalage.oath_strain,
              agenda_pending?: Vassalization.agenda_pending?(vassalage),
              levy_status: Levy.status_for(state.world.id, vassalage.lord_player_id, player.id),
              # Story 914: this vassal's OWN read of their own active
              # Protection Pact call, same `nil | %{window_remaining:}`
              # shape `format_vassal/2` gives the lord.
              protection_call: protection_call_view(state, player.id),
              # Story 917: whether THIS lord's own Lord unit is
              # currently dead — the vassal's own "seize the moment"
              # trigger (`GameLive.Play`'s own `seize-the-moment-prompt`).
              lord_fallen?: not lord_unit_alive?(state, lord_player.id)
            }
        end
    end
  end

  # Story 917: whether `lord_user_id` currently has ANY living Lord
  # unit on the board — a player with no `Player` row at all (never
  # joined, or a stale/foreign id) reads as NOT fallen (`false`) rather
  # than crashing, mirroring every other defensive `find_player/2`
  # lookup in this module.
  defp lord_fallen?(state, lord_user_id) do
    case find_player(state, lord_user_id) do
      nil -> false
      lord_player -> not lord_unit_alive?(state, lord_player.id)
    end
  end

  defp lord_unit_alive?(state, lord_player_id) do
    Enum.any?(state.units, fn {_id, unit} ->
      unit.type == :lord and unit.player_id == lord_player_id
    end)
  end

  defp do_choose_hidden_agenda(state, user, agenda) do
    with {:ok, player} <- fetch_player(state, user.id),
         {:ok, vassalage} <- fetch_vassalage_as_vassal(state, player.id) do
      Vassalization.choose_agenda_changeset(vassalage, agenda) |> Repo.update()
    end
  end

  defp do_set_tribute_rate(state, user, vassal_user_id, rate) do
    with {:ok, lord_player} <- fetch_player(state, user.id),
         {:ok, vassal_player} <- fetch_player(state, vassal_user_id),
         {:ok, vassalage} <- fetch_vassalage(state, lord_player.id, vassal_player.id) do
      Tribute.set_rate_changeset(vassalage, rate) |> Repo.update()
    end
  end

  # `:resolve_garrison_fate`'s own `handle_call` is a thin delegation
  # into `BrokenOaths.Combat.Siege.apply_garrison_fate/4`
  # (`.code_my_spec/knowledge/genserver_decomposition.md`).
  #
  # `:issue_levy`/`:answer_levy`/`:refuse_levy`'s own `handle_call`s are
  # thin delegations into `BrokenOaths.Feudal.Levy.issue/5`/`answer/3`/
  # `refuse/3` (pragdave decomposition, slice 6). `levy_status_for/3`
  # moved home alongside them as `Levy.status_for/3` — `format_vassal/2`
  # and `vassal_status/2` above call it directly.

  defp active_vassalage_for_vassal(state, vassal_player_id) do
    Repo.get_by(Vassalage,
      world_id: state.world.id,
      vassal_player_id: vassal_player_id,
      status: :active
    )
  end

  defp fetch_vassalage(state, lord_player_id, vassal_player_id) do
    case Repo.get_by(Vassalage,
           world_id: state.world.id,
           lord_player_id: lord_player_id,
           vassal_player_id: vassal_player_id,
           status: :active
         ) do
      nil -> {:error, :not_a_vassal}
      vassalage -> {:ok, vassalage}
    end
  end

  defp fetch_vassalage_as_vassal(state, vassal_player_id) do
    case active_vassalage_for_vassal(state, vassal_player_id) do
      nil -> {:error, :not_a_vassal}
      vassalage -> {:ok, vassalage}
    end
  end

  # -------------------------------------------------------------------
  # Rebellion (stories 915/919)
  # -------------------------------------------------------------------

  # `user`'s own active-or-most-recent Rebellion as REBEL — `nil` if
  # they've never raised one. Reads the SAME settled row forever once a
  # rebellion ends (`Rebellion.changeset/2`'s own once-only transition
  # guard).
  defp rebellion_status(state, user) do
    case find_player(state, user.id) do
      nil ->
        nil

      player ->
        Rebellion
        |> where([r], r.world_id == ^state.world.id and r.rebel_player_id == ^player.id)
        |> order_by([r], desc: r.id)
        |> limit(1)
        |> Repo.one()
        |> case do
          nil -> nil
          rebellion -> format_rebellion(state, rebellion)
        end
    end
  end

  # Every Rebellion (active or ended) raised against `user` as the
  # FORMER LORD, freshest first.
  defp rebellions_as_lord(state, user) do
    case find_player(state, user.id) do
      nil ->
        []

      player ->
        Rebellion
        |> where([r], r.world_id == ^state.world.id and r.former_lord_player_id == ^player.id)
        |> order_by([r], desc: r.id)
        |> Repo.all()
        |> Enum.map(&format_rebellion(state, &1))
    end
  end

  defp format_rebellion(state, rebellion) do
    rebel_player = Map.get(state.players, rebellion.rebel_player_id)
    lord_player = Map.get(state.players, rebellion.former_lord_player_id)
    rebel_user = rebel_player && Users.get_user!(rebel_player.user_id)
    lord_user = lord_player && Users.get_user!(lord_player.user_id)

    %{
      id: rebellion.id,
      status: rebellion.status,
      rebel_user_id: rebel_user && rebel_user.id,
      rebel_name: rebel_user && User.display_name(rebel_user),
      former_lord_user_id: lord_user && lord_user.id,
      former_lord_name: lord_user && User.display_name(lord_user),
      started_turn: rebellion.started_turn,
      army_size: rebellion.army_size,
      risen_city_ids: rebellion.risen_city_ids,
      loyal_city_ids: rebellion.loyal_city_ids,
      peace_outcome: rebellion.peace_outcome,
      reparations_gold: rebellion.reparations_gold,
      pending_peace_offer: format_pending_offer(state, rebellion)
    }
  end

  # Story 919, criterion 7754 — surfaces a still-pending peace offer
  # (`nil` while none is open) so either side's own view can render an
  # Accept/Reject affordance naming who offered what.
  defp format_pending_offer(state, rebellion) do
    case Map.get(peace_offers(state), rebellion.id) do
      nil ->
        nil

      offer ->
        offering_player = Map.get(state.players, offer.offered_by_player_id)
        offering_user = offering_player && Users.get_user!(offering_player.user_id)

        %{
          offered_by_user_id: offering_user && offering_user.id,
          offered_by_name: offering_user && User.display_name(offering_user),
          outcome: offer.outcome,
          reparations_gold: offer.reparations_gold
        }
    end
  end

  defp peace_offers(state), do: Map.get(state, :peace_offers, %{})

  # -------------------------------------------------------------------
  # Research (story 902)
  # -------------------------------------------------------------------

  defp player_research_summary(state, user) do
    case find_player(state, user.id) do
      nil ->
        nil

      player ->
        pr = player_research_for(state, player.id)
        cities = for {_id, city} <- state.cities, city.player_id == player.id, do: city

        %{
          completed_techs: pr.completed_techs,
          current_research: pr.current_research,
          banked_science: pr.banked_science,
          progress: Research.progress(pr),
          science_per_turn: Research.science_per_turn(cities)
        }
    end
  end

  # Story 904: `barbarians_killed`/`camps_destroyed` ride the player
  # row directly (see `Player`'s own moduledoc) — no derivation needed,
  # unlike `player_cities/2`'s "just count them" story for cities
  # founded.
  defp player_stats(state, user) do
    case find_player(state, user.id) do
      nil ->
        nil

      player ->
        %{barbarians_killed: player.barbarians_killed, camps_destroyed: player.camps_destroyed}
    end
  end

  # Upserts (QA issue 957f4e55) rather than a blind `update_all` — a
  # player who joined before story 902 (or whose row is otherwise
  # missing) gets a row created here instead of the write silently
  # no-opping. `load_state/1`'s `backfill_player_research/3` already
  # covers the common case at boot; this is the defensive backstop for
  # any row still missing when a write actually happens.
  defp do_set_research(state, user, tech) do
    with {:ok, player} <- fetch_player(state, user.id),
         {:ok, updated} <- Research.set_research(player_research_for(state, player.id), tech) do
      upsert_player_research(state.world.id, player.id, updated)

      {:ok, %{state | player_research: Map.put(state.player_research, player.id, updated)}}
    end
  end

  # A player who joined before this state key existed (or whose row is
  # somehow missing) is treated as `Research.new/0` — same defensive
  # fallback `Turn.accrue_science/1` uses.
  defp player_research_for(state, player_id),
    do: Map.get(state.player_research, player_id, Research.new())

  defp fetch_player(state, user_id) do
    case find_player(state, user_id) do
      nil -> {:error, :not_a_player}
      player -> {:ok, player}
    end
  end

  # -------------------------------------------------------------------
  # Coordinated Rebellion — Pact of Broken Oaths (story 916)
  # -------------------------------------------------------------------

  # `user`'s own warning that a plot against them has been informed on
  # (criterion 7741) — `nil` while no member of any of the lord's own
  # `:forming` pacts has informed. Never carries the informer's own
  # identity (`RebellionPact.informer/1` finds the row; this only ever
  # surfaces the strike turn).
  defp pact_informed_notice(state, user) do
    case find_player(state, user.id) do
      nil -> nil
      player -> informed_forming_pact(state, player.id)
    end
  end

  defp informed_forming_pact(state, lord_player_id) do
    RebellionPact
    |> where(
      [p],
      p.world_id == ^state.world.id and p.lord_player_id == ^lord_player_id and
        p.status == :forming
    )
    |> Repo.all()
    |> Repo.preload(:members)
    |> Enum.find_value(&informed_notice/1)
  end

  defp informed_notice(pact) do
    if RebellionPact.informer(pact), do: %{strike_turn: pact.strike_turn}
  end

  # -------------------------------------------------------------------
  # Gold Bank (story 909) / Feudal Stewardship (story 910)
  # -------------------------------------------------------------------

  # Pragdave decomposition, slice 6: `:bank`/`:collect_bank`/
  # `:upgrade_bank` (`BrokenOaths.Feudal.Bank`) and every
  # `:steward_*`/`:alliances`/`:steward_log` `handle_call`
  # (`BrokenOaths.Feudal.Stewardship`) are thin delegations into their
  # owning domain model
  # (`.code_my_spec/knowledge/genserver_decomposition.md`).

  defp honor_of(nil), do: 0
  defp honor_of(player), do: player.honor

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

          persist_heir_changes(
            Map.get(old_state, :pending_heirs, %{}),
            Map.get(new_state, :pending_heirs, %{})
          )

          persist_improvement_changes(
            new_state.world.id,
            old_state.improvements,
            new_state.improvements
          )

          persist_improvement_changes(
            new_state.world.id,
            old_state.roads,
            new_state.roads
          )

          persist_cleared_feature_changes(
            new_state.world.id,
            Map.get(old_state, :cleared_features, MapSet.new()),
            Map.get(new_state, :cleared_features, MapSet.new())
          )

          persist_known_player_changes(
            new_state.world.id,
            Map.get(old_state, :known_players, MapSet.new()),
            Map.get(new_state, :known_players, MapSet.new())
          )

          persist_player_research_changes(
            new_state.world.id,
            Map.get(old_state, :player_research, %{}),
            Map.get(new_state, :player_research, %{})
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
  # destroyed this delta (combat, or a worker expending its last build
  # charge — story 882 playtest update, issue 1caa87e9, see
  # `BrokenOaths.Simulation.Turn`'s "Improvement progress" section — outside
  # of `found_city`'s own dedicated delete) — swept from the DB here
  # rather than left as a zombie row. `found_city` still deletes its
  # consumed settler immediately, in its own transaction, same as
  # before; this only ever catches removals this generic diff would
  # otherwise silently miss.
  defp persist_unit_changes(old_units, new_units) do
    removed_ids = Map.keys(old_units) -- Map.keys(new_units)
    if removed_ids != [], do: Repo.delete_all(from(u in Unit, where: u.id in ^removed_ids))

    for {id, unit} <- new_units, Map.get(old_units, id) != unit do
      Repo.update_all(from(u in Unit, where: u.id == ^id),
        set: [
          tile_id: unit.tile_id,
          movement: unit.movement,
          hp: unit.hp,
          charges: Map.get(unit, :charges, 3),
          # Story 920 — the Fortify stance's own turns-held counter;
          # `Map.get/3` default matches the schema's own `0` (see
          # `Units.Unit`'s own "fortified_turns" moduledoc paragraph).
          fortified_turns: Map.get(unit, :fortified_turns, 0)
        ]
      )
    end
  end

  # Newly founded/renamed/reassigned cities are already persisted
  # immediately by their own command (see "Found city"/"Worked tiles"/
  # "Rename city" above) — this only ever catches what the TICK itself
  # (or, since story 895, `Siege.attack_city/4`'s own immediate
  # resolution) changes: size, food, territory (growth), worked_tiles
  # (a settler's pop cost, or a pillage, un-working a tile), `hp`/
  # `production_halted_until` (city combat — see `CityDefense`),
  # (story 902) `has_granary` — `Production.complete/3`'s own Granary
  # branch flips it the same tick a Granary item finishes banking —
  # (story 930) `buildings` — the same `Production.complete/3`'s own
  # `@passive_buildings` branch, for the other four buildings — and
  # (story 906) `occupied_by_player_id`, set the instant `Siege.
  # materialize_captures/2` captures a broken city.
  defp persist_city_changes(old_cities, new_cities) do
    for {id, city} <- new_cities, Map.get(old_cities, id) != city do
      Repo.update_all(from(c in City, where: c.id == ^id),
        set: [
          size: city.size,
          food: city.food,
          territory: city.territory,
          worked_tiles: city.worked_tiles,
          hp: city.hp,
          production_halted_until: city.production_halted_until,
          has_granary: Map.get(city, :has_granary, false),
          buildings: Map.get(city, :buildings, []),
          occupied_by_player_id: Map.get(city, :occupied_by_player_id)
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

  # New camps are persisted immediately at founding (see `City`'s own
  # `spawn_wilderness_camps/3`) — this only reconciles what the tick
  # itself advances: `spawn_counter` (every camp, every tick), `hp`
  # (story 894's camp assault), and `destroyed_at` (also story 894 — a
  # camp reduced to 0 HP, both via `BrokenOaths.Combat.Camps.attack_camp/4`
  # immediately and
  # via `Turn`'s barbarian AI loop pillaging nothing of the camp itself,
  # only ever set here).
  defp persist_camp_changes(old_camps, new_camps) do
    for {id, camp} <- new_camps, Map.get(old_camps, id) != camp do
      Repo.update_all(from(c in Camp, where: c.id == ^id),
        set: [hp: camp.hp, spawn_counter: camp.spawn_counter, destroyed_at: camp.destroyed_at]
      )
    end
  end

  # Gold was the only mutable field on a player once joined — bounty
  # kills (story 893, criterion 7557) and camp-destroy rewards (story
  # 894, criterion 7560) were the first things that ever changed it
  # after `spawn_new_player/2`'s initial 50. Story 904 adds two more,
  # riding the same diff-and-persist path: `barbarians_killed` (bumped
  # alongside every bounty payout) and `camps_destroyed` (bumped
  # alongside every reward-share payout `BrokenOaths.Combat.Camps.
  # attack_camp/4` triggers).
  defp persist_player_changes(old_players, new_players) do
    for {id, player} <- new_players, Map.get(old_players, id) != player do
      Repo.update_all(from(p in Player, where: p.id == ^id),
        set: [
          gold: player.gold,
          barbarians_killed: player.barbarians_killed,
          camps_destroyed: player.camps_destroyed,
          banked_gold: player.banked_gold,
          bank_cap: player.bank_cap,
          honor: player.honor
        ]
      )
    end
  end

  # The heir schedule is small and rarely changes — diff both directions
  # so a scheduled arrival is written and a resolved (or superseded) one
  # is cleared (story 896, QA issue 0b7e82cd).
  defp persist_heir_changes(old_heirs, new_heirs) do
    for {id, turn} <- new_heirs, Map.get(old_heirs, id) != turn do
      Repo.update_all(from(p in Player, where: p.id == ^id), set: [heir_arrives_turn: turn])
    end

    for {id, _turn} <- old_heirs, not Map.has_key?(new_heirs, id) do
      Repo.update_all(from(p in Player, where: p.id == ^id), set: [heir_arrives_turn: nil])
    end
  end

  # Starting/attaching an improvement is persisted immediately (see
  # "Improvements" above) — this only reconciles what the tick itself
  # advances: progress, completion, and a builder walking away. Called
  # once for `state.improvements` and once for `state.roads` (QA issue
  # 5656770d) — the `kind` filter is required now that a single tile
  # can carry a row in EACH collection: without it, this would rewrite
  # every row at `tile_id` (both the yield improvement's AND the
  # Road's) to whichever one changed.
  defp persist_improvement_changes(world_id, old_improvements, new_improvements) do
    for {tile_id, improvement} <- new_improvements,
        Map.get(old_improvements, tile_id) != improvement do
      Repo.update_all(
        from(i in Improvement,
          where: i.world_id == ^world_id and i.tile_id == ^tile_id and i.kind == ^improvement.kind
        ),
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
      nil ->
        improvements

      %{status: :complete} = improvement ->
        Map.put(improvements, tile_id, Improvement.pillage(improvement))

      improvement ->
        Map.put(improvements, tile_id, improvement)
    end
  end

  defp persist_pillage_for_test(_world_id, _tile_id, nil), do: :ok

  defp persist_pillage_for_test(world_id, tile_id, %{status: :pillaged, kind: kind} = pillaged) do
    case Repo.get_by(Improvement, world_id: world_id, tile_id: tile_id, kind: kind) do
      nil ->
        :ok

      existing ->
        existing
        |> Improvement.changeset(%{
          status: pillaged.status,
          progress: pillaged.progress,
          builder_unit_id: nil
        })
        |> Repo.update()

        :ok
    end
  end

  defp persist_pillage_for_test(_world_id, _tile_id, _unchanged), do: :ok

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

  # Story 899: a permanent record once written (`KnownPlayer`'s own
  # doc) — only ever INSERTED, never updated or removed. `on_conflict:
  # :nothing` is the same defensive backstop `Player`'s unique indexes
  # already are for the rest of this module: this WorldServer process
  # is the single serialization point for `state.known_players`, so a
  # genuine duplicate insert should never happen, but a second
  # WorldServer instance for this world racing the same first-contact
  # (see `run_tick/1`'s `:stale` handling) is the one scenario where it
  # could.
  # Story 927 — `state.cleared_features` is a `MapSet`, the same "insert
  # once, never removed" shape `state.known_players` already has (see
  # `BrokenOaths.Worlds.ClearedFeature`'s own moduledoc): only ever
  # grows, so a plain set-difference against the pre-chop snapshot is
  # every new row this tick needs to write. `on_conflict: :nothing`
  # guards the same race `persist_known_player_changes/3` already guards
  # against.
  defp persist_cleared_feature_changes(world_id, old_cleared, new_cleared) do
    for tile_id <- MapSet.difference(new_cleared, old_cleared) do
      %ClearedFeature{}
      |> ClearedFeature.changeset(%{world_id: world_id, tile_id: tile_id})
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:world_id, :tile_id])
    end
  end

  defp persist_known_player_changes(world_id, old_known, new_known) do
    for {viewer_id, discovered_id} <- MapSet.difference(new_known, old_known) do
      %KnownPlayer{}
      |> KnownPlayer.changeset(%{
        world_id: world_id,
        viewer_player_id: viewer_id,
        discovered_player_id: discovered_id
      })
      |> Repo.insert(
        on_conflict: :nothing,
        conflict_target: [:world_id, :viewer_player_id, :discovered_player_id]
      )
    end
  end

  # Story 902: research state is created at join (`persist_join!/3`) or
  # backfilled at boot (`backfill_player_research/3`), but this
  # reconciles what the tick's own science-accrual phase advances
  # (banked science, completion, `current_research` clearing) alongside
  # whatever `do_set_research/3` already wrote immediately outside the
  # tick. Upserts (QA issue 957f4e55) rather than a blind `update_all`
  # so a still-missing row never silently swallows progress.
  defp persist_player_research_changes(world_id, old_player_research, new_player_research) do
    for {player_id, pr} <- new_player_research, Map.get(old_player_research, player_id) != pr do
      upsert_player_research(world_id, player_id, pr)
    end
  end

  # Shared upsert for both write paths above — `on_conflict: :replace`
  # on the mutable fields keeps this a true upsert (insert when the row
  # is missing, update when it isn't) while leaving `world_id`/`player_id`
  # untouched on conflict, the same `{:replace, fields}` shape
  # `BrokenOaths.Integrations.IntegrationRepository.upsert_integration/3`
  # already uses for its own (user_id, provider) upsert.
  defp upsert_player_research(world_id, player_id, pr) do
    %PlayerResearch{}
    |> PlayerResearch.changeset(%{
      world_id: world_id,
      player_id: player_id,
      completed_techs: pr.completed_techs,
      current_research: pr.current_research,
      banked_science: stringify_banked_science(pr.banked_science)
    })
    |> Repo.insert(
      on_conflict: {:replace, [:completed_techs, :current_research, :banked_science]},
      conflict_target: [:world_id, :player_id]
    )
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
    players = load_players(world.id)

    %{
      world: world,
      turn: world.turn,
      turn_started_at: world.turn_started_at || persist_initial_turn_started_at(world),
      units: load_units(world.id),
      orders: load_orders(world.id),
      players: players,
      explored: load_explored(world.id),
      cities: load_cities(world.id),
      improvements: load_improvements(world.id),
      roads: load_roads(world.id),
      # Story 927 — see `BrokenOaths.Worlds.ClearedFeature`'s own
      # moduledoc: the stored delta over the seed-derived terrain a
      # Chop leaves behind, rehydrated as a `MapSet` so
      # `BrokenOaths.Worlds.Regions.terrain/3`'s own `MapSet.member?/2`
      # check is O(1).
      cleared_features: load_cleared_features(world.id),
      camps: load_camps(world.id),
      # Hydrated from game_players.heir_arrives_turn so a restart
      # mid-wait re-derives every pending heir (QA issue 0b7e82cd).
      pending_heirs: pending_heirs_from(players),
      # Story 899: every directional `{viewer_player_id, discovered_player_id}`
      # pair already recorded for this world — the baseline
      # `Discovery.new_contacts/2` diffs each tick's sightings against.
      known_players: load_known_players(world.id),
      # Story 902: one `Research.player_research()` map per player,
      # created at join (`persist_join!/3`) and advanced every tick by
      # `Turn`'s own "science accrual" phase. Backfilled for any player
      # who joined BEFORE story 902 shipped (QA issue 957f4e55) so
      # `do_set_research/3`/`persist_player_research_changes/2` always
      # have a row to upsert through, instead of silently losing
      # progress every restart.
      player_research: backfill_player_research(world, players, load_player_research(world.id))
    }
  end

  # A `game_player_research` row is only ever created at join
  # (`persist_join!/3`) — any player who joined a world BEFORE story
  # 902 shipped has none. Backfilled here with the same defaults
  # `persist_join!/3` itself inserts, mirroring how `pending_heirs_from/1`
  # re-derives its own state from a column that's always present.
  # `on_conflict: :nothing` guards the same race `persist_known_player_changes/3`
  # already guards against: a second WorldServer instance for this world
  # booting concurrently.
  defp backfill_player_research(world, players, player_research) do
    Enum.reduce(players, player_research, fn {player_id, _player}, acc ->
      if Map.has_key?(acc, player_id) do
        acc
      else
        {:ok, pr} =
          %PlayerResearch{}
          |> PlayerResearch.changeset(%{world_id: world.id, player_id: player_id})
          |> Repo.insert(on_conflict: :nothing, conflict_target: [:world_id, :player_id])

        Map.put(acc, player_id, player_research_map(pr))
      end
    end)
  end

  defp pending_heirs_from(players) do
    for {id, %{heir_arrives_turn: turn}} <- players, not is_nil(turn), into: %{}, do: {id, turn}
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
    |> Map.new(fn o ->
      {o.unit_id,
       %{kind: o.kind, path: o.path, status: o.status, hp_at_issue: o.hp_at_issue}}
    end)
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

  # QA issue 5656770d — a Road lives in its own in-memory map
  # (`state.roads`), independent of the tile's yield improvement
  # (Farm/Mine/Pasture, `state.improvements`) — see `Improvement`'s own
  # moduledoc. Excluding `:road` here (rather than a single
  # `Map.new(&{&1.tile_id, ...})` keyed only by `tile_id`) is required
  # for correctness, not just organization: once a tile can carry BOTH
  # a yield improvement and a Road row, a single tile-keyed `Map.new/2`
  # would silently drop one of the two same-tile rows.
  defp load_improvements(world_id) do
    from(i in Improvement, where: i.world_id == ^world_id and i.kind != :road)
    |> Repo.all()
    |> Map.new(&{&1.tile_id, improvement_map(&1)})
  end

  defp load_roads(world_id) do
    from(i in Improvement, where: i.world_id == ^world_id and i.kind == :road)
    |> Repo.all()
    |> Map.new(&{&1.tile_id, improvement_map(&1)})
  end

  defp load_cleared_features(world_id) do
    from(c in ClearedFeature, where: c.world_id == ^world_id, select: c.tile_id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp load_camps(world_id) do
    from(c in Camp, where: c.world_id == ^world_id)
    |> Repo.all()
    |> Map.new(&{&1.id, camp_map(&1)})
  end

  defp load_known_players(world_id) do
    from(k in KnownPlayer,
      where: k.world_id == ^world_id,
      select: {k.viewer_player_id, k.discovered_player_id}
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp load_player_research(world_id) do
    from(pr in PlayerResearch, where: pr.world_id == ^world_id)
    |> Repo.all()
    |> Map.new(&{&1.player_id, player_research_map(&1)})
  end

  defp player_map(%Player{} = p),
    do: %{
      id: p.id,
      user_id: p.user_id,
      region_id: p.region_id,
      gold: p.gold,
      heir_arrives_turn: p.heir_arrives_turn,
      barbarians_killed: p.barbarians_killed,
      camps_destroyed: p.camps_destroyed,
      banked_gold: p.banked_gold,
      bank_cap: p.bank_cap,
      honor: p.honor
    }

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
      max_movement: u.max_movement,
      charges: u.charges,
      temporary: u.temporary,
      fortified_turns: u.fortified_turns,
      rebellion_id: u.rebellion_id
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
      hp: c.hp,
      production_halted_until: c.production_halted_until,
      has_granary: c.has_granary,
      buildings: c.buildings,
      occupied_by_player_id: c.occupied_by_player_id,
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
      duration: i.duration,
      builder_unit_id: i.builder_unit_id
    }
  end

  defp camp_map(%Camp{} = c) do
    %{
      id: c.id,
      tile_id: c.tile_id,
      hp: c.hp,
      spawn_counter: c.spawn_counter,
      destroyed_at: c.destroyed_at
    }
  end

  # Story 902: `PlayerResearch.banked_science` round-trips jsonb as a
  # string-keyed map — this is the one place that converts it into the
  # tech-atom-keyed map every `Research` function works with. Safe via
  # `String.to_existing_atom/1` since every tech name is already a
  # compile-time atom in `Research`'s own catalog.
  defp player_research_map(%PlayerResearch{} = pr) do
    %{
      completed_techs: pr.completed_techs,
      current_research: pr.current_research,
      banked_science: atomize_banked_science(pr.banked_science)
    }
  end

  defp atomize_banked_science(banked_science) do
    Map.new(banked_science, fn {tech, amount} -> {String.to_existing_atom(tech), amount} end)
  end

  defp stringify_banked_science(banked_science) do
    Map.new(banked_science, fn {tech, amount} -> {Atom.to_string(tech), amount} end)
  end
end
