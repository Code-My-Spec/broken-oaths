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

  alias BrokenOaths.Game.{
    Alliance,
    Bank,
    BarbarianAI,
    Camp,
    Camps,
    City,
    CityDefense,
    Combat,
    Cooperation,
    Discovery,
    Exploration,
    GoldLog,
    Improvement,
    KnownPlayer,
    Levy,
    OathStrain,
    Order,
    Player,
    PlayerResearch,
    Presence,
    ProtectionPact,
    Production,
    ProductionItem,
    Rebellion,
    Rebellion.Resolution,
    RebellionPact,
    RebellionPactMember,
    Research,
    Siege,
    Spawner,
    StewardLog,
    Stewardship,
    Tribute,
    Turn,
    Unit,
    Vassalage,
    Vassalization,
    Visibility,
    Yields
  }

  alias BrokenOaths.Game
  alias BrokenOaths.Repo
  alias BrokenOaths.Users
  alias BrokenOaths.Worlds
  alias BrokenOaths.Worlds.Globe
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.Resources
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
    case do_queue_move(state, user, unit_id, to_tile) do
      {:ok, _path, queued} ->
        # Orders execute immediately with whatever movement the unit has
        # left; the turn boundary only recharges and continues.
        moved = Turn.move_now(queued, unit_id)
        {moved, capture_events} = apply_captures(moved)
        # Story 919: an adjacent march can knock a rebel out of the
        # fight (or hand the former lord back every risen city) without
        # ever needing a full turn boundary — see `process_rebellion_
        # endings/1`'s own doc for why this immediate hook matters
        # alongside its `run_tick/1` call site.
        moved = process_rebellion_endings(moved, :move)

        case persist_tick(queued, moved) do
          :ok ->
            broadcast(
              moved.world.id,
              [:units_changed | approach_alert_events(state, moved)] ++ capture_events
            )

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
    case do_attack_city(state, user, unit_id, city_id) do
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

  # QA issue 8aa2c571 — see `BrokenOaths.Game.cancel_improvement/3`'s doc.
  def handle_call({:cancel_improvement, user, unit_id}, _from, state) do
    case do_cancel_improvement(state, user, unit_id) do
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

  # Story 899: every civilization `user` has discovered in this world —
  # permanent once recorded, unrelated to current fog of war (see
  # `Discovery`'s and `KnownPlayer`'s docs). Ordered by `viewer_player_id`'s
  # own directional `KnownPlayer` rows, not fog-filtered current
  # visibility.
  def handle_call({:known_players, user}, _from, state) do
    {:reply, known_players(state, user), state}
  end

  # Story 901: every alliance `user` is a party to — reads straight from
  # `Repo` rather than an in-memory `state` cache the way `known_players`
  # does, since (unlike discovery) nothing on the tick hot-path ever
  # needs to check alliance status — `Cooperation.split_bounty/3`
  # explicitly does NOT gate on one (criterion 7624).
  def handle_call({:alliances, user}, _from, state) do
    {:reply, list_alliances(state, user), state}
  end

  # Builds (or updates, if a `:proposed` row already exists for this
  # pair) an `Alliance` changeset via `Cooperation.propose/4` and
  # persists it directly — an alliance is world-membership-scoped
  # coordination state, not tick-state, so unlike a move/attack/build
  # order this never touches `persist_tick/2` or the optimistic
  # turn-guard those use.
  def handle_call({:propose_alliance, user, other_user}, _from, state) do
    case do_propose_alliance(state, user, other_user) do
      {:ok, _alliance} ->
        broadcast(state.world.id, [:alliances_changed])
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Same non-tick-state status as `:propose_alliance` above.
  def handle_call({:accept_alliance, user, alliance_id}, _from, state) do
    case do_accept_alliance(state, user, alliance_id) do
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
    case do_resolve_garrison_fate(state, user, city_id, choice) do
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
    case do_issue_levy(state, user, vassal_user_id, target_user_id, share) do
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
    case do_answer_levy(state, user, lord_user_id) do
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
    case do_refuse_levy(state, user, lord_user_id) do
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
    case do_gift_vassal(state, user, vassal_user_id) do
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
    case do_declare_shared_enemy(state, user, vassal_user_id, enemy_user_id) do
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
    case do_mark_pact_unhonored(state, user, lord_user_id) do
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
  # `do_independence_preview/3`'s own doc.
  def handle_call({:independence_preview, user, lord_user_id}, _from, state) do
    {:reply, do_independence_preview(state, user, lord_user_id), state}
  end

  # Story 915: severs the oath, resolves risings, spawns the temporary
  # army, and opens the war — see `do_declare_independence/3`'s own
  # doc. Bypasses `persist_tick/2`'s own generic diff (which never
  # tracks a unit's own `player_id` changing, the defecting-garrison
  # case) in favor of its own immediate, targeted Repo writes — the
  # SAME "immediate, not tick-state" status `apply_captures/1`'s own
  # `persist_vassalization/2` already has for the sibling vassalization
  # write.
  def handle_call({:declare_independence, user, lord_user_id}, _from, state) do
    case do_declare_independence(state, user, lord_user_id) do
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
    case do_offer_peace(state, user, counterparty_user_id, outcome, reparations_gold) do
      {:ok, new_state} ->
        broadcast(new_state.world.id, [:vassals_changed])
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:accept_peace, user, counterparty_user_id}, _from, state) do
    case do_accept_peace(state, user, counterparty_user_id) do
      {:ok, new_state} ->
        broadcast(new_state.world.id, [:vassals_changed, :units_changed, :cities_changed])
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:reject_peace, user, counterparty_user_id}, _from, state) do
    case do_reject_peace(state, user, counterparty_user_id) do
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
    {:reply, pact_view(state, user), state}
  end

  def handle_call({:pact_candidates, user}, _from, state) do
    {:reply, pact_candidates(state, user), state}
  end

  # Persisted directly (never `persist_tick/2`) — same status
  # `do_propose_alliance/3` already has, since nothing about opening a
  # pact chat touches the tick-state hot path.
  def handle_call({:open_pact_chat, user, strike_turn, invitee_user_ids}, _from, state) do
    case do_open_pact_chat(state, user, strike_turn, invitee_user_ids) do
      {:ok, pact} ->
        broadcast(state.world.id, [:pact_changed])
        {:reply, {:ok, pact}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:pact_commit, user}, _from, state) do
    case do_pact_answer(state, user, :committed) do
      {:ok, member} ->
        broadcast(state.world.id, [:pact_changed])
        {:reply, {:ok, member}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:pact_decline, user}, _from, state) do
    case do_pact_answer(state, user, :declined) do
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
    case do_pact_inform(state, user) do
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
    {:reply, conspiracy_heat(state, user), state}
  end

  # Immediate, targeted Repo writes (`state.cities`/`state.units`
  # updated in-place) — same "bypasses `persist_tick/2`'s own generic
  # diff" status `rise_cities/5` already has, since neither a city's
  # nor a unit's own HP is otherwise ever mutated outside a tick.
  def handle_call({:brace_defenses, user}, _from, state) do
    case do_brace_defenses(state, user) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:reposition_lord, user}, _from, state) do
    case do_reposition_lord(state, user) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:buy_off_conspirators, user}, _from, state) do
    case do_buy_off_conspirators(state, user) do
      :ok ->
        broadcast(state.world.id, [:vassals_changed])
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:honor_protection_call, user, vassal_user_id}, _from, state) do
    case do_honor_protection_call(state, user, vassal_user_id) do
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
    {:reply, bank_status(state, user), state}
  end

  # The deliberate engagement tap: sweep the ENTIRE bank into the
  # treasury (`Bank.collect/1`) — a no-op (empties nothing, moves
  # nothing) against an already-empty bank, never refused outright.
  def handle_call({:collect_bank, user}, _from, state) do
    case do_collect_bank(state, user) do
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
    case do_upgrade_bank(state, user) do
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
    {:reply, steward_log(state, user), state}
  end

  # `Bank.steward_collect/1` — sweeps the offline owner's ENTIRE bank
  # into their own treasury, pure stewardship (the steward's own
  # treasury never moves). Refused unless `steward_user` is eligible
  # (`Stewardship.eligible?/1`) and `owner_user_id` is genuinely
  # offline (`Presence.online?/2`).
  def handle_call({:steward_collect_bank, steward_user, owner_user_id}, _from, state) do
    case do_steward_collect_bank(state, steward_user, owner_user_id) do
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
  # same "not tick-state" status `do_queue_production/4` already has.
  def handle_call(
        {:steward_queue_production, steward_user, owner_user_id, city_id, type},
        _from,
        state
      ) do
    case do_steward_queue_production(state, steward_user, owner_user_id, city_id, type) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  # "No cancel-griefing" — a steward's cancel attempt is refused
  # structurally: no path anywhere in this module ever reaches the
  # real `do_cancel_production_item/4`. Same discipline
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
    case do_steward_defend(state, steward_user, owner_user_id, unit_id, to_tile) do
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
    {:reply, Enum.map(Map.values(state.camps), &format_camp(&1, state)), state}
  end

  def handle_call({:camps_visible_to, user}, _from, state) do
    {:reply, visible_camps(state, user), state}
  end

  # QA issue 56ee521a: fog-filtered ENEMY (another player's own) cities
  # — the same "own region OR explored" rule `visible_camps/2` already
  # uses, minus every city already occupied by the VIEWER themselves
  # (their own captured holding isn't a fresh attack target — see
  # `captured_cities_visible_to/2`'s own doc for where THAT surfaces
  # instead). Empty unless `Game.feudal_enabled?/0` — belt-and-
  # suspenders alongside `do_attack_city/4`'s own gate, matching
  # `apply_captures/1`'s own posture.
  def handle_call({:enemy_cities_visible_to, user}, _from, state) do
    {:reply, visible_enemy_cities(state, user), state}
  end

  # QA issue ffa66192: cities the VIEWER has personally captured
  # (`occupied_by_player_id == their own player id`), each carrying
  # `fallen_garrison?` — whether `Siege.fallen_garrison/2` still finds a
  # living defender awaiting the execute/release choice. Powers
  # `GameLive.Play`'s own "Captured Cities" panel. Empty unless `Game.
  # feudal_enabled?/0`, same belt-and-suspenders status as
  # `visible_enemy_cities/2` above.
  def handle_call({:captured_cities_visible_to, user}, _from, state) do
    {:reply, captured_cities(state, user), state}
  end

  def handle_call({:tile_improvement, tile_id}, _from, state) do
    {:reply, tile_improvement_at(state, tile_id), state}
  end

  def handle_call({:improvements_visible_to, user}, _from, state) do
    {:reply, visible_improvements(state, user), state}
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
  # yet at all (`BrokenOaths.Game.Yields` only ever produces food/
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
    new_state = put_improvement(state, kind, tile_id, improvement_data)
    {:reply, improvement_data, new_state}
  end

  # Test-only: grant `city_id` Copper access (story 911) by appending a
  # REAL Copper tile's id (found anywhere on the map via
  # `Resources.at/2`) onto that city's own `territory` — same narrow,
  # documented-bridge status as `:complete_improvement_for_test` above.
  # A city's Copper access is a genuine geometric fact (a Copper tile
  # somewhere in ITS OWN territory), which most specs have no reason to
  # steer deterministically — a scenario whose SUBJECT is something
  # else entirely (e.g. story 903's "the Spearman outfights a
  # barbarian" combat spec) still needs a real, spawned Bronze Spearman
  # to exist, and story 911 makes that now depend on an access fact no
  # earlier story had to arrange. This sidesteps hunting for (or
  # engineering a founding spot near) a real Copper tile the way
  # `:relocate_unit_for_test` sidesteps a real march. Refuses with
  # `{:error, :no_copper_on_map}` if the world's own placement rolled
  # no Copper anywhere (vanishingly rare at real gameplay scale, but a
  # possible outcome of any seed-deterministic placement).
  def handle_call({:grant_copper_access_for_test, city_id}, _from, state) do
    case Map.get(state.cities, city_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      city ->
        case find_any_copper_tile(state.world) do
          nil ->
            {:reply, {:error, :no_copper_on_map}, state}

          tile_id ->
            new_territory = Enum.uniq([tile_id | city.territory])
            new_city = %{city | territory: new_territory}
            {:reply, :ok, %{state | cities: Map.put(state.cities, city_id, new_city)}}
        end
    end
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
    {gated_state, deferred_heirs} = defer_gated_heirs(state)
    {ticked, events} = Turn.tick(gated_state)
    ticked = restore_gated_heirs(ticked, deferred_heirs)
    {events, ticked} = materialize_spawns(events, ticked)
    ticked = %{ticked | turn_started_at: DateTime.utc_now()}
    {ticked, capture_events} = apply_captures(ticked)
    {ticked, tribute_logs} = apply_tribute(ticked)
    ticked = apply_oath_strain_drift(ticked)
    ticked = apply_protection_pact_ticks(ticked)
    ticked = apply_bank(ticked)
    ticked = process_rebellion_endings(ticked)
    ticked = reconcile_heir_vassals(ticked, events)
    ticked = apply_rebellion_pact_strikes(ticked)
    {new_state, discovery_events} = apply_discoveries(state, ticked)

    case persist_tick(state, new_state) do
      :ok ->
        persist_gold_logs(tribute_logs)

        broadcast(
          new_state.world.id,
          [:vassals_changed] ++
            events ++
            discovery_events ++ approach_alert_events(state, new_state) ++ capture_events
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

  # Story 917 (criterion 7748) — reconciles story 896's own already-
  # shipped flat-10-turn heir schedule (`schedule_heir_if_lord_fell/2`,
  # UNCHANGED — a single scheduling mechanism, never a second competing
  # timer) with "the heir does not arrive until the LAST active
  # rebellion against the realm has ended": withholds any `state.
  # pending_heirs` entry for a player currently facing an ACTIVE
  # `Rebellion` from `Turn.tick/1`'s own pure "heir succession" phase
  # entirely (so it can never resolve THIS tick no matter how far past
  # its own `arrival_turn` the clock has run), then splices it back in,
  # completely untouched, once `Turn.tick/1` returns (`restore_gated_
  # heirs/2` below) — the very next tick re-checks from scratch. A
  # player with NO active rebellion against them (including a lord who
  # dies with no vassals at all — criterion 7750's own "quiet death")
  # is never gated at all, so the original flat-10-turn arrival fires
  # exactly as story 896 shipped it, unmodified.
  defp defer_gated_heirs(state) do
    pending = Map.get(state, :pending_heirs, %{})

    {gated, ready} =
      Enum.split_with(pending, fn {player_id, _arrival_turn} ->
        active_rebellion_against?(state, player_id)
      end)

    {%{state | pending_heirs: Map.new(ready)}, Map.new(gated)}
  end

  defp restore_gated_heirs(ticked, gated) when map_size(gated) == 0, do: ticked

  defp restore_gated_heirs(ticked, gated) do
    pending = Map.get(ticked, :pending_heirs, %{})
    %{ticked | pending_heirs: Map.merge(pending, gated)}
  end

  defp active_rebellion_against?(state, former_lord_player_id) do
    Rebellion
    |> where(
      [r],
      r.world_id == ^state.world.id and r.former_lord_player_id == ^former_lord_player_id and
        r.status == :active
    )
    |> Repo.exists?()
  end

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
        |> Enum.each(&maybe_revassalize(state, lord_player.id, &1))
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

  # Story 899: first-contact detection is evaluated once per turn
  # boundary — the same place every other cross-player/AI decision in
  # this codebase resolves (heir succession, city alerts, barbarian AI).
  # `Discovery.new_contacts/2` reports each NEW pair against the
  # PRE-tick known set (`state.known_players`) using the POST-tick
  # (`ticked`) unit/city positions — a unit that moved into sight THIS
  # tick is what triggers it. Each contact folds both directions into
  # `known_players` (discovery is mutual — see `KnownPlayer`'s doc) and
  # produces one `{:discovery, user_id, message}` event per side,
  # mirroring `:city_alert`'s player-scoped push shape.
  defp apply_discoveries(state, ticked) do
    known = Map.get(state, :known_players, MapSet.new())
    contacts = Discovery.new_contacts(ticked, known)

    Enum.reduce(contacts, {ticked, []}, fn {a, b}, {acc_state, acc_events} ->
      updated_known =
        acc_state |> Map.get(:known_players, known) |> MapSet.put({a, b}) |> MapSet.put({b, a})

      new_acc_state = Map.put(acc_state, :known_players, updated_known)
      {new_acc_state, acc_events ++ discovery_events(acc_state, a, b)}
    end)
  end

  defp discovery_events(state, player_a_id, player_b_id) do
    user_a_id = Map.fetch!(state.players, player_a_id).user_id
    user_b_id = Map.fetch!(state.players, player_b_id).user_id
    email_a = Users.get_user!(user_a_id).email
    email_b = Users.get_user!(user_b_id).email

    [
      {:discovery, user_a_id, "You have discovered #{email_b}'s civilization!"},
      {:discovery, user_b_id, "#{email_a} has discovered your civilization!"}
    ]
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
        unit = insert_spawned_unit!(acc_state.world.id, spawn_event)

        {{:unit_spawned, Map.put(spawn_event, :unit_id, unit.id)},
         %{acc_state | units: Map.put(acc_state.units, unit.id, unit)}}

      other_event, acc_state ->
        {other_event, acc_state}
    end)
  end

  defp insert_spawned_unit!(
         world_id,
         %{player_id: player_id, type: type, tile_id: tile_id} = event
       ) do
    stats = Production.unit_stats(type)
    camp_id = Map.get(event, :camp_id)

    {:ok, unit} =
      insert_unit(world_id, player_id, type, tile_id, stats.hp, stats.movement, camp_id)

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

        {:ok, player_research} =
          %PlayerResearch{}
          |> PlayerResearch.changeset(%{world_id: state.world.id, player_id: player.id})
          |> Repo.insert()

        {player_map(player), [unit_map(lord), unit_map(settler)], explored,
         player_research_map(player_research)}
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

  # Story 915: the temporary rebellion army raised at declare-independence
  # time — same shape as `insert_unit/7` plus the two fields that mark
  # it disbandable (`Unit`'s own moduledoc, `temporary`/`rebellion_id`).
  defp insert_temporary_unit!(world_id, player_id, type, tile_id, rebellion_id) do
    stats = Production.unit_stats(type)

    {:ok, unit} =
      %Unit{}
      |> Unit.changeset(%{
        world_id: world_id,
        player_id: player_id,
        type: type,
        tile_id: tile_id,
        hp: stats.hp,
        max_hp: stats.hp,
        movement: stats.movement,
        max_movement: stats.movement,
        temporary: true,
        rebellion_id: rebellion_id
      })
      |> Repo.insert()

    unit_map(unit)
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

      occupied_by_own?(state, to_tile, player.id, unit) ->
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
  # tile is still occupied when they actually arrive. Story 895's
  # exception: `mover`'s own city's own tile allows up to
  # `CityDefense.garrison_cap/0` military units (civilians always fit,
  # uncounted) — see `CityDefense.garrison_room?/2`. Every OTHER own
  # tile keeps a tighter, but not all-or-nothing, rule (v0.2.1 playtest
  # issue 5df5de88): exactly one non-combat unit may stack with exactly
  # one combat unit out in the open field — `field_stack_room?/2` below
  # — so a worker/settler can walk with a warrior escort without a
  # city underfoot. `Turn.blocked?/6` mirrors this same allowance for
  # the dynamic, tick-time collision check.
  defp occupied_by_own?(state, tile_id, player_id, mover) do
    own_units_here =
      for {_id, u} <- state.units, u.tile_id == tile_id, u.player_id == player_id, do: u

    case Enum.find(state.cities, fn {_id, c} ->
           c.tile_id == tile_id and c.player_id == player_id
         end) do
      nil -> not field_stack_room?(mover, own_units_here)
      _own_city -> not CityDefense.garrison_room?(mover, own_units_here)
    end
  end

  # Room for `mover` on a non-city tile already holding `own_units_here`
  # (all same-owner, by construction — see `occupied_by_own?/4`'s own
  # `own_units_here` filter): empty is always room; a lone existing unit
  # leaves room only for the OTHER combat class (one civilian + one
  # combat, either order); two or more units already there is always
  # full. `CityDefense.military?/1` is the same combat/civilian split
  # story 895's own garrison rule uses (`:lord`/`:warrior`/
  # `:bronze_spearman` are combat; everything else is civilian).
  defp field_stack_room?(_mover, []), do: true

  defp field_stack_room?(mover, [only]),
    do: CityDefense.military?(only) != CityDefense.military?(mover)

  defp field_stack_room?(_mover, _units), do: false

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

        case validate_attack(state, attacker, defender, adjacent_tile_ids) do
          :ok ->
            {result, new_state} = resolve_attack(state, attacker, defender)
            {:ok, result, new_state}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # Story 914: `Combat.validate_attack/3`'s own general "no PvP in the
  # Stone Age" rule (`Combat.hostile?/2` — false for any two real
  # players, LOCKED, see `BrokenOathsSpex.Story899.Criterion7603Spex`)
  # stays untouched for everyone ELSE — this only widens the CALLER-side
  # gate `do_attack/4` itself applies, with one narrow, story-914-scoped
  # exception: a lord may always strike the SPECIFIC unit currently
  # tracked as the besieger of one of their OWN vassal's active
  # Protection Pact calls ("the lord is notified and is expected to
  # defend" — the design doc's own words require the lord be ABLE to
  # fight back). Every other pairing of two real players falls through
  # to `Combat.validate_attack/3`'s own unchanged verdict.
  defp validate_attack(state, attacker, defender, adjacent_tile_ids) do
    cond do
      attacker.movement <= 0 -> {:error, :out_of_movement}
      defender.tile_id not in adjacent_tile_ids -> {:error, :not_adjacent}
      Combat.hostile?(attacker, defender) -> :ok
      protecting_lord_may_strike?(state, attacker, defender) -> :ok
      rebellion_war?(state, attacker.player_id, defender.player_id) -> :ok
      true -> {:error, :not_hostile}
    end
  end

  defp protecting_lord_may_strike?(state, attacker, defender) do
    Enum.any?(protection_calls(state), fn {_vassal_player_id, call} ->
      call.attacker_unit_id == defender.id and call.lord_player_id == attacker.player_id
    end)
  end

  defp resolve_attack(state, attacker, defender) do
    seed = {state.world.seed, state.turn, attacker.id, defender.id}

    %{damage_to_defender: dealt, damage_to_attacker: taken} =
      Combat.resolve(attacker, defender,
        seed: seed,
        attacker_aura?: lord_adjacent?(state, attacker),
        defender_aura?: lord_adjacent?(state, defender),
        attacker_garrisoned?: CityDefense.garrisoned?(attacker, Map.values(state.cities)),
        defender_garrisoned?: CityDefense.garrisoned?(defender, Map.values(state.cities))
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
      |> maybe_raise_protection_call(attacker, defender.player_id)
      |> resolve_protection_call_if_dead(new_attacker)
      |> resolve_protection_call_if_dead(new_defender)

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
  # there, killed by the defender's counter-blow). Story 904: the same
  # kill also bumps the payee's own `barbarians_killed` career total —
  # the progress panel's "Total barbarians killed" figure.
  defp pay_bounty_if_barbarian_fell(state, %{player_id: nil, hp: 0}, %{player_id: payee_id})
       when not is_nil(payee_id) do
    state = update_in(state.players[payee_id].gold, &(&1 + BarbarianAI.bounty_gold()))
    update_in(state.players[payee_id].barbarians_killed, &(&1 + 1))
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
      |> record_camp_damage(camp.id, attacker.player_id, dealt)
      |> apply_camp_damage(new_camp)

    {%{damage_dealt: dealt, damage_taken: 0}, state}
  end

  # Story 901: every hit against a camp — from ANY player, not just
  # whoever eventually lands the killing blow — accumulates in the
  # in-memory damage ledger `split_bounty/2` (below) reads once the
  # camp falls. Kept only in memory (`state.camp_contributions`), never
  # persisted — same known, narrow limitation `WorldServer`'s own
  # `pending_heirs` doc calls out for equally ephemeral cross-tick
  # bookkeeping: a restart mid-siege loses the running tally (the
  # camp's own HP, being a real persisted column, is unaffected).
  defp record_camp_damage(state, camp_id, player_id, dealt) do
    contributions =
      Cooperation.record_damage(camp_contributions(state), camp_id, player_id, dealt)

    Map.put(state, :camp_contributions, contributions)
  end

  defp camp_contributions(state), do: Map.get(state, :camp_contributions, %{})

  # Story 894/901, criterion 7560/7614/7615: 0 HP destroys the camp —
  # `destroyed_at` stops `Camps.advance/2` from ever spawning again
  # (already handled, story 892) and drops it from `visible_camps/2`'s
  # fog-filtered surface. `Camps.destroy_reward/0` splits proportionally
  # across every player who ever struck THIS camp
  # (`Cooperation.split_bounty/3`, reading the ledger `record_camp_damage/3`
  # built above) — a sole attacker's own 100% share is still the WHOLE
  # reward, never a smaller "default" cut (criterion 7615). The ledger
  # entry is forgotten immediately after: a camp is destroyed exactly
  # once, and nothing else ever reads its history. Orphaned warriors are
  # untouched — they're separate `Unit` rows, not nested under the camp
  # in `state.units` (criterion 7561).
  defp apply_camp_damage(state, %{hp: 0} = camp) do
    destroyed = %{camp | destroyed_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)}
    shares = Cooperation.split_bounty(camp_contributions(state), camp.id, Camps.destroy_reward())

    %{state | camps: Map.put(state.camps, camp.id, destroyed)}
    |> pay_shares(shares)
    |> Map.put(:camp_contributions, Cooperation.forget(camp_contributions(state), camp.id))
  end

  defp apply_camp_damage(state, camp) do
    %{state | camps: Map.put(state.camps, camp.id, camp)}
  end

  # Story 904: every contributor paid a reward share also gets their
  # own `camps_destroyed` career total bumped — the same "credit
  # everyone who struck it, not just the killing blow" philosophy
  # `Cooperation.split_bounty/3` already applies to the gold itself.
  defp pay_shares(state, shares) do
    Enum.reduce(shares, state, fn {player_id, gold}, acc ->
      acc = update_in(acc.players[player_id].gold, &(&1 + gold))
      update_in(acc.players[player_id].camps_destroyed, &(&1 + 1))
    end)
  end

  # -------------------------------------------------------------------
  # City assault (story 895)
  # -------------------------------------------------------------------

  # Resolves immediately, like `do_attack/4` — see `CityDefense`'s
  # moduledoc for the damage math (city defensive strength vs. attacker
  # strength, countered by the strongest garrisoned defender). Unlike
  # `Combat.hostile?/2`'s "no Stone Age PvP" rule for unit-vs-unit
  # combat, ANY player's unit may assault ANY OTHER player's city —
  # `Siege.validate_siege/3` (story 906) layers ONE new rule on top of
  # `CityDefense.validate_attack/3`'s own not-your-own-city/adjacency/
  # movement checks: the attacker must be MILITARY, a civilian besieger
  # is refused outright (`:not_military`) rather than merely
  # ineffective — matching this story's own spec convention of a second
  # real player standing in for a barbarian. `Game.feudal_enabled?/0`
  # is checked LAST, only once the request is otherwise well-formed
  # (owned attacker, real city target) — with the batch dormant
  # (`config :broken_oaths, :feudal_enabled, false`, prod's own
  # default), any city assault is refused exactly the way `Combat.
  # hostile?/2` already refuses unit-vs-unit PvP: `{:error,
  # :not_hostile}`, same "Stone Age players cannot fight each other"
  # copy `combat_error_message/1` already renders for it — restoring
  # the pre-906 no-PvP-city-capture behavior. Barbarian city assault
  # (`CityDefense`'s pillage path, driven by `Turn`'s own barbarian-AI
  # phase, never this "attack" surface) is untouched either way.
  defp do_attack_city(state, user, unit_id, city_id) do
    player = find_player(state, user.id)
    attacker = Map.get(state.units, unit_id)
    city = Map.get(state.cities, city_id)

    cond do
      is_nil(player) or is_nil(attacker) or attacker.player_id != player.id ->
        {:error, :not_owner}

      is_nil(city) ->
        {:error, :invalid_target}

      not Game.feudal_enabled?() ->
        {:error, :not_hostile}

      true ->
        adjacent_tile_ids = Regions.adjacent_tiles(state.world, attacker.tile_id)

        case Siege.validate_siege(attacker, city, adjacent_tile_ids) do
          :ok ->
            {result, new_state} = resolve_city_attack(state, attacker, city)

            alert =
              {:city_alert, owner_user_id(state, city.player_id),
               CityDefense.under_attack_alert(city.name)}

            {:ok, result, new_state, alert}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp resolve_city_attack(state, attacker, city) do
    seed = {state.world.seed, state.turn, attacker.id, city.id}
    units = Map.values(state.units)

    %{damage_to_city: dealt, damage_to_barbarian: taken} =
      CityDefense.resolve_attack(city, units, attacker,
        seed: seed,
        attacker_aura?: lord_adjacent?(state, attacker)
      )

    new_city = Siege.take_damage(city, dealt)
    new_attacker = %{attacker | hp: max(attacker.hp - taken, 0), movement: 0}

    state =
      %{
        state
        | units: apply_combat_unit(state.units, attacker.id, new_attacker),
          cities: Map.put(state.cities, city.id, new_city)
      }
      |> schedule_heir_if_lord_fell(attacker, new_attacker)
      |> pay_bounty_if_barbarian_fell(new_attacker, %{player_id: city.player_id})
      |> maybe_raise_protection_call(attacker, city.player_id)
      |> resolve_protection_call_if_dead(new_attacker)

    {%{damage_dealt: dealt, damage_taken: taken}, state}
  end

  defp owner_user_id(state, player_id), do: Map.fetch!(state.players, player_id).user_id

  # -------------------------------------------------------------------
  # Capture & Vassalization (stories 906/907)
  # -------------------------------------------------------------------

  # Safe to call after ANY movement-producing change (an immediate
  # `queue_move`, or a full tick) — `Siege.materialize_captures/2` is
  # itself idempotent, so this never double-reports a city already
  # captured on a prior call. A fresh capture that leaves its defeated
  # player with zero free cities left also fires vassalization right
  # here (`Vassalization.vassalization_events/2`), in the SAME pass —
  # the DB write happens immediately (mirrors `do_propose_alliance/3`'s
  # own "not tick-state, persisted immediately" status), never waiting
  # on `persist_tick/2`'s own city/unit diff. A no-op while `Game.
  # feudal_enabled?/0` reads `false` — belt-and-suspenders alongside
  # `do_attack_city/4`'s own gate, which already keeps every city
  # `Siege.broken?/1` (the only way `materialize_captures/2` ever finds
  # anything to capture) from ever happening in the first place.
  defp apply_captures(state) do
    if Game.feudal_enabled?() do
      {new_cities, capture_events} = Siege.materialize_captures(state.cities, state.units)
      new_state = %{state | cities: new_cities}

      case capture_events do
        [] ->
          {new_state, []}

        _ ->
          vassalize_events =
            Vassalization.vassalization_events(capture_events, Map.values(new_cities))

          Enum.each(vassalize_events, &persist_vassalization(new_state, &1))

          events =
            [:cities_changed] ++
              Enum.flat_map(vassalize_events, &vassalization_broadcast(new_state, &1))

          {new_state, events}
      end
    else
      {state, []}
    end
  end

  # Guards against ever double-inserting the same vassal's own row —
  # `apply_captures/1` is idempotent about REPORTING a capture, but a
  # defensive re-check here keeps this write idempotent too, in case a
  # future caller ever runs it against the same event twice.
  defp persist_vassalization(state, %{captor_player_id: lord_id, defeated_player_id: vassal_id}) do
    case Repo.get_by(Vassalage,
           world_id: state.world.id,
           vassal_player_id: vassal_id,
           status: :active
         ) do
      nil ->
        upsert_vassalage!(state.world.id, lord_id, vassal_id)
        :ok

      _existing ->
        :ok
    end
  end

  # Story 915/919: `Vassalage`'s own unique index is on `(world_id,
  # vassal_player_id)` ALONE, not scoped to `status` — "a vassal serves
  # exactly one lord at a time... a broken/superseded row would need a
  # DIFFERENT status, not a second active one for the same vassal"
  # (`20260718090000_create_vassalages.exs`'s own comment). A rebel
  # whose Vassalage was severed (`:broken`, story 915) and is later
  # re-vassalized (crushed, story 919, or plain re-siege) reactivates
  # that SAME row rather than inserting a fresh one that would violate
  # the index — reset to a clean oath (default tribute/strain, no
  # carried-over Hidden Agenda) under whichever lord captured them this
  # time.
  defp upsert_vassalage!(world_id, lord_player_id, vassal_player_id) do
    case Repo.get_by(Vassalage, world_id: world_id, vassal_player_id: vassal_player_id) do
      nil ->
        {:ok, vassalage} =
          Vassalization.vassalize_changeset(world_id, lord_player_id, vassal_player_id)
          |> Repo.insert()

        vassalage

      existing ->
        Vassalage.changeset(existing, %{
          lord_player_id: lord_player_id,
          status: :active,
          tribute_rate: 0.25,
          oath_strain: 0,
          hidden_agenda: nil,
          contract_terms: %{}
        })
        |> Repo.update!()
    end
  end

  # Both halves of "both players notified": the fresh vassal's own
  # `"game:vassalized"` push (story 906's own criterion 7665 trigger,
  # reused as-is by 907) and the lord's own `"game:new_vassal"` push
  # (907's own new half).
  defp vassalization_broadcast(state, %{captor_player_id: lord_id, defeated_player_id: vassal_id}) do
    lord_user_id = owner_user_id(state, lord_id)
    vassal_user_id = owner_user_id(state, vassal_id)
    lord_email = Users.get_user!(lord_user_id).email
    vassal_email = Users.get_user!(vassal_user_id).email

    [
      {:vassalized, vassal_user_id, Vassalization.vassalized_message(lord_email)},
      {:new_vassal, lord_user_id, vassal_user_id, Vassalization.new_vassal_message(vassal_email)}
    ]
  end

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
  # `apply_captures/1`'s own gate, which already keeps `active_vassalages/1`
  # from ever finding a row to collect against.
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
  # Oath Strain drift (story 913)
  # -------------------------------------------------------------------

  # Runs every turn boundary, alongside `apply_tribute/1` — reads the
  # SAME `active_vassalages/1` fresh from Repo and nudges each one's own
  # Oath Strain by `OathStrain.tribute_drift/2`, off its OWN
  # `tribute_rate` ("slow and sticky": at most `OathStrain.
  # max_drift_step/0` points per boundary, zero at the 25% baseline —
  # see that module's own moduledoc). Persisted immediately, same
  # "direct Repo write, not tick-state" status `Tribute.
  # spike_oath_strain/1`'s own call site (`do_refuse_levy/3`) already
  # has for this exact column — never writes when the drift is
  # genuinely zero, so a quiet vassalage held exactly at the baseline
  # generates no churn. A no-op while `Game.feudal_enabled?/0` reads
  # `false`, same belt-and-suspenders status `apply_tribute/1` already
  # carries.
  defp apply_oath_strain_drift(state) do
    if Game.feudal_enabled?() do
      for vassalage <- active_vassalages(state.world.id) do
        new_strain = OathStrain.tribute_drift(vassalage.oath_strain, vassalage.tribute_rate)

        if new_strain != vassalage.oath_strain do
          Vassalage.changeset(vassalage, %{oath_strain: new_strain}) |> Repo.update!()
        end
      end

      state
    else
      state
    end
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

  # Story 914 (criterion 7726): the moment a genuine THIRD PARTY (never
  # the vassal's own lord) lands a real attack on a vassal's city or
  # unit, raises a Protection Pact obligation against their lord —
  # reuses the SAME two real attack surfaces every combat in this
  # codebase already resolves through: `resolve_attack/3` (unit-vs-unit,
  # also the barbarian bridge `:resolve_barbarian_attack_for_test`
  # calls) and `resolve_city_attack/2` (a besieging "attack"/
  # `target_city_id`). A no-op while a call is ALREADY pending for this
  # vassal (one obligation at a time), while the attacker IS their own
  # lord (no self-protection), or while `Game.feudal_enabled?/0` reads
  # `false`.
  defp maybe_raise_protection_call(state, _attacker, nil), do: state

  defp maybe_raise_protection_call(state, attacker, victim_player_id) do
    with true <- Game.feudal_enabled?(),
         %Vassalage{} = vassalage <- active_vassalage_for_vassal(state, victim_player_id),
         true <- attacker.player_id != vassalage.lord_player_id,
         nil <- Map.get(protection_calls(state), victim_player_id) do
      call =
        vassalage.lord_player_id
        |> ProtectionPact.raise_call(victim_player_id, state.turn)
        |> Map.put(:attacker_unit_id, attacker.id)

      Map.put(state, :protection_calls, Map.put(protection_calls(state), victim_player_id, call))
    else
      _ -> state
    end
  end

  # The HONORED branch (criteria 7728/7730): the moment the tracked
  # besieger dies — whether from the lord's own follow-up strike
  # (`resolve_attack/3`) or the CITY's own counter-fire in the very same
  # clash that raised the call (`resolve_city_attack/2`) — the call
  # resolves honored right here, no window-expiry wait needed. Only
  # ever matches a call still tracking THIS exact dead unit's own id.
  defp resolve_protection_call_if_dead(state, %{hp: 0} = dead_unit) do
    protection_calls(state)
    |> Enum.find(fn {_vassal_player_id, call} -> call.attacker_unit_id == dead_unit.id end)
    |> case do
      nil -> state
      {vassal_player_id, call} -> resolve_honored(state, vassal_player_id, call)
    end
  end

  defp resolve_protection_call_if_dead(state, _unit), do: state

  defp resolve_honored(state, vassal_player_id, call) do
    {:ok, vassalage} = fetch_vassalage(state, call.lord_player_id, vassal_player_id)
    lord_honor = state.players[call.lord_player_id].honor

    {_resolved_call, new_strain, new_honor} =
      ProtectionPact.score_honored(call, vassalage.oath_strain, lord_honor)

    Vassalage.changeset(vassalage, %{oath_strain: new_strain}) |> Repo.update!()

    state = put_in(state.players[call.lord_player_id].honor, new_honor)

    state
    |> Map.put(:protection_calls, Map.delete(protection_calls(state), vassal_player_id))
    |> Map.put(
      :protection_honored_counts,
      Map.update(protection_honored_counts(state), vassal_player_id, 1, &(&1 + 1))
    )
  end

  # The BROKEN branch (criterion 7729): only ever called once a call's
  # own `ProtectionPact.expired?/1` reads true (see
  # `apply_protection_pact_ticks/1`) — docks the lord's Honor, spikes
  # the direct victim's own strain, and fans the smaller realm-wide
  # contagion spike out to every OTHER active vassal of the same lord
  # (`apply_protection_pact_contagion/3`).
  defp resolve_broken(state, vassal_player_id, call) do
    {:ok, vassalage} = fetch_vassalage(state, call.lord_player_id, vassal_player_id)
    lord_honor = state.players[call.lord_player_id].honor

    {_resolved_call, new_strain, new_honor} =
      ProtectionPact.score_broken(call, vassalage.oath_strain, lord_honor)

    Vassalage.changeset(vassalage, %{oath_strain: new_strain}) |> Repo.update!()
    apply_protection_pact_contagion(state, call.lord_player_id, vassal_player_id)

    state = put_in(state.players[call.lord_player_id].honor, new_honor)
    Map.put(state, :protection_calls, Map.delete(protection_calls(state), vassal_player_id))
  end

  # Every OTHER active vassal of `lord_player_id` (never the direct
  # victim, `victim_vassal_player_id`) takes `ProtectionPact.
  # spike_contagion/1` — read fresh from Repo, same "world-membership-
  # scoped coordination state, not tick-state" status `active_vassalages/1`
  # already documents. Persisted immediately, side-effect only (the
  # caller's own `state` is untouched by this).
  defp apply_protection_pact_contagion(state, lord_player_id, victim_vassal_player_id) do
    Vassalage
    |> where(
      [v],
      v.world_id == ^state.world.id and v.lord_player_id == ^lord_player_id and
        v.status == :active and v.vassal_player_id != ^victim_vassal_player_id
    )
    |> Repo.all()
    |> Enum.each(fn vassalage ->
      new_strain = ProtectionPact.spike_contagion(vassalage.oath_strain)
      Vassalage.changeset(vassalage, %{oath_strain: new_strain}) |> Repo.update!()
    end)
  end

  # Runs every turn boundary, alongside `apply_oath_strain_drift/1` —
  # counts every still-pending call down by exactly one
  # (`ProtectionPact.tick/1`, criterion 7727); an expired, still-
  # unanswered one resolves BROKEN right here (criterion 7729). A no-op
  # while `Game.feudal_enabled?/0` reads `false`.
  defp apply_protection_pact_ticks(state) do
    if Game.feudal_enabled?() do
      Enum.reduce(protection_calls(state), state, fn {vassal_player_id, call}, acc ->
        ticked_call = ProtectionPact.tick(call)

        if ProtectionPact.expired?(ticked_call) do
          resolve_broken(acc, vassal_player_id, ticked_call)
        else
          Map.put(
            acc,
            :protection_calls,
            Map.put(protection_calls(acc), vassal_player_id, ticked_call)
          )
        end
      end)
    else
      state
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
  # `apply_tribute/1` taxes) via `Bank.settle_income/3`: straight to
  # `:gold` while `Presence.online?/2` reads true, into the capped
  # `:banked_gold` otherwise. A no-op while `Game.feudal_enabled?/0`
  # reads `false` — same belt-and-suspenders status
  # `apply_captures/1`/`apply_tribute/1` already carry, so prod's own
  # gold economy (bounty kills, camp rewards — the only things that
  # ever moved `gold` before this story) stays exactly as it was until
  # the flag flips on for real (v0.3.0).
  defp apply_bank(state) do
    if Game.feudal_enabled?() do
      income_by_player = gold_income_by_player(state)

      new_players =
        Enum.reduce(income_by_player, state.players, &settle_player_income(&1, &2, state.world))

      %{state | players: new_players}
    else
      state
    end
  end

  defp settle_player_income({player_id, income}, players, world) do
    case Map.get(players, player_id) do
      nil ->
        players

      player ->
        online? = Presence.online?(world, %{id: player.user_id})
        Map.put(players, player_id, Bank.settle_income(player, income, online?))
    end
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
            first_founding? =
              not Enum.any?(state.cities, fn {_id, c} -> c.player_id == player.id end)

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
    # Units, existing camps (any player's founding may already have
    # placed some — game_camps carries a world+tile unique index), and
    # cities all block placement.
    occupied =
      [
        state.units |> Map.values() |> Enum.map(& &1.tile_id),
        state |> Map.get(:camps, %{}) |> Map.values() |> Enum.map(& &1.tile_id),
        state |> Map.get(:cities, %{}) |> Map.values() |> Enum.map(& &1.tile_id)
      ]
      |> List.flatten()
      |> MapSet.new()

    seed = {state.world.seed, city_tile_id}

    tiles =
      Camps.place_wilderness(state.world, city_tile_id, home_region, explored, occupied, seed)

    camps = Enum.map(tiles, &persist_camp!(state.world.id, &1))

    %{state | camps: Enum.reduce(camps, Map.get(state, :camps, %{}), &Map.put(&2, &1.id, &1))}
  end

  defp persist_camp!(world_id, tile_id) do
    {:ok, camp} =
      %Camp{}
      |> Camp.changeset(%{
        world_id: world_id,
        tile_id: tile_id,
        hp: Camp.max_hp(),
        spawn_counter: 0
      })
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
         :ok <-
           Production.can_queue?(city, type,
             granary_available?: granary_available?(state, city),
             bronze_age?: bronze_age?(state, city),
             copper_access?: copper_access?(state, city),
             archery?: archery?(state, city)
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

  defp parse_item_type(type)
       when type in [:settler, :worker, :warrior, :granary, :bronze_spearman, :archer],
       do: {:ok, type}

  defp parse_item_type("settler"), do: {:ok, :settler}
  defp parse_item_type("worker"), do: {:ok, :worker}
  defp parse_item_type("warrior"), do: {:ok, :warrior}
  defp parse_item_type("granary"), do: {:ok, :granary}
  defp parse_item_type("bronze_spearman"), do: {:ok, :bronze_spearman}
  # QA issue da39e50b — the Archery tech unlocked nothing; a first-pass
  # Archer (melee-for-now — see `Production`'s own moduledoc) buildable
  # once the city's owner has completed Archery.
  defp parse_item_type("archer"), do: {:ok, :archer}
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
         :ok <- validate_assign(state.world, city, from_tile, to_tile) do
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

  defp validate_assign(_world, _city, _from_tile, nil), do: :ok

  # A `to_tile` with no paired `from_tile` grows the worked-tile count
  # by one — refused once the city is already at its population cap
  # (`City.changeset/2`'s `validate_worked_tiles_within_size/1` encodes
  # the same "cannot exceed size" invariant, but this write path
  # persists via a raw `Repo.update_all` that never runs the
  # changeset, so the cap has to be checked here too — issue
  # 7509c453). A paired swap (`from_tile` supplied) never changes the
  # count, so it stays allowed even at the cap.
  defp validate_assign(world, city, from_tile, tile) do
    cond do
      tile == city.tile_id -> {:error, :invalid_tile}
      tile not in city.territory -> {:error, :not_territory}
      tile in city.worked_tiles -> {:error, :already_worked}
      not Yields.workable?(Regions.terrain(world, tile)) -> {:error, :invalid_terrain}
      is_nil(from_tile) and length(city.worked_tiles) >= city.size -> {:error, :size_exceeded}
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
         :ok <- validate_improvement_terrain(state, unit.tile_id, kind, unit.player_id),
         :ok <- validate_improvement_slot(state, unit.tile_id, kind) do
      improvement = persist_start_improvement!(state, unit, kind)
      {:ok, put_improvement(state, kind, unit.tile_id, improvement)}
    end
  end

  # QA issue 5656770d — a Road (`state.roads`) and the tile's yield
  # improvement (Farm/Mine/Pasture, `state.improvements`) are
  # independent slots; see `Improvement`'s own moduledoc.
  defp put_improvement(state, :road, tile_id, improvement),
    do: %{state | roads: Map.put(state.roads, tile_id, improvement)}

  defp put_improvement(state, _kind, tile_id, improvement),
    do: %{state | improvements: Map.put(state.improvements, tile_id, improvement)}

  # QA issue 8aa2c571 — see `BrokenOaths.Game.cancel_improvement/3`'s doc.
  # Deletes the DB row outright (rather than merely clearing
  # `builder_unit_id`, the way a worker simply walking away already
  # does at a turn boundary — see `BrokenOaths.Game.Turn.advance_improvement/2`)
  # so that SLOT comes back completely empty, free for any kind that
  # shares it. QA issue 5656770d — a tile can now carry an active build
  # in BOTH slots at once (a Road building alongside a Farm, say); this
  # cancels whichever one `active_building/2` finds, preferring the
  # yield slot (`state.improvements`) over the road slot (`state.roads`)
  # when — the rare case — both are mid-build on the same tile, the same
  # tie-break `visible_improvements/2`'s list order and the UI's own
  # `worker_current_dig/2` (`Enum.find`, first match) already use.
  defp do_cancel_improvement(state, user, unit_id) do
    with {:ok, unit} <- owned_worker(state, user, unit_id),
         {:ok, collection} <- active_building(state, unit.tile_id) do
      kind = state |> Map.fetch!(collection) |> Map.fetch!(unit.tile_id) |> Map.fetch!(:kind)
      persist_cancel_improvement!(state, unit.tile_id, kind)
      new_collection = state |> Map.fetch!(collection) |> Map.delete(unit.tile_id)
      {:ok, Map.put(state, collection, new_collection)}
    end
  end

  # Only a `:building` improvement is cancelable — the same status
  # `BrokenOathsWeb.GameLive.Play`'s `worker_current_dig/2` gates the
  # dig-progress badge (and the Cancel button beside it) on, so the
  # button never offers to cancel something that isn't there to cancel
  # (a `:complete` improvement, or a `:pillaged` one nobody has resumed
  # repairing yet). Returns which COLLECTION (`:improvements` or
  # `:roads`) the active build lives in, since a tile can now have one
  # building in each independently (QA issue 5656770d).
  defp active_building(state, tile_id) do
    cond do
      match?(%{status: :building}, Map.get(state.improvements, tile_id)) -> {:ok, :improvements}
      match?(%{status: :building}, Map.get(state.roads, tile_id)) -> {:ok, :roads}
      true -> {:error, :no_active_build}
    end
  end

  defp persist_cancel_improvement!(state, tile_id, kind) do
    case Repo.get_by(Improvement, world_id: state.world.id, tile_id: tile_id, kind: kind) do
      nil -> :ok
      improvement -> do_delete_improvement(improvement)
    end
  end

  defp do_delete_improvement(improvement) do
    {:ok, _deleted} = Repo.delete(improvement)
    :ok
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

  defp parse_kind(kind) when kind in [:farm, :mine, :road, :pasture], do: {:ok, kind}
  defp parse_kind("farm"), do: {:ok, :farm}
  defp parse_kind("mine"), do: {:ok, :mine}
  defp parse_kind("road"), do: {:ok, :road}
  defp parse_kind("pasture"), do: {:ok, :pasture}
  defp parse_kind(_other), do: {:error, :invalid_improvement}

  # Pasture (story 905) gates on the tile's RESOURCE
  # (`Improvement.resource_allowed?/1` — Cattle/Sheep only) and the
  # building worker's OWNER having researched Animal Husbandry
  # (`Research.pasture_enabled?/1`), never on `Improvement.allowed?/2`'s
  # terrain table — that table is Farm/Mine/Road's own gate only.
  defp validate_improvement_terrain(state, tile_id, :pasture, player_id) do
    cond do
      Regions.tile_class(state.world, tile_id) != :land ->
        {:error, :invalid_terrain}

      not Improvement.resource_allowed?(Resources.at(state.world, tile_id)) ->
        {:error, :invalid_terrain}

      not Research.pasture_enabled?(player_research_for(state, player_id)) ->
        {:error, :invalid_terrain}

      true ->
        :ok
    end
  end

  # Mine (QA issue 5a30ad3f) gates on the resource-aware
  # `Improvement.mine_allowed?/2` — Hills relief OR a Copper deposit that
  # `Resources.ensure_reachable_copper/3` may have guaranteed onto a
  # non-Hills tile — rather than the terrain-only `allowed?/2` below.
  defp validate_improvement_terrain(state, tile_id, :mine, _player_id) do
    cond do
      Regions.tile_class(state.world, tile_id) != :land ->
        {:error, :invalid_terrain}

      not Improvement.mine_allowed?(
        Regions.terrain(state.world, tile_id),
        Resources.at(state.world, tile_id)
      ) ->
        {:error, :invalid_terrain}

      true ->
        :ok
    end
  end

  defp validate_improvement_terrain(state, tile_id, kind, _player_id) do
    cond do
      Regions.tile_class(state.world, tile_id) != :land ->
        {:error, :invalid_terrain}

      not Improvement.allowed?(kind, Regions.terrain(state.world, tile_id)) ->
        {:error, :invalid_terrain}

      true ->
        :ok
    end
  end

  # QA issue 5656770d — Road and the tile's yield improvement
  # (Farm/Mine/Pasture) occupy INDEPENDENT slots (see `Improvement`'s
  # own moduledoc): a `:road` request only ever checks `state.roads`
  # for this tile, and every other kind only ever checks
  # `state.improvements` — neither slot's occupant blocks the other, so
  # a worker can build a Road across a tile that already carries (or is
  # still building) a Farm/Mine/Pasture, and vice versa.
  #
  # Within a single slot, a completed improvement refuses any second
  # dig. An in-progress one of the SAME kind just reattaches (any
  # worker may resume a frozen dig — improvements aren't owned); a
  # DIFFERENT kind already mid-build in the SAME slot is refused rather
  # than silently switched (this can only ever happen for the yield
  # slot, since `state.roads` only ever holds `:road`). A pillaged one
  # (story 893) is the same "resume the same kind" story, just entered
  # from `:pillaged` instead of `:building`.
  defp validate_improvement_slot(state, tile_id, :road),
    do: slot_status(Map.get(state.roads, tile_id), :road)

  defp validate_improvement_slot(state, tile_id, kind),
    do: slot_status(Map.get(state.improvements, tile_id), kind)

  defp slot_status(nil, _kind), do: :ok
  defp slot_status(%{status: :complete}, _kind), do: {:error, :occupied_improvement}
  defp slot_status(%{status: :building, kind: kind}, kind), do: :ok
  defp slot_status(%{status: :building}, _kind), do: {:error, :invalid_improvement}
  defp slot_status(%{status: :pillaged, kind: kind}, kind), do: :ok
  defp slot_status(%{status: :pillaged}, _kind), do: {:error, :invalid_improvement}

  # A truly NEW improvement (no row yet on this tile) resolves its
  # `duration` once, here, from the BUILDING WORKER'S OWNER's research
  # (story 902, criterion 7628 — see `Improvement`'s own moduledoc,
  # "Mining's 3-turn unlock") — a worker resuming an EXISTING row
  # (interrupted, or pillaged-and-repairing) never re-resolves it, so a
  # dig's target pace is fixed at build-start regardless of who later
  # finishes it.
  defp persist_start_improvement!(state, unit, kind) do
    case Repo.get_by(Improvement, world_id: state.world.id, tile_id: unit.tile_id, kind: kind) do
      nil ->
        {:ok, improvement} =
          %Improvement{}
          |> Improvement.changeset(%{
            world_id: state.world.id,
            tile_id: unit.tile_id,
            kind: kind,
            progress: 0,
            status: :building,
            duration: improvement_duration(state, unit, kind),
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

  defp improvement_duration(state, unit, :mine),
    do: Research.mine_duration(player_research_for(state, unit.player_id))

  defp improvement_duration(_state, _unit, kind), do: Improvement.duration(kind)

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
      charges: Map.get(unit, :charges, 3),
      # Story 915 — see `BrokenOathsSpex.Story915.Criterion7734Spex`'s
      # own "flagged temporary" read: the sanctioned board-state bridge
      # (`Fixtures.player_units/2`) needs this on every unit map, not
      # just the owner's own view, since a temporary rebellion unit's
      # own flag is public knowledge (it's on the board).
      temporary: Map.get(unit, :temporary, false),
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

    age = Research.age(player_research_for(state, city.player_id))

    %{
      id: city.id,
      name: city.name,
      tile_id: city.tile_id,
      size: city.size,
      food: city.food,
      food_threshold: Yields.threshold(city.size, age),
      production: Production.flat_base() + worked_production,
      queue: city.queue,
      territory: city.territory,
      worked_tiles: city.worked_tiles,
      hp: city.hp,
      defense: CityDefense.defensive_strength(city, Map.values(state.units)),
      # QA issue 1c47edff "Granary confusion" — `has_granary` was
      # tracked on the `City` schema and already fed `Yields.
      # accrue_food/3`'s math, but never made it into THIS map, the one
      # `Game.player_cities/2` actually hands to `GameLive.CityPanel` —
      # so a built Granary had no way to ever show up in the UI at all.
      has_granary: city.has_granary,
      # Story 906 — `:free` (no badge), `:broken` (0 HP, not yet
      # entered), or `:occupied` (captured) — `Siege.status/1`'s own
      # single source of truth for `GameLive.CityPanel`'s `city-status`
      # badge.
      status: Siege.status(city),
      occupied_by_player_id: Map.get(city, :occupied_by_player_id)
    }
  end

  # `%{user_id:, email:}` for every player `user` has discovered — the
  # future `KnownPlayersPanel`'s own read, exposed here (not built
  # there yet, story 899 scope) the same way `player_cities/2` was
  # exposed well before `GameLive.CityPanel` consumed it.
  defp known_players(state, user) do
    case find_player(state, user.id) do
      nil ->
        []

      player ->
        known = Map.get(state, :known_players, MapSet.new())

        for {viewer_id, discovered_id} <- known, viewer_id == player.id do
          discovered_player = Map.fetch!(state.players, discovered_id)
          discovered_user = Users.get_user!(discovered_player.user_id)
          %{user_id: discovered_user.id, email: discovered_user.email}
        end
    end
  end

  # -------------------------------------------------------------------
  # Alliances (story 901)
  # -------------------------------------------------------------------

  defp list_alliances(state, user) do
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
    # at all (`Stewardship.steward_role/4`'s own `:ally` clause reads
    # straight off an accepted `Alliance`) — a merely `:proposed` row,
    # or an online ally, carries no `steward_view/2` payload.
    stewardable? = alliance.status == :accepted and not online?

    %{
      id: alliance.id,
      status: alliance.status,
      proposed_by_me?: alliance.proposer_player_id == my_player_id,
      other_user_id: other_user.id,
      other_email: other_user.email,
      # Story 910: same "offer Steward only while offline" status
      # `format_vassal/2` already carries.
      online?: online?,
      steward: if(stewardable?, do: steward_view(state, other_player), else: nil)
    }
  end

  defp do_propose_alliance(state, user, other_user) do
    with {:ok, player} <- fetch_player(state, user.id),
         {:ok, other_player} <- fetch_player(state, other_user.id),
         existing = find_alliance(state.world.id, player.id, other_player.id),
         {:ok, changeset} <-
           Cooperation.propose(existing, state.world.id, player.id, other_player.id) do
      Repo.insert_or_update(changeset)
    end
  end

  defp do_accept_alliance(state, user, alliance_id) do
    with {:ok, player} <- fetch_player(state, user.id),
         {:ok, alliance} <- fetch_alliance(alliance_id),
         {:ok, changeset} <- Cooperation.accept(alliance, player.id) do
      Repo.update(changeset)
    end
  end

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
      email: vassal_user.email,
      tribute_rate: vassalage.tribute_rate,
      oath_strain: vassalage.oath_strain,
      levy_status:
        levy_status_for(state.world.id, vassalage.lord_player_id, vassalage.vassal_player_id),
      # Story 910: whether this vassal is currently reachable to steward
      # — `GameLive.VassalsPanel`'s own Steward affordance only offers
      # itself against an OFFLINE household member.
      online?: online?,
      # QA issue bd93cc0a: the production-stewardship + emergency-defend
      # click-through's own data source — `nil` while online (nothing to
      # steward yet), `steward_view/2`'s real payload once offline.
      steward: if(online?, do: nil, else: steward_view(state, vassal_player)),
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
              lord_email: lord_user.email,
              tribute_rate: vassalage.tribute_rate,
              oath_strain: vassalage.oath_strain,
              agenda_pending?: Vassalization.agenda_pending?(vassalage),
              levy_status: levy_status_for(state.world.id, vassalage.lord_player_id, player.id),
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

  # The vassal has exactly one lord at a time, so at most one levy
  # history between the two of them — the most recent (highest id) is
  # "the" levy both the lord's own row and the vassal's own badge read.
  defp levy_status_for(world_id, lord_player_id, vassal_player_id) do
    Levy
    |> where(
      [l],
      l.world_id == ^world_id and l.lord_player_id == ^lord_player_id and
        l.vassal_player_id == ^vassal_player_id
    )
    |> order_by([l], desc: l.id)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> nil
      levy -> levy.status
    end
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

  # Same "diff-and-persist" status every other in-place unit mutation
  # already has (`Turn`'s own combat, etc.) — the caller runs this
  # through `persist_tick/2`, which deletes any unit missing from the
  # returned `state.units` (`persist_unit_changes/2`).
  defp do_resolve_garrison_fate(state, user, city_id, choice) do
    player = find_player(state, user.id)
    city = Map.get(state.cities, city_id)

    cond do
      is_nil(player) or is_nil(city) ->
        {:error, :invalid_target}

      city.occupied_by_player_id != player.id ->
        {:error, :not_owner}

      true ->
        to_remove = Siege.resolve_garrison_fate(choice, city, Map.values(state.units))

        new_state =
          state
          |> Map.update!(:units, &Map.drop(&1, to_remove))
          |> apply_garrison_fate_honor(player.id, choice)

        {:ok, new_state}
    end
  end

  # QA issue ed1ff4c0 — the conqueror's own Honor consequence for their
  # garrison-fate choice (design doc: executing costs a small Honor
  # penalty, releasing is neutral). Folded into the SAME `new_state`
  # `do_resolve_garrison_fate/4` already returns, so the caller's own
  # `persist_tick/2` picks up the `state.players` diff exactly like
  # `resolve_steward_defend/5`'s own sabotage-penalty write above.
  defp apply_garrison_fate_honor(state, player_id, :execute) do
    update_in(state.players[player_id].honor, &Siege.apply_execute_honor_penalty/1)
  end

  defp apply_garrison_fate_honor(state, _player_id, :release), do: state

  defp do_issue_levy(state, user, vassal_user_id, target_user_id, share) do
    with {:ok, lord_player} <- fetch_player(state, user.id),
         {:ok, vassal_player} <- fetch_player(state, vassal_user_id),
         {:ok, target_player} <- fetch_player(state, target_user_id),
         {:ok, _vassalage} <- fetch_vassalage(state, lord_player.id, vassal_player.id) do
      Tribute.issue_changeset(
        state.world.id,
        lord_player.id,
        vassal_player.id,
        target_player.id,
        share
      )
      |> Repo.insert()
    end
  end

  defp do_answer_levy(state, user, lord_user_id) do
    with {:ok, vassal_player} <- fetch_player(state, user.id),
         {:ok, lord_player} <- fetch_player(state, lord_user_id),
         {:ok, levy} <- fetch_pending_levy(state.world.id, lord_player.id, vassal_player.id) do
      Tribute.answer_changeset(levy) |> Repo.update()
    end
  end

  defp do_refuse_levy(state, user, lord_user_id) do
    with {:ok, vassal_player} <- fetch_player(state, user.id),
         {:ok, lord_player} <- fetch_player(state, lord_user_id),
         {:ok, levy} <- fetch_pending_levy(state.world.id, lord_player.id, vassal_player.id),
         {:ok, refused} <- Tribute.refuse_changeset(levy) |> Repo.update(),
         {:ok, vassalage} <- fetch_vassalage(state, lord_player.id, vassal_player.id),
         {:ok, _vassalage} <- Tribute.spike_oath_strain(vassalage) |> Repo.update() do
      new_state =
        update_in(state.players[vassal_player.id].honor, &Tribute.apply_refusal_honor_penalty/1)

      {:ok, refused, new_state}
    end
  end

  # Story 913: `user` (the lord) gifts `vassal_user_id` — eases their
  # Oath Strain by `OathStrain.gift_ease/0`.
  defp do_gift_vassal(state, user, vassal_user_id) do
    with {:ok, lord_player} <- fetch_player(state, user.id),
         {:ok, vassal_player} <- fetch_player(state, vassal_user_id),
         {:ok, vassalage} <- fetch_vassalage(state, lord_player.id, vassal_player.id) do
      new_strain = OathStrain.ease_gift(vassalage.oath_strain)
      Vassalage.changeset(vassalage, %{oath_strain: new_strain}) |> Repo.update()
    end
  end

  # Story 913: `user` (the lord) and `vassal_user_id` declare
  # `enemy_user_id` a shared enemy — eases the vassal's Oath Strain by
  # `OathStrain.shared_enemy_ease/0`. `enemy_user_id` only needs to be a
  # real, known player (validated via `fetch_player/2`) — nothing about
  # the declaration itself is persisted beyond the strain ease.
  defp do_declare_shared_enemy(state, user, vassal_user_id, enemy_user_id) do
    with {:ok, lord_player} <- fetch_player(state, user.id),
         {:ok, vassal_player} <- fetch_player(state, vassal_user_id),
         {:ok, _enemy_player} <- fetch_player(state, enemy_user_id),
         {:ok, vassalage} <- fetch_vassalage(state, lord_player.id, vassal_player.id) do
      new_strain = OathStrain.ease_shared_enemy(vassalage.oath_strain)
      Vassalage.changeset(vassalage, %{oath_strain: new_strain}) |> Repo.update()
    end
  end

  # Story 913 (criterion 7722): `user` (the vassal) marks their own
  # bond with `lord_user_id` unhonored — spikes their own Oath Strain by
  # `OathStrain.protection_pact_spike/0`. See this handler's own
  # `handle_call/3` doc for how this differs from the real story 914
  # broken-pact resolution.
  defp do_mark_pact_unhonored(state, user, lord_user_id) do
    with {:ok, vassal_player} <- fetch_player(state, user.id),
         {:ok, lord_player} <- fetch_player(state, lord_user_id),
         {:ok, vassalage} <- fetch_vassalage(state, lord_player.id, vassal_player.id) do
      new_strain = OathStrain.spike_broken_protection_pact(vassalage.oath_strain)
      Vassalage.changeset(vassalage, %{oath_strain: new_strain}) |> Repo.update()
    end
  end

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

  defp fetch_pending_levy(world_id, lord_player_id, vassal_player_id) do
    Levy
    |> where(
      [l],
      l.world_id == ^world_id and l.lord_player_id == ^lord_player_id and
        l.vassal_player_id == ^vassal_player_id and l.status == :pending
    )
    |> order_by([l], desc: l.id)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      levy -> {:ok, levy}
    end
  end

  # -------------------------------------------------------------------
  # Rebellion (stories 915/919)
  # -------------------------------------------------------------------

  # `user`'s own occupied cities under `lord_player_id` right now — the
  # exact `cities()` list `Resolution.resolve_risings/4`/`city_rises?/4`
  # need, shared by the preview and the real commit so both ALWAYS
  # agree (criterion 7732: "no hidden dice roll").
  defp rebel_occupied_cities(state, vassal_player_id, lord_player_id) do
    state.cities
    |> Map.values()
    |> Enum.filter(
      &(&1.player_id == vassal_player_id and &1.occupied_by_player_id == lord_player_id)
    )
  end

  # Story 915, criterion 7732 — read-only inspection: the SAME
  # `Resolution.city_rises?/4`/`army_size/1` inputs (the lord's own
  # Honor, this vassalage's own tribute rate, the world's own seed)
  # `do_declare_independence/3` commits with below, never live RNG.
  defp do_independence_preview(state, user, lord_user_id) do
    with {:ok, vassal_player} <- fetch_player(state, user.id),
         {:ok, lord_player} <- fetch_player(state, lord_user_id),
         {:ok, vassalage} <- fetch_vassalage(state, lord_player.id, vassal_player.id) do
      cities = rebel_occupied_cities(state, vassal_player.id, lord_player.id)

      {risen_ids, _loyal_ids} =
        Resolution.resolve_risings(
          lord_player.honor,
          vassalage.tribute_rate,
          state.world.seed,
          cities
        )

      verdicts = for city <- cities, do: %{city_id: city.id, will_rise?: city.id in risen_ids}
      army_size = Resolution.army_size(vassalage.oath_strain)

      {:ok, %{cities: verdicts, army_size: army_size}}
    end
  end

  # Story 915 — the full commit: severs the Vassalage (`:broken`, so
  # `apply_tribute/1`'s own `active_vassalages/1` read never finds it
  # again — "no further tribute transfers"), resolves risings with the
  # SAME formula the preview already showed, de-occupies + heals every
  # risen city (its former garrison defecting to the rebel), spawns the
  # temporary rebellion army flagged `temporary: true`, and creates the
  # first-class `Rebellion` row. Returns `{:ok, %{rebellion:, message:},
  # new_state, lord_events}` — `lord_events` is the former lord's own
  # `{:rebellion_declared, ...}` notification, broadcast by the caller
  # alongside the ordinary `:vassals_changed`/`:units_changed`/
  # `:cities_changed` refresh triggers; the rebel's own "game:rebellion"
  # push is built straight from this same reply by `GameLive.Play`
  # (no broadcast round-trip needed for the caller's own session).
  defp do_declare_independence(state, user, lord_user_id) do
    with {:ok, vassal_player} <- fetch_player(state, user.id),
         {:ok, lord_player} <- fetch_player(state, lord_user_id),
         {:ok, vassalage} <- fetch_vassalage(state, lord_player.id, vassal_player.id) do
      cities = rebel_occupied_cities(state, vassal_player.id, lord_player.id)

      {risen_ids, loyal_ids} =
        Resolution.resolve_risings(
          lord_player.honor,
          vassalage.tribute_rate,
          state.world.seed,
          cities
        )

      army_size = Resolution.army_size(vassalage.oath_strain)

      {:ok, rebellion} =
        %Rebellion{}
        |> Rebellion.changeset(%{
          world_id: state.world.id,
          rebel_player_id: vassal_player.id,
          former_lord_player_id: lord_player.id,
          status: :active,
          started_turn: state.turn,
          risen_city_ids: risen_ids,
          loyal_city_ids: loyal_ids,
          army_size: army_size
        })
        |> Repo.insert()

      {:ok, _severed} = Vassalage.changeset(vassalage, %{status: :broken}) |> Repo.update()

      risen_cities = Enum.filter(cities, &(&1.id in risen_ids))

      {new_cities, new_units} =
        rise_cities(state.cities, state.units, risen_cities, vassal_player.id, lord_player.id)

      new_units =
        spawn_rebellion_army(
          %{state | units: new_units},
          rebellion,
          vassal_player.id,
          risen_cities,
          army_size
        )

      new_state = %{state | cities: new_cities, units: new_units}

      lord_user = Users.get_user!(lord_player.user_id)
      rebel_user = Users.get_user!(vassal_player.user_id)

      lord_events = [
        {:rebellion_declared, lord_user.id, "#{rebel_user.email} has declared independence!",
         risen_ids}
      ]

      {:ok, %{rebellion: rebellion, message: rebellion_message(risen_ids)}, new_state,
       lord_events}
    end
  end

  defp rebellion_message([]), do: "You have declared independence — the war begins."
  defp rebellion_message(_risen), do: "Your cities rise — a rebellion rallies to your cause!"

  # De-occupies + fully heals every one of `risen_cities` and defects
  # whichever of `lord_player_id`'s own units still stand on each one's
  # own tile to `vassal_player_id` — criterion 7733's own "the lord's
  # garrison stationed there defects". Scoped to the FORMER LORD's own
  # units only, mirroring `Siege.fallen_garrison/2`'s own "never the
  # conqueror's" discipline (here: never some unrelated third party's
  # unit that happens to be passing through). Persisted immediately —
  # `occupied_by_player_id`/`hp` on the city row, `player_id` on each
  # defecting unit — since `persist_tick/2`'s own generic unit diff
  # never tracks a `player_id` change.
  defp rise_cities(cities, units, risen_cities, vassal_player_id, lord_player_id) do
    Enum.reduce(risen_cities, {cities, units}, fn city, {cities_acc, units_acc} ->
      freed_hp = CityDefense.max_hp()

      Repo.update_all(from(c in City, where: c.id == ^city.id),
        set: [occupied_by_player_id: nil, hp: freed_hp]
      )

      freed_city = %{city | occupied_by_player_id: nil, hp: freed_hp}

      defecting_ids =
        units_acc
        |> Map.values()
        |> Enum.filter(&(&1.tile_id == city.tile_id and &1.player_id == lord_player_id))
        |> Enum.map(& &1.id)

      if defecting_ids != [] do
        Repo.update_all(from(u in Unit, where: u.id in ^defecting_ids),
          set: [player_id: vassal_player_id]
        )
      end

      new_units_acc =
        Enum.reduce(defecting_ids, units_acc, fn id, acc ->
          Map.update!(acc, id, &%{&1 | player_id: vassal_player_id})
        end)

      {Map.put(cities_acc, city.id, freed_city), new_units_acc}
    end)
  end

  # Spawns `army_size` real `:warrior` units, owned by the rebel and
  # flagged `temporary: true`/`rebellion_id:` — on the FIRST risen
  # city's own tile when one exists, else wherever the rebel's own Lord
  # (or, failing that, any of their own units) currently stands — a
  # fully-occupied vassal still has real units on the board even with
  # zero free cities. Declaring is always available and always raises
  # SOME token force (`OathStrain.rebellion_army_size/1`'s own
  # moduledoc); this only ever spawns nothing if the rebel somehow has
  # no anchor tile at all (never true for a real player, who always
  # carries at least their own Lord unit).
  defp spawn_rebellion_army(state, rebellion, vassal_player_id, risen_cities, army_size) do
    case {army_size, rebellion_spawn_tile(state, vassal_player_id, risen_cities)} do
      {0, _tile} ->
        state.units

      {_size, nil} ->
        state.units

      {size, tile_id} ->
        Enum.reduce(1..size, state.units, fn _, units_acc ->
          unit =
            insert_temporary_unit!(
              state.world.id,
              vassal_player_id,
              :warrior,
              tile_id,
              rebellion.id
            )

          Map.put(units_acc, unit.id, unit)
        end)
    end
  end

  defp rebellion_spawn_tile(_state, _vassal_player_id, [city | _risen_cities]), do: city.tile_id

  defp rebellion_spawn_tile(state, vassal_player_id, []) do
    units = state.units |> Map.values() |> Enum.filter(&(&1.player_id == vassal_player_id))

    case Enum.find(units, &(&1.type == :lord)) do
      %{tile_id: tile_id} ->
        tile_id

      nil ->
        case units do
          [%{tile_id: tile_id} | _] -> tile_id
          [] -> nil
        end
    end
  end

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
      rebel_email: rebel_user && rebel_user.email,
      former_lord_user_id: lord_user && lord_user.id,
      former_lord_email: lord_user && lord_user.email,
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
          offered_by_email: offering_user && offering_user.email,
          outcome: offer.outcome,
          reparations_gold: offer.reparations_gold
        }
    end
  end

  # The ONE active Rebellion (if any) between two players, whichever
  # direction — `validate_attack/4`'s own rebellion-war exception and
  # the peace offer/accept/reject seam below both key off this same
  # lookup.
  defp find_active_rebellion_between(state, player_a_id, player_b_id) do
    Rebellion
    |> where([r], r.world_id == ^state.world.id and r.status == :active)
    |> where(
      [r],
      (r.rebel_player_id == ^player_a_id and r.former_lord_player_id == ^player_b_id) or
        (r.rebel_player_id == ^player_b_id and r.former_lord_player_id == ^player_a_id)
    )
    |> Repo.one()
  end

  # Story 915: the narrow, rebellion-scoped PvP exception `validate_attack/4`
  # needs — mirrors `protecting_lord_may_strike?/3`'s own technique
  # (widen the CALLER-side gate, never touch `Combat.hostile?/2` itself).
  defp rebellion_war?(state, player_a_id, player_b_id)
       when not is_nil(player_a_id) and not is_nil(player_b_id) do
    not is_nil(find_active_rebellion_between(state, player_a_id, player_b_id))
  end

  defp rebellion_war?(_state, _player_a_id, _player_b_id), do: false

  defp peace_offers(state), do: Map.get(state, :peace_offers, %{})

  defp parse_peace_outcome("independence"), do: {:ok, :independence}
  defp parse_peace_outcome("restored_vassal"), do: {:ok, :restored_vassal}

  defp parse_peace_outcome(outcome) when outcome in [:independence, :restored_vassal],
    do: {:ok, outcome}

  defp parse_peace_outcome(_other), do: {:error, :invalid_outcome}

  defp do_offer_peace(state, user, counterparty_user_id, outcome, reparations_gold) do
    with {:ok, offering_player} <- fetch_player(state, user.id),
         {:ok, counterparty_player} <- fetch_player(state, counterparty_user_id),
         %Rebellion{} = rebellion <-
           find_active_rebellion_between(state, offering_player.id, counterparty_player.id),
         {:ok, outcome_atom} <- parse_peace_outcome(outcome) do
      offer = %{
        offered_by_player_id: offering_player.id,
        outcome: outcome_atom,
        reparations_gold: reparations_gold
      }

      new_state = Map.put(state, :peace_offers, Map.put(peace_offers(state), rebellion.id, offer))
      {:ok, new_state}
    else
      nil -> {:error, :no_active_rebellion}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_accept_peace(state, user, counterparty_user_id) do
    with {:ok, accepting_player} <- fetch_player(state, user.id),
         {:ok, offering_player} <- fetch_player(state, counterparty_user_id),
         %Rebellion{} = rebellion <-
           find_active_rebellion_between(state, accepting_player.id, offering_player.id),
         offering_player_id = offering_player.id,
         %{offered_by_player_id: ^offering_player_id} = offer <-
           Map.get(peace_offers(state), rebellion.id) do
      new_state =
        state
        |> apply_peace_resolution(
          rebellion,
          offer.outcome,
          offer.reparations_gold,
          offering_player.id,
          accepting_player.id
        )
        |> then(&Map.put(&1, :peace_offers, Map.delete(peace_offers(&1), rebellion.id)))

      {:ok, new_state}
    else
      nil -> {:error, :no_pending_offer}
      %{} -> {:error, :no_pending_offer}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_reject_peace(state, user, counterparty_user_id) do
    with {:ok, rejecting_player} <- fetch_player(state, user.id),
         {:ok, offering_player} <- fetch_player(state, counterparty_user_id),
         %Rebellion{} = rebellion <-
           find_active_rebellion_between(state, rejecting_player.id, offering_player.id) do
      new_state = Map.put(state, :peace_offers, Map.delete(peace_offers(state), rebellion.id))
      {:ok, new_state}
    else
      nil -> {:error, :no_active_rebellion}
      {:error, reason} -> {:error, reason}
    end
  end

  # Story 919, criterion 7754 — "nobody loses cities in a peace": frees
  # AND fully heals every one of the rebel's own cities, risen or
  # loyal, regardless of `outcome`. Reparations (optional) move from
  # whoever ACCEPTED to whoever OFFERED — the offering side proposed
  # (and, per the design, is compensated for) the terms.
  defp apply_peace_resolution(
         state,
         rebellion,
         outcome,
         reparations_gold,
         offering_player_id,
         accepting_player_id
       ) do
    {:ok, ended} = Resolution.resolve_peace(rebellion, outcome, reparations_gold) |> Repo.update()

    state =
      state
      |> free_rebel_cities(ended)
      |> disband_temporary_army(ended.id)
      |> transfer_reparations(accepting_player_id, offering_player_id, reparations_gold)

    if outcome == :restored_vassal do
      maybe_revassalize(state, ended.former_lord_player_id, ended.rebel_player_id)
    end

    state
  end

  # Story 919 — the turn-boundary lifecycle sweep: every ACTIVE
  # rebellion in this world settles into EXACTLY ONE ended status the
  # moment its own end condition reads true (`Rebellion.changeset/2`'s
  # own once-only transition guard makes a repeat call to either
  # `Resolution.win_independence/1`/`crush/1` a no-op error this
  # function never triggers a second time — see `process_rebellion_
  # ending/2`'s own `status: :active` scope). A no-op while `Game.
  # feudal_enabled?/0` reads `false`, same belt-and-suspenders status
  # every other feudal tick phase already carries. Also run immediately
  # after an ordinary `queue_move` resolves (see that handler's own
  # call site) — a rebel's last free city can fall to an adjacent march
  # that itself never needed a fresh tick boundary to land.
  defp process_rebellion_endings(state, trigger \\ :tick) do
    if Game.feudal_enabled?() do
      Rebellion
      |> where([r], r.world_id == ^state.world.id and r.status == :active)
      |> Repo.all()
      |> Enum.reduce(state, &process_rebellion_ending(&2, &1, trigger))
    else
      state
    end
  end

  # `trigger` distinguishes an ordinary quiet turn boundary (`:tick`,
  # `run_tick/1`'s own call site) from an actual player move (`:move`,
  # `do_queue_move`'s own call site): `crushed?/2` and `independence_won?/3`
  # are both SAFE to check on either — neither can ever read true off a
  # mere tick with nothing new having happened (both require an actual
  # city-occupation change or elapsed-turn count, never a side effect of
  # checking itself). `rebel_defeated?/2`, by contrast, would otherwise
  # read true on the VERY FIRST quiet tick for a rebel whose cities
  # never rose at all (see `Resolution.rebel_defeated?/2`'s own
  # moduledoc) — indistinguishable from criterion 7731's own "one quiet
  # turn boundary, still at war" expectation unless it's scoped to an
  # actual move (a real siege attempt, however it resolves) instead.
  defp process_rebellion_ending(state, rebellion, trigger) do
    cities = Map.values(state.cities)

    cond do
      Resolution.independence_won?(rebellion, cities, state.turn) ->
        end_rebellion_independence_won(state, rebellion)

      Resolution.crushed?(rebellion, cities) ->
        end_rebellion_crushed(state, rebellion)

      trigger == :move and Resolution.rebel_defeated?(rebellion, cities) ->
        end_rebellion_crushed(state, rebellion)

      true ->
        state
    end
  end

  # Story 919, criterion 7752 — "the severed oath becomes permanent and
  # the rebel is free": nothing further happens to the rebel's own
  # cities here (a risen city is already free; a loyal one the former
  # lord never lost stays theirs — "no separate reconquest mechanic",
  # criterion 7736). Only the temporary army disbands and the war state
  # clears.
  defp end_rebellion_independence_won(state, rebellion) do
    {:ok, ended} = Resolution.win_independence(rebellion) |> Repo.update()

    state = disband_temporary_army(state, ended.id)

    broadcast(state.world.id, [:vassals_changed, :units_changed])

    state
  end

  # Story 919, criterion 7753 — "the normal siege and vassalization
  # rules apply to the losing rebel, including being re-vassalized on
  # the loss of their last city": reuses the SAME real vassalization
  # write + `"game:vassalized"`/`"game:new_vassal"` notifications story
  # 906/907 already ship (`maybe_revassalize/3`), rather than a second,
  # parallel re-vassalization path — a rebel who's ALREADY back under
  # an active Vassalage (the ordinary siege pipeline beat this sweep to
  # it) is left untouched.
  defp end_rebellion_crushed(state, rebellion) do
    {:ok, ended} = Resolution.crush(rebellion) |> Repo.update()

    state = disband_temporary_army(state, ended.id)

    maybe_revassalize(state, ended.former_lord_player_id, ended.rebel_player_id)

    broadcast(state.world.id, [:vassals_changed, :units_changed])

    state
  end

  # Frees AND fully heals every one of `rebellion`'s own rebel-owned
  # cities — both `risen_city_ids` (already free, this is a no-op for
  # them) and `loyal_city_ids` (still occupied by the former lord) —
  # `apply_peace_resolution/5`'s own "nobody loses cities" contract.
  defp free_rebel_cities(state, rebellion) do
    city_ids = rebellion.risen_city_ids ++ rebellion.loyal_city_ids
    freed_hp = CityDefense.max_hp()

    if city_ids != [] do
      Repo.update_all(from(c in City, where: c.id in ^city_ids),
        set: [occupied_by_player_id: nil, hp: freed_hp]
      )
    end

    new_cities =
      Enum.reduce(city_ids, state.cities, fn id, acc ->
        case Map.get(acc, id) do
          nil -> acc
          city -> Map.put(acc, id, %{city | occupied_by_player_id: nil, hp: freed_hp})
        end
      end)

    %{state | cities: new_cities}
  end

  # Removes every unit `rebellion_id`-tagged to `rebellion_id` — the
  # temporary rebellion army, exactly once, the moment the war ends
  # (any status). Idempotent: a rebellion with no remaining temporary
  # units (already disbanded) simply deletes nothing.
  defp disband_temporary_army(state, rebellion_id) do
    Repo.delete_all(from(u in Unit, where: u.rebellion_id == ^rebellion_id))

    new_units =
      state.units
      |> Enum.reject(fn {_id, unit} -> Map.get(unit, :rebellion_id) == rebellion_id end)
      |> Map.new()

    %{state | units: new_units}
  end

  defp transfer_reparations(state, _from_player_id, _to_player_id, nil), do: state
  defp transfer_reparations(state, _from_player_id, _to_player_id, 0), do: state

  defp transfer_reparations(state, from_player_id, to_player_id, amount) do
    Repo.update_all(from(p in Player, where: p.id == ^from_player_id), inc: [gold: -amount])
    Repo.update_all(from(p in Player, where: p.id == ^to_player_id), inc: [gold: amount])

    state =
      put_in(state.players[from_player_id].gold, state.players[from_player_id].gold - amount)

    put_in(state.players[to_player_id].gold, state.players[to_player_id].gold + amount)
  end

  # Re-vassalizes `vassal_player_id` under `lord_player_id` via the
  # SAME real `Vassalization.vassalize_changeset/3` write + `"game:
  # vassalized"`/`"game:new_vassal"` notifications story 906/907 already
  # ship — a no-op (no double row, no duplicate notification) if an
  # active Vassalage between the two already exists (the ordinary siege
  # pipeline may have already re-created it in the same pass).
  defp maybe_revassalize(state, lord_player_id, vassal_player_id) do
    case Repo.get_by(Vassalage,
           world_id: state.world.id,
           vassal_player_id: vassal_player_id,
           status: :active
         ) do
      nil ->
        upsert_vassalage!(state.world.id, lord_player_id, vassal_player_id)

        broadcast(
          state.world.id,
          vassalization_broadcast(state, %{
            captor_player_id: lord_player_id,
            defeated_player_id: vassal_player_id
          })
        )

      _existing ->
        :ok
    end
  end

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

  # Story 902, criterion 7629 — whether `city`'s OWNER has completed
  # Pottery, the option `Production.can_queue?/3` needs to gate
  # `:granary` on (`Production` itself never touches `Research`).
  defp granary_available?(state, city),
    do: Research.granary_enabled?(player_research_for(state, city.player_id))

  # Story 903 — whether `city`'s OWNER is in the Bronze Age
  # (`Research.age/1`), the option `Production.can_queue?/3` needs to
  # gate `:bronze_spearman` on, same "Production never touches
  # Research" split `granary_available?/2` already establishes.
  defp bronze_age?(state, city),
    do: Research.age(player_research_for(state, city.player_id)) == :bronze_age

  # QA issue da39e50b — whether `city`'s OWNER has completed Archery,
  # the option `Production.can_queue?/3` needs to gate `:archer` on,
  # same "Production never touches Research" split `bronze_age?/2`
  # already establishes.
  defp archery?(state, city),
    do: Research.archery_enabled?(player_research_for(state, city.player_id))

  # Story 911 — whether `city` itself has Copper access: a Copper tile
  # anywhere in its own `territory` (worked or not — a pure ACCESS
  # GATE), the option `Production.can_queue?/3` needs to gate
  # `:bronze_spearman` on ALONGSIDE `bronze_age?/2` above. Unlike
  # `granary_available?/2`/`bronze_age?/2` (both resolve `Research`
  # over the city's OWNER), this reads `Resources.at/2` over the
  # CITY's own territory — Copper access is a per-city fact, not a
  # per-player one (two cities belonging to the same player can differ:
  # one may sit on Copper hills, the other may not).
  defp copper_access?(state, city),
    do: Enum.any?(city.territory, &(Resources.at(state.world, &1) == :copper))

  # Test-only helper for `:grant_copper_access_for_test` above: the
  # first tile id (mesh order) anywhere on `world` carrying Copper, or
  # `nil` if this particular seed/density placed none at all.
  defp find_any_copper_tile(world) do
    mesh = Globe.get(world.frequency)

    Enum.find_value(mesh.tiles, fn {tile_id, _tile} ->
      if Resources.at(world, tile_id) == :copper, do: tile_id
    end)
  end

  defp fetch_player(state, user_id) do
    case find_player(state, user_id) do
      nil -> {:error, :not_a_player}
      player -> {:ok, player}
    end
  end

  defp fetch_alliance(alliance_id) do
    case Repo.get(Alliance, alliance_id) do
      nil -> {:error, :not_found}
      alliance -> {:ok, alliance}
    end
  end

  # Same canonical (lowest id, highest id) pair `Alliance.changeset/2`
  # itself normalizes to — reading it back requires the query to match
  # that same order regardless of which of the two is "me" here.
  defp find_alliance(world_id, player_a_id, player_b_id) do
    {lo, hi} =
      if player_a_id <= player_b_id,
        do: {player_a_id, player_b_id},
        else: {player_b_id, player_a_id}

    Repo.get_by(Alliance, world_id: world_id, player_a_id: lo, player_b_id: hi)
  end

  # -------------------------------------------------------------------
  # Coordinated Rebellion — Pact of Broken Oaths (story 916)
  # -------------------------------------------------------------------

  # `user`'s own membership in a `:forming` pact, masked per criterion
  # 7738: every OTHER member's own `status` always reads `:invited`
  # ("Outstanding") no matter their real, secret answer — only the
  # reader's own row (`own_status`) ever tells the truth. `nil` while
  # `user` isn't currently a member of any `:forming` pact.
  defp pact_view(state, user) do
    case find_player(state, user.id) do
      nil ->
        nil

      player ->
        case fetch_forming_pact_for_player(state.world.id, player.id) do
          nil -> nil
          pact -> format_pact_view(state, pact, player.id)
        end
    end
  end

  defp format_pact_view(state, pact, viewer_player_id) do
    own_member = Enum.find(pact.members, &(&1.player_id == viewer_player_id))

    members =
      for member <- pact.members do
        member_player = Map.fetch!(state.players, member.player_id)
        member_user = Users.get_user!(member_player.user_id)

        status =
          if member.player_id == viewer_player_id,
            do: member.commit_status,
            else: :invited

        %{user_id: member_user.id, email: member_user.email, status: status}
      end

    %{
      id: pact.id,
      strike_turn: pact.strike_turn,
      own_status: own_member.commit_status,
      informer?: own_member.informer,
      members: members
    }
  end

  defp fetch_forming_pact_for_player(world_id, player_id) do
    pact_id =
      from(m in RebellionPactMember,
        join: p in RebellionPact,
        on: p.id == m.rebellion_pact_id,
        where: m.player_id == ^player_id and p.world_id == ^world_id and p.status == :forming,
        select: p.id
      )
      |> Repo.one()

    case pact_id do
      nil -> nil
      id -> RebellionPact |> Repo.get!(id) |> Repo.preload(:members)
    end
  end

  # Every FELLOW vassal of `user`'s own lord — `[]` for a free player,
  # or a vassal with no fellow vassals under the same lord. Deliberately
  # never excludes a fellow vassal already invited/committed elsewhere
  # (criterion 7737's own second `then_` re-toggles the composer AFTER
  # the pact already exists and still expects the full fellow roster).
  defp pact_candidates(state, user) do
    with player when not is_nil(player) <- find_player(state, user.id),
         vassalage when not is_nil(vassalage) <- active_vassalage_for_vassal(state, player.id) do
      fellow_vassal_candidates(state, vassalage.lord_player_id, player.id)
    else
      nil -> []
    end
  end

  defp fellow_vassal_candidates(state, lord_player_id, exclude_player_id) do
    Vassalage
    |> where(
      [v],
      v.world_id == ^state.world.id and v.lord_player_id == ^lord_player_id and
        v.status == :active and v.vassal_player_id != ^exclude_player_id
    )
    |> Repo.all()
    |> Enum.map(&format_pact_candidate(state, &1))
  end

  defp format_pact_candidate(state, fellow) do
    fellow_player = Map.fetch!(state.players, fellow.vassal_player_id)
    fellow_user = Users.get_user!(fellow_player.user_id)
    %{user_id: fellow_user.id, email: fellow_user.email}
  end

  # `strike_turn` arrives a positive integer of turn BOUNDARIES from
  # right now (never an absolute world-turn number — see
  # `BrokenOaths.Game.RebellionPact`'s own moduledoc for why "the
  # world-turn the revolt fires" still holds once this offset is added
  # to `state.turn` below). Opener becomes a member of their own pact
  # too (`:invited`, same as any real invitee); a non-fellow-vassal
  # invitee is silently dropped rather than refusing the whole call.
  defp do_open_pact_chat(state, user, strike_turn_param, invitee_user_ids) do
    with {:ok, opener_player} <- fetch_player(state, user.id),
         {:ok, vassalage} <- fetch_vassalage_as_vassal(state, opener_player.id),
         {:ok, offset} <- parse_strike_turn(strike_turn_param) do
      lord_player_id = vassalage.lord_player_id

      {:ok, pact} =
        %RebellionPact{}
        |> RebellionPact.changeset(%{
          world_id: state.world.id,
          lord_player_id: lord_player_id,
          opener_player_id: opener_player.id,
          strike_turn: state.turn + offset,
          status: :forming
        })
        |> Repo.insert()

      fellow_vassal_ids =
        Vassalage
        |> where(
          [v],
          v.world_id == ^state.world.id and v.lord_player_id == ^lord_player_id and
            v.status == :active
        )
        |> select([v], v.vassal_player_id)
        |> Repo.all()
        |> MapSet.new()

      invitee_player_ids =
        invitee_user_ids
        |> Enum.map(&parse_pact_id/1)
        |> Enum.map(&find_player(state, &1))
        |> Enum.reject(&is_nil/1)
        |> Enum.map(& &1.id)
        |> Enum.filter(&MapSet.member?(fellow_vassal_ids, &1))

      member_player_ids = Enum.uniq([opener_player.id | invitee_player_ids])

      for player_id <- member_player_ids do
        {:ok, _member} =
          %RebellionPactMember{}
          |> RebellionPactMember.changeset(%{
            rebellion_pact_id: pact.id,
            player_id: player_id,
            commit_status: :invited
          })
          |> Repo.insert()
      end

      {:ok, pact}
    end
  end

  defp parse_strike_turn(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_strike_turn(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> {:error, :invalid_strike_turn}
    end
  end

  defp parse_strike_turn(_value), do: {:error, :invalid_strike_turn}

  defp parse_pact_id(id) when is_integer(id), do: id
  defp parse_pact_id(id) when is_binary(id), do: String.to_integer(id)

  defp do_pact_answer(state, user, commit_status) do
    with {:ok, player} <- fetch_player(state, user.id),
         {:ok, member} <- fetch_forming_pact_member(state.world.id, player.id) do
      RebellionPactMember.changeset(member, %{commit_status: commit_status}) |> Repo.update()
    end
  end

  # Criterion 7741 — flips `informer: true` only, never `commit_status`:
  # informing changes no odds.
  defp do_pact_inform(state, user) do
    with {:ok, player} <- fetch_player(state, user.id),
         {:ok, member} <- fetch_forming_pact_member(state.world.id, player.id) do
      RebellionPactMember.changeset(member, %{informer: true}) |> Repo.update()
    end
  end

  defp fetch_forming_pact_member(world_id, player_id) do
    RebellionPactMember
    |> join(:inner, [m], p in RebellionPact, on: p.id == m.rebellion_pact_id)
    |> where(
      [m, p],
      m.player_id == ^player_id and p.world_id == ^world_id and p.status == :forming
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :not_a_pact_member}
      member -> {:ok, member}
    end
  end

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

  # Criterion 7742 — the coarse aggregate `OathStrain.heat/1`, never
  # the exact per-vassal figure `vassal-oath-strain` already shows.
  defp conspiracy_heat(state, user) do
    case find_player(state, user.id) do
      nil ->
        0

      player ->
        Vassalage
        |> where(
          [v],
          v.world_id == ^state.world.id and v.lord_player_id == ^player.id and v.status == :active
        )
        |> select([v], v.oath_strain)
        |> Repo.all()
        |> OathStrain.heat()
    end
  end

  # Immediate, targeted Repo write — same "bypasses `persist_tick/2`'s
  # own generic diff" status `rise_cities/5` already has, since a
  # city's own HP is otherwise only ever mutated inside a tick.
  defp do_brace_defenses(state, user) do
    with {:ok, player} <- fetch_player(state, user.id) do
      city_ids =
        state.cities
        |> Map.values()
        |> Enum.filter(&(&1.player_id == player.id))
        |> Enum.map(& &1.id)

      max_hp = CityDefense.max_hp()
      Repo.update_all(from(c in City, where: c.id in ^city_ids), set: [hp: max_hp])

      new_cities =
        Enum.reduce(city_ids, state.cities, fn id, acc ->
          Map.update!(acc, id, &%{&1 | hp: max_hp})
        end)

      {:ok, %{state | cities: new_cities}}
    end
  end

  defp do_reposition_lord(state, user) do
    with {:ok, player} <- fetch_player(state, user.id),
         lord_unit when not is_nil(lord_unit) <- find_lord_unit(state, player.id) do
      max_hp = lord_unit.max_hp
      Repo.update_all(from(u in Unit, where: u.id == ^lord_unit.id), set: [hp: max_hp])
      new_units = Map.put(state.units, lord_unit.id, %{lord_unit | hp: max_hp})
      {:ok, %{state | units: new_units}}
    else
      nil -> {:error, :no_lord_unit}
      error -> error
    end
  end

  defp find_lord_unit(state, player_id) do
    state.units
    |> Map.values()
    |> Enum.find(&(&1.type == :lord and &1.player_id == player_id))
  end

  # A broad concession a warned lord can make without knowing WHICH of
  # their own vassals is actually plotting — the roster stays secret
  # even once informed (criterion 7741).
  defp do_buy_off_conspirators(state, user) do
    with {:ok, player} <- fetch_player(state, user.id) do
      Vassalage
      |> where(
        [v],
        v.world_id == ^state.world.id and v.lord_player_id == ^player.id and v.status == :active
      )
      |> Repo.all()
      |> Enum.each(fn vassalage ->
        new_strain = OathStrain.ease_gift(vassalage.oath_strain)
        Vassalage.changeset(vassalage, %{oath_strain: new_strain}) |> Repo.update()
      end)

      :ok
    end
  end

  defp do_honor_protection_call(state, user, vassal_user_id) do
    with {:ok, lord_player} <- fetch_player(state, user.id),
         {:ok, vassal_player} <- fetch_player(state, vassal_user_id),
         {:ok, vassalage} <- fetch_vassalage(state, lord_player.id, vassal_player.id) do
      new_strain = OathStrain.ease_autonomy(vassalage.oath_strain)
      Vassalage.changeset(vassalage, %{oath_strain: new_strain}) |> Repo.update()
    end
  end

  # Criterion 7739 — the tick-boundary phase: every `:forming` pact
  # whose `strike_turn` has arrived (`<=`, not `==`, the same
  # catch-up-safe comparison `Resolution.independence_won?/3` already
  # uses elsewhere) reveals and fires all at once. Every `:committed`
  # member declares independence for real, through the SAME
  # `do_declare_independence/3` the immediate player-driven
  # `"declare_independence"` event commits with — no coordination
  # bonus, each conspirator resolves their own reputation-driven rising
  # and their own strain-sized army independently. A member who never
  # committed (still `:invited`, or `:declined`) is left completely
  # untouched — the strike only sweeps in those who actually committed.
  defp apply_rebellion_pact_strikes(state) do
    if Game.feudal_enabled?() do
      RebellionPact
      |> where(
        [p],
        p.world_id == ^state.world.id and p.status == :forming and p.strike_turn <= ^state.turn
      )
      |> Repo.all()
      |> Repo.preload(:members)
      |> Enum.reduce(state, &strike_pact/2)
    else
      state
    end
  end

  defp strike_pact(pact, state) do
    {:ok, _struck} = RebellionPact.changeset(pact, %{status: :struck}) |> Repo.update()

    pact.members
    |> Enum.filter(&RebellionPactMember.committed?/1)
    |> Enum.reduce(state, &strike_member(&1, pact, &2))
  end

  defp strike_member(member, pact, state) do
    with {:ok, vassal_player} <- Map.fetch(state.players, member.player_id),
         {:ok, lord_player} <- Map.fetch(state.players, pact.lord_player_id),
         {:ok, _result, new_state, _lord_events} <-
           do_declare_independence(state, %{id: vassal_player.user_id}, lord_player.user_id) do
      new_state
    else
      _ -> state
    end
  end

  # -------------------------------------------------------------------
  # Gold Bank (story 909)
  # -------------------------------------------------------------------

  defp bank_status(state, user) do
    case find_player(state, user.id) do
      nil -> %{gold: 0, cap: Bank.starting_cap()}
      player -> Bank.status(player)
    end
  end

  defp honor_of(nil), do: 0
  defp honor_of(player), do: player.honor

  defp do_collect_bank(state, user) do
    with :ok <- ensure_feudal_enabled(),
         {:ok, player} <- fetch_player(state, user.id) do
      {new_player, _swept} = Bank.collect(player)
      {:ok, %{state | players: Map.put(state.players, player.id, new_player)}}
    end
  end

  defp do_upgrade_bank(state, user) do
    with :ok <- ensure_feudal_enabled(),
         {:ok, player} <- fetch_player(state, user.id),
         {:ok, upgraded} <- Bank.upgrade(player) do
      {:ok, %{state | players: Map.put(state.players, player.id, upgraded)}}
    end
  end

  # Shared gate every direct Bank/Stewardship command checks first — a
  # no-op (`{:error, :feudal_disabled}`) while `Game.feudal_enabled?/0`
  # reads `false` (prod's own default), same belt-and-suspenders status
  # `apply_captures/1`/`apply_tribute/1`/`apply_bank/1` already carry
  # for the turn-tick side of this same batch.
  defp ensure_feudal_enabled do
    if Game.feudal_enabled?(), do: :ok, else: {:error, :feudal_disabled}
  end

  # -------------------------------------------------------------------
  # Feudal Stewardship (story 910)
  # -------------------------------------------------------------------

  defp steward_log(state, user) do
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
      steward_email: steward_user.email,
      action: log.action,
      turn: log.turn,
      sabotage: log.sabotage
    }
  end

  # QA issue bd93cc0a: the click-through steward view carried on every
  # OFFLINE household member's own `format_vassal/2`/`format_alliance/3`
  # row — everything `GameLive.Play`'s own production-stewardship +
  # emergency-defend controls need to render REAL options, not a blank
  # check. `nil` (never computed at all) whenever the owner is online or
  # not currently stewardable, the same "absent means nothing to offer"
  # posture `vassal_status/2` already gives a free player's own `nil`.
  defp steward_view(state, owner_player) do
    units = owner_units(state, owner_player.id)
    cities = for {_id, c} <- state.cities, c.player_id == owner_player.id, do: c

    %{
      cities: Enum.map(cities, &steward_city_view(state, &1)),
      under_attack?: Stewardship.under_attack?(units),
      # Only units genuinely worth defending (`Stewardship.
      # under_attack?/1`'s own literal "hp < max_hp" signal) — each
      # carrying its own CURRENT `adjacent_tile_ids` so the rendered
      # defend buttons can never go stale against a unit that's already
      # moved (a stale button would make `Stewardship.
      # defend_target_allowed?/3` refuse as provable sabotage, dinging
      # an innocent steward's own Honor for nothing).
      threatened_units:
        units
        |> Enum.filter(&(&1.hp < &1.max_hp))
        |> Enum.map(&steward_unit_view(state, &1))
    }
  end

  # `catalog` reuses `Production.available_items/1` — the SAME
  # research/copper-gated Build list `GameLive.CityPanel` already reads
  # for the owning player themselves — filtered through `Stewardship.
  # constructive_item?/1` (today a no-op: every buildable type IS
  # already constructive, see that module's own moduledoc, but still
  # the one gate this view is contractually bound to).
  defp steward_city_view(state, city) do
    opts = [
      granary_available?: granary_available?(state, city),
      bronze_age?: bronze_age?(state, city),
      copper_access?: copper_access?(state, city)
    ]

    catalog =
      opts
      |> Production.available_items()
      |> Enum.filter(&Stewardship.constructive_item?/1)

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

  # Every real steward mutation shares this same eligibility gate:
  # feudal batch reachable, steward_user/owner_user_id both real
  # players, `Stewardship.eligible?/1` over the resolved `steward_role/3`,
  # and the owner genuinely offline (`Presence.online?/2`) —
  # `{:ok, steward_player, owner_player}` once every check clears.
  defp fetch_steward_context(state, steward_user, owner_user_id) do
    with {:ok, steward_player} <- fetch_player(state, steward_user.id),
         {:ok, owner_player} <- fetch_player(state, owner_user_id) do
      role = steward_role(state, steward_player.id, owner_player.id)
      owner_online? = Presence.online?(state.world, %{id: owner_player.user_id})

      cond do
        not Game.feudal_enabled?() -> {:error, :feudal_disabled}
        not Stewardship.eligible?(role) -> {:error, :not_eligible}
        owner_online? -> {:error, :owner_online}
        true -> {:ok, steward_player, owner_player}
      end

      # NOTE: kept as its own literal `Game.feudal_enabled?()` check
      # (rather than delegating to `ensure_feudal_enabled/0`) since this
      # branch sits inside a `cond`, not a `with`, and needs to run
      # AFTER both players are already resolved (`:not_a_player` must
      # still win over `:feudal_disabled` for an invalid user_id).
    end
  end

  # Resolves the (steward, owner) relationship into `Stewardship.role/0`
  # — the owner's own lord (if any), the steward's own lord (if any),
  # and whether an ACCEPTED alliance exists between the two, each read
  # fresh off `Repo` (world-membership-scoped coordination state, same
  # non-tick-state status `list_alliances/2`/`vassals/2` already have).
  defp steward_role(state, steward_player_id, owner_player_id) do
    owner_lord_id = state |> active_vassalage_for_vassal(owner_player_id) |> lord_id_of()
    steward_lord_id = state |> active_vassalage_for_vassal(steward_player_id) |> lord_id_of()
    allied? = accepted_ally?(state.world.id, steward_player_id, owner_player_id)

    Stewardship.steward_role(owner_lord_id, steward_player_id, steward_lord_id, allied?)
  end

  defp lord_id_of(nil), do: nil
  defp lord_id_of(%Vassalage{lord_player_id: lord_player_id}), do: lord_player_id

  defp accepted_ally?(world_id, player_a_id, player_b_id) do
    case find_alliance(world_id, player_a_id, player_b_id) do
      %Alliance{status: :accepted} -> true
      _other -> false
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

  # `Bank.steward_collect/1` — pure stewardship, every gold lands with
  # the owner, the steward's own treasury never moves. Logged
  # immediately (not tick-state, same "persisted immediately" status
  # `do_propose_alliance/3`'s own write already has) regardless of the
  # swept amount (even a 0-gold sweep is a real, logged action).
  defp do_steward_collect_bank(state, steward_user, owner_user_id) do
    with {:ok, steward_player, owner_player} <-
           fetch_steward_context(state, steward_user, owner_user_id) do
      {new_owner, swept} = Bank.steward_collect(owner_player)

      log_steward_action!(
        state,
        steward_player.id,
        owner_player.id,
        :bank_collect,
        %{amount: swept}
      )

      {:ok, %{state | players: Map.put(state.players, owner_player.id, new_owner)}}
    end
  end

  # Mirrors `do_queue_production/4` exactly — same catalog
  # (`parse_item_type/1`), same `Production.can_queue?/3` gate — but
  # scoped through stewardship eligibility instead of ownership, and
  # additionally gated on `Stewardship.constructive_item?/1` (today
  # always true for anything `parse_item_type/1` accepts at all; the
  # whitelist hook future non-constructive items would need).
  defp do_steward_queue_production(state, steward_user, owner_user_id, city_id, type) do
    with {:ok, steward_player, owner_player} <-
           fetch_steward_context(state, steward_user, owner_user_id),
         {:ok, city} <- fetch_owned_city(state, owner_player, city_id),
         {:ok, type} <- parse_item_type(type),
         :ok <- constructive_item(type),
         :ok <-
           Production.can_queue?(city, type,
             granary_available?: granary_available?(state, city),
             bronze_age?: bronze_age?(state, city),
             copper_access?: copper_access?(state, city)
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

      log_steward_action!(
        state,
        steward_player.id,
        owner_player.id,
        :production_set,
        %{city_id: city_id, item: type}
      )

      {:ok, %{state | cities: Map.put(state.cities, city_id, new_city)}}
    end
  end

  defp fetch_owned_city(state, owner_player, city_id) do
    case Map.get(state.cities, city_id) do
      %{player_id: player_id} = city when player_id == owner_player.id -> {:ok, city}
      _other -> {:error, :not_found}
    end
  end

  defp constructive_item(type) do
    if Stewardship.constructive_item?(type), do: :ok, else: {:error, :not_constructive}
  end

  # EMERGENCY DEFENSE: three gates, in order — eligible + offline
  # (`fetch_steward_context/3`), genuinely `Stewardship.under_attack?/1`,
  # and a `Stewardship.defend_target_allowed?/3` destination (strictly
  # adjacent, never the unit's own tile). The third gate has two
  # failure shapes: NOT under attack at all is a quiet, unlogged refusal
  # (no legitimate emergency window ever existed to abuse); under
  # attack but overreaching the destination IS provable sabotage —
  # logged AND dinged on the steward's own Honor, even though the move
  # itself is still refused. Only every gate clearing actually queues
  # and immediately resolves the move (`bfs_path/3` + `Turn.move_now/2`,
  # the same "orders execute immediately" pattern `do_queue_move/4`
  # already establishes).
  defp do_steward_defend(state, steward_user, owner_user_id, unit_id, to_tile) do
    with {:ok, steward_player, owner_player} <-
           fetch_steward_context(state, steward_user, owner_user_id),
         {:ok, unit} <- fetch_owned_unit(state, owner_player, unit_id) do
      resolve_steward_defend(state, steward_player, owner_player, unit, to_tile)
    end
  end

  defp resolve_steward_defend(state, steward_player, owner_player, unit, to_tile) do
    cond do
      not Stewardship.under_attack?(owner_units(state, owner_player.id)) ->
        {:error, :not_under_attack}

      not Stewardship.defend_target_allowed?(
        unit.tile_id,
        to_tile,
        Regions.adjacent_tiles(state.world, unit.tile_id)
      ) ->
        log_steward_action!(
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
            &Stewardship.apply_sabotage_penalty/1
          )

        {:ok, new_state}

      true ->
        case bfs_path(state, unit.tile_id, to_tile) do
          path when path in [nil, []] ->
            {:error, :unreachable}

          path ->
            persist_order!(unit.id, path)

            queued = %{
              state
              | orders:
                  Map.put(state.orders, unit.id, %{kind: :move, path: path, status: :pending})
            }

            moved = Turn.move_now(queued, unit.id)

            log_steward_action!(
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

  defp log_steward_action!(
         state,
         steward_player_id,
         owner_player_id,
         action,
         details,
         sabotage? \\ false
       ) do
    %StewardLog{}
    |> StewardLog.changeset(
      Stewardship.log_attrs(
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

  # QA issue 5656770d — a tile's yield improvement (`state.improvements`)
  # is checked first, then its Road (`state.roads`), since the two now
  # live independently; a tile with both a completed Farm and a
  # completed Road reports the Farm here (this reader has always
  # returned a single kind — same tie-break `visible_improvements/2`'s
  # list order and cancel's `active_building/2` already use).
  defp tile_improvement_at(state, tile_id) do
    case Map.get(state.improvements, tile_id) do
      %{status: :complete, kind: kind} -> kind
      _other -> road_improvement_at(state, tile_id)
    end
  end

  defp road_improvement_at(state, tile_id) do
    case Map.get(state.roads, tile_id) do
      %{status: :complete, kind: kind} -> kind
      _other -> nil
    end
  end

  # Improvements follow the same fog rule as camps below: a player sees
  # a tile's improvement only in their home region or once the tile is
  # explored — hidden tiles never leak their contents over the wire.
  # QA issue 5656770d — a tile's yield improvement (`state.improvements`)
  # and its Road (`state.roads`) are now independent, so both are
  # emitted here when present; the board's own improvement billboard
  # loop (`assets/js/globe_render.js`) draws every entry it's handed,
  # offsetting a `:road` sprite so it never fully overlaps a
  # Farm/Mine/Pasture sprite on the same tile.
  defp visible_improvements(state, user) do
    case find_player(state, user.id) do
      nil ->
        []

      player ->
        home = player_region_tiles(state.world, player.region_id)
        explored = Map.get(state.explored, player.id, MapSet.new())

        visible? = fn tile_id ->
          MapSet.member?(home, tile_id) or MapSet.member?(explored, tile_id)
        end

        yield_improvements =
          for {tile_id, imp} <- state.improvements,
              visible?.(tile_id),
              do: format_improvement(tile_id, imp)

        roads =
          for {tile_id, imp} <- state.roads,
              visible?.(tile_id),
              do: format_improvement(tile_id, imp)

        yield_improvements ++ roads
    end
  end

  defp format_improvement(tile_id, imp),
    do: %{tile_id: tile_id, kind: imp.kind, status: imp.status, progress: imp.progress}

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
        |> Enum.filter(
          &(MapSet.member?(home, &1.tile_id) or MapSet.member?(explored, &1.tile_id))
        )
        |> Enum.map(&format_camp(&1, state))
    end
  end

  # QA issue 56ee521a — see `handle_call({:enemy_cities_visible_to, ...`
  # above for the full rationale. `city.player_id` is the ORIGINAL
  # (possibly since-defeated) owner — it never changes on capture, only
  # `occupied_by_player_id` does (see `Siege`'s own moduledoc) — so a
  # city already captured by a THIRD player still reads as hostile here
  # (attacking it again isn't specially blocked today), only the
  # VIEWER's own captured holdings are excluded.
  defp visible_enemy_cities(state, user) do
    if Game.feudal_enabled?(), do: do_visible_enemy_cities(state, user), else: []
  end

  defp do_visible_enemy_cities(state, user) do
    case find_player(state, user.id) do
      nil ->
        []

      player ->
        home = player_region_tiles(state.world, player.region_id)
        explored = Map.get(state.explored, player.id, MapSet.new())

        state.cities
        |> Map.values()
        |> Enum.filter(&enemy_city_visible?(&1, player, home, explored))
        |> Enum.map(&enemy_city_summary/1)
    end
  end

  # QA issue 7f91cff2 — `broken` (computed off the FULL city, which
  # still carries `occupied_by_player_id`, before `Map.take/2` drops it)
  # is what `GameLive.Play`'s `.Board` hook needs to route a right-click
  # (or the UnitPanel button) to `queue_move`/occupy instead of another
  # `attack` once the city is at 0 HP — `Siege.broken?/1` is the single
  # source of truth every other broken-city check already reads.
  defp enemy_city_summary(city) do
    city
    |> Map.take([:id, :name, :tile_id, :size, :hp])
    |> Map.put(:broken, Siege.broken?(city))
  end

  defp enemy_city_visible?(city, player, home, explored) do
    city.player_id != player.id and city.occupied_by_player_id != player.id and
      (MapSet.member?(home, city.tile_id) or MapSet.member?(explored, city.tile_id))
  end

  # QA issue ffa66192 — see `handle_call({:captured_cities_visible_to,
  # ...` above for the full rationale.
  defp captured_cities(state, user) do
    if Game.feudal_enabled?() do
      case find_player(state, user.id) do
        nil ->
          []

        player ->
          state.cities
          |> Map.values()
          |> Enum.filter(&(&1.occupied_by_player_id == player.id))
          |> Enum.map(&format_captured_city(state, &1))
      end
    else
      []
    end
  end

  defp format_captured_city(state, city) do
    fallen_garrison? = city |> Siege.fallen_garrison(Map.values(state.units)) |> Enum.any?()
    %{id: city.id, name: city.name, tile_id: city.tile_id, fallen_garrison?: fallen_garrison?}
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
  # `BrokenOaths.Game.Turn`'s "Improvement progress" section — outside
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
          charges: Map.get(unit, :charges, 3)
        ]
      )
    end
  end

  # Newly founded/renamed/reassigned cities are already persisted
  # immediately by their own command (see "Found city"/"Worked tiles"/
  # "Rename city" above) — this only ever catches what the TICK itself
  # (or, since story 895, `do_attack_city/4`'s own immediate
  # resolution) changes: size, food, territory (growth), worked_tiles
  # (a settler's pop cost, or a pillage, un-working a tile), `hp`/
  # `production_halted_until` (city combat — see `CityDefense`),
  # (story 902) `has_granary` — `Production.complete/3`'s own Granary
  # branch flips it the same tick a Granary item finishes banking —
  # and (story 906) `occupied_by_player_id`, set the instant `Siege.
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

  # Gold was the only mutable field on a player once joined — bounty
  # kills (story 893, criterion 7557) and camp-destroy rewards (story
  # 894, criterion 7560) were the first things that ever changed it
  # after `spawn_new_player/2`'s initial 50. Story 904 adds two more,
  # riding the same diff-and-persist path: `barbarians_killed` (bumped
  # alongside every bounty payout) and `camps_destroyed` (bumped
  # alongside every reward-share payout, `pay_shares/2`).
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
