defmodule BrokenOaths.Game.Rebellion.War do
  @moduledoc """
  Pure, process-unaware orchestration for the Rebellion war itself
  (stories 915/919) — the pragdave-pattern "domain model" home for the
  logic `BrokenOaths.Game.WorldServer` used to bury inline (see
  `.code_my_spec/knowledge/genserver_decomposition.md`).

  Every function here takes the WorldServer's own tick-`state` (or the
  relevant substructure) plus plain args and returns either a reply
  tuple/value or an updated `state` — no `GenServer`, no `handle_*`, no
  process awareness. `WorldServer`'s own `handle_call`/tick clauses are
  thin one-line delegations into this module.

  Owns: declaring independence (and its read-only preview), the
  negotiated peace seam (offer/accept/reject), the turn-boundary
  rebellion-lifecycle sweep (independence won / crushed), the narrow
  rebel<->former-lord PvP exception `WorldServer`'s own combat gate
  widens for, and the heir-succession gating that withholds a fallen
  lord's own heir until their last active rebellion resolves.

  Coordinates its siblings directly, per the north star's "cross-cutting
  operations are orchestrated by their OWNING domain model calling its
  siblings" rule: `Rebellion`/`Rebellion.Resolution` for the schema and
  pure war math, `Vassalage` for severing (and, via
  `BrokenOaths.Game.Vassalization.maybe_revassalize/3`, restoring) the
  oath, and `Unit`/`City` schemas for the immediate, targeted Repo
  writes a rebellion's own city-rising/army-spawn/city-freeing needs
  (bypassing `WorldServer`'s own generic tick-diff persistence, exactly
  as the original inline code did).

  `maybe_revassalize/3` lives on `BrokenOaths.Game.Vassalization`
  (moved home from `WorldServer` alongside the rest of the capture/
  vassalization pipeline — the combat/vassalization decomposition
  slice): it's shared between this module's own peace/crushed endings
  and `WorldServer`'s own story-917 heir reconciliation sweep, so a
  single real DB-write + notification-broadcast implementation is the
  single source of truth for both callers.
  """

  import Ecto.Query

  alias BrokenOaths.Game
  alias BrokenOaths.Game.City
  alias BrokenOaths.Game.CityDefense
  alias BrokenOaths.Game.Player
  alias BrokenOaths.Game.Production
  alias BrokenOaths.Game.Rebellion
  alias BrokenOaths.Game.Rebellion.Resolution
  alias BrokenOaths.Game.Unit
  alias BrokenOaths.Game.Vassalage
  alias BrokenOaths.Game.Vassalization
  alias BrokenOaths.Game.WorldServer
  alias BrokenOaths.Repo
  alias BrokenOaths.Users

  # -------------------------------------------------------------------
  # Declare independence (story 915)
  # -------------------------------------------------------------------

  @doc """
  Story 915, criterion 7732 — read-only inspection: the SAME
  `Resolution.city_rises?/4`/`army_size/1` inputs (the lord's own Honor,
  this vassalage's own tribute rate, the world's own seed)
  `declare_independence/3` commits with below, never live RNG.
  """
  @spec independence_preview(map(), map(), integer()) :: {:ok, map()} | {:error, atom()}
  def independence_preview(state, user, lord_user_id) do
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

  @doc """
  Story 915 — the full commit: severs the Vassalage (`:broken`, so
  tribute never transfers again), resolves risings with the SAME
  formula the preview already showed, de-occupies + heals every risen
  city (its former garrison defecting to the rebel), spawns the
  temporary rebellion army flagged `temporary: true`, and creates the
  first-class `Rebellion` row. Returns `{:ok, %{rebellion:, message:},
  new_state, lord_events}` — `lord_events` is the former lord's own
  `{:rebellion_declared, ...}` notification, broadcast by the caller
  alongside the ordinary `:vassals_changed`/`:units_changed`/
  `:cities_changed` refresh triggers.
  """
  @spec declare_independence(map(), map(), integer()) ::
          {:ok, map(), map(), [tuple()]} | {:error, atom()}
  def declare_independence(state, user, lord_user_id) do
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

  # De-occupies + fully heals every one of `risen_cities` and defects
  # whichever of `lord_player_id`'s own units still stand on each one's
  # own tile to `vassal_player_id` — criterion 7733's own "the lord's
  # garrison stationed there defects". Persisted immediately —
  # `occupied_by_player_id`/`hp` on the city row, `player_id` on each
  # defecting unit.
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
  # (or, failing that, any of their own units) currently stands.
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

  # Story 915: the temporary rebellion army raised at declare-independence
  # time — same shape as an ordinary spawned unit plus the two fields
  # that mark it disbandable (`temporary`/`rebellion_id`).
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

  # -------------------------------------------------------------------
  # Negotiated peace (story 919)
  # -------------------------------------------------------------------

  @doc "Story 919: either side offers a negotiated peace — persisted only as in-memory tick-state (`state.peace_offers`)."
  @spec offer_peace(map(), map(), integer(), atom() | String.t(), non_neg_integer() | nil) ::
          {:ok, map()} | {:error, atom()}
  def offer_peace(state, user, counterparty_user_id, outcome, reparations_gold) do
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

  @doc "Story 919: the counterparty accepts a still-pending peace offer, resolving the rebellion."
  @spec accept_peace(map(), map(), integer()) :: {:ok, map()} | {:error, atom()}
  def accept_peace(state, user, counterparty_user_id) do
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

  @doc "Story 919: either side rejects (or withdraws) a still-pending peace offer — the war simply continues."
  @spec reject_peace(map(), map(), integer()) :: {:ok, map()} | {:error, atom()}
  def reject_peace(state, user, counterparty_user_id) do
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

  defp peace_offers(state), do: Map.get(state, :peace_offers, %{})

  defp parse_peace_outcome("independence"), do: {:ok, :independence}
  defp parse_peace_outcome("restored_vassal"), do: {:ok, :restored_vassal}

  defp parse_peace_outcome(outcome) when outcome in [:independence, :restored_vassal],
    do: {:ok, outcome}

  defp parse_peace_outcome(_other), do: {:error, :invalid_outcome}

  # Story 919, criterion 7754 — "nobody loses cities in a peace": frees
  # AND fully heals every one of the rebel's own cities, risen or
  # loyal, regardless of `outcome`. Reparations (optional) move from
  # whoever ACCEPTED to whoever OFFERED.
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
      Vassalization.maybe_revassalize(state, ended.former_lord_player_id, ended.rebel_player_id)
    end

    state
  end

  # -------------------------------------------------------------------
  # Turn-boundary lifecycle sweep (story 919)
  # -------------------------------------------------------------------

  @doc """
  Story 919 — the turn-boundary lifecycle sweep: every ACTIVE rebellion
  in this world settles into EXACTLY ONE ended status the moment its
  own end condition reads true. A no-op while `Game.feudal_enabled?/0`
  reads `false`. Also run immediately after an ordinary `queue_move`
  resolves (`trigger: :move`) — a rebel's last free city can fall to an
  adjacent march that itself never needed a fresh tick boundary to land.
  """
  @spec process_rebellion_endings(map(), :tick | :move) :: map()
  def process_rebellion_endings(state, trigger \\ :tick) do
    if Game.feudal_enabled?() do
      Rebellion
      |> where([r], r.world_id == ^state.world.id and r.status == :active)
      |> Repo.all()
      |> Enum.reduce(state, &process_rebellion_ending(&2, &1, trigger))
    else
      state
    end
  end

  # `trigger` distinguishes an ordinary quiet turn boundary (`:tick`)
  # from an actual player move (`:move`): `crushed?/2` and
  # `independence_won?/3` are both SAFE to check on either, but
  # `rebel_defeated?/2` is scoped to `:move` only — it would otherwise
  # read true on the VERY FIRST quiet tick for a rebel whose cities
  # never rose at all.
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
  # cities here. Only the temporary army disbands and the war state
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
  # write story 906/907 already ship (`Vassalization.maybe_revassalize/3`).
  defp end_rebellion_crushed(state, rebellion) do
    {:ok, ended} = Resolution.crush(rebellion) |> Repo.update()

    state = disband_temporary_army(state, ended.id)

    Vassalization.maybe_revassalize(state, ended.former_lord_player_id, ended.rebel_player_id)

    broadcast(state.world.id, [:vassals_changed, :units_changed])

    state
  end

  # Frees AND fully heals every one of `rebellion`'s own rebel-owned
  # cities — both `risen_city_ids` (already free, this is a no-op for
  # them) and `loyal_city_ids` (still occupied by the former lord).
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
  # (any status). Idempotent.
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

  # -------------------------------------------------------------------
  # PvP exception (story 915)
  # -------------------------------------------------------------------

  # The ONE active Rebellion (if any) between two players, whichever
  # direction — `WorldServer`'s own `validate_attack/4` rebellion-war
  # exception and the peace offer/accept/reject seam above both key off
  # this same lookup.
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

  @doc """
  Story 915: the narrow, rebellion-scoped PvP exception `WorldServer`'s
  own `validate_attack/4` needs — mirrors `protecting_lord_may_strike?/3`'s
  own technique (widen the CALLER-side gate, never touch
  `Combat.hostile?/2` itself).
  """
  @spec rebellion_war?(map(), integer() | nil, integer() | nil) :: boolean()
  def rebellion_war?(state, player_a_id, player_b_id)
      when not is_nil(player_a_id) and not is_nil(player_b_id) do
    not is_nil(find_active_rebellion_between(state, player_a_id, player_b_id))
  end

  def rebellion_war?(_state, _player_a_id, _player_b_id), do: false

  # -------------------------------------------------------------------
  # Heir succession gating (story 917)
  # -------------------------------------------------------------------

  @doc """
  Story 917 (criterion 7748) — reconciles the flat-10-turn heir schedule
  with "the heir does not arrive until the LAST active rebellion against
  the realm has ended": withholds any `state.pending_heirs` entry for a
  player currently facing an ACTIVE `Rebellion` from `Turn.tick/1`'s own
  pure "heir succession" phase entirely, returning `{gated_state,
  deferred_heirs}` — `restore_gated_heirs/2` splices `deferred_heirs`
  back in, untouched, once `Turn.tick/1` returns.
  """
  @spec defer_gated_heirs(map()) :: {map(), map()}
  def defer_gated_heirs(state) do
    pending = Map.get(state, :pending_heirs, %{})

    {gated, ready} =
      Enum.split_with(pending, fn {player_id, _arrival_turn} ->
        active_rebellion_against?(state, player_id)
      end)

    {%{state | pending_heirs: Map.new(ready)}, Map.new(gated)}
  end

  @doc "Splices `gated` (built by `defer_gated_heirs/1`) back into `ticked.pending_heirs`, untouched."
  @spec restore_gated_heirs(map(), map()) :: map()
  def restore_gated_heirs(ticked, gated) when map_size(gated) == 0, do: ticked

  def restore_gated_heirs(ticked, gated) do
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

  # -------------------------------------------------------------------
  # Shared, trivial lookups — duplicated rather than reaching back into
  # `WorldServer` (or reaching sideways into `Vassalage`, out of scope
  # for this slice), matching this module's own "pure, process-unaware,
  # unit-testable with no GenServer running" contract.
  # -------------------------------------------------------------------

  defp find_player(state, user_id) do
    state.players |> Map.values() |> Enum.find(&(&1.user_id == user_id))
  end

  defp fetch_player(state, user_id) do
    case find_player(state, user_id) do
      nil -> {:error, :not_a_player}
      player -> {:ok, player}
    end
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

  defp broadcast(world_id, events) do
    Enum.each(
      events,
      &Phoenix.PubSub.broadcast(BrokenOaths.PubSub, WorldServer.topic(world_id), &1)
    )
  end
end
