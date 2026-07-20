defmodule BrokenOaths.Feudal.Vassalization do
  @moduledoc """
  The subjugation pivot (story 907): the business rules built on top of
  `BrokenOaths.Feudal.Vassalage`, mirroring `BrokenOaths.Game.
  Cooperation`'s own "pure changeset, no `Repo`" role for `Alliance`.
  `BrokenOaths.Game.WorldServer` is the imperative shell that calls into
  this module once `BrokenOaths.Combat.Siege.materialize_captures/2`
  reports a fresh capture, actually persists the row, and pushes the
  notifications both players see.

  ## When vassalization fires

  Zeroing a city's HP and walking in (`Siege`'s own job) is necessary
  but not sufficient — vassalization only fires once the DEFEATED
  player has zero free cities left ("'Free city' = a city you own that
  no other player occupies... Vassalization fires at ZERO free cities",
  design doc, "Round-5 decisions"). `vassalization_events/2` is that
  filter, applied to whatever `Siege.materialize_captures/2` reports:
  a capture that still leaves the defeated player one free city is
  silently dropped (`BrokenOathsSpex.Story907.Criterion7667Spex`); a
  capture that leaves them none is kept.

  Several different players' own last cities can fall in the very same
  tick (each independently besieged down and walked into) — each is
  resolved on its own, deterministically, in `Siege`'s own capture
  order (ascending city id): `vassalization_events/2` also collapses
  the rare case of the SAME player's own last TWO cities somehow
  falling in one pass to a single event, so a defeated player is never
  vassalized twice for the same subjugation.

  ## Creating the relationship

  `vassalize_changeset/3` builds a fresh `Vassalage` row with every
  default forward-looking field the design doc calls for (25% tribute,
  0 Oath Strain, an empty contract-terms bag, `:active` status) — the
  caller is responsible for the actual `Repo.insert/1`.

  ## The Oath screen

  The fresh vassal's own Hidden Agenda pick — Restore, Usurp, Kingmaker,
  or Merchant Prince — is a SEPARATE, later commit
  (`choose_agenda_changeset/2`), not part of the vassalizing insert
  itself: the relationship exists (and both players are notified) the
  MOMENT the last free city falls, but the agenda stays secret and
  unset until the vassal actually picks one on their own view.

  ## Capture -> vassalization orchestration (stories 906/907/917/919)

  `apply_captures/1` and `maybe_revassalize/3` are the pragdave-pattern
  "domain model" home (`.code_my_spec/knowledge/genserver_decomposition.md`)
  for the capture/occupy → swear-fealty flow `BrokenOaths.Game.
  WorldServer` used to bury inline: they take the WorldServer's own
  tick-`state` (see `BrokenOaths.Game.Turn`'s moduledoc for that shape)
  plus plain args and return either a reply tuple or an updated
  `state` — no `GenServer`, no `handle_*`, no process awareness.
  `WorldServer`'s own `:queue_move` handler and tick loop are thin
  delegations into `apply_captures/1`; `BrokenOaths.Feudal.Rebellion.War`
  (peace/crushed rebellion endings) and `WorldServer`'s own story-917
  heir reconciliation sweep both call `maybe_revassalize/3` directly.
  """

  alias BrokenOaths.Game
  alias BrokenOaths.Combat.Siege
  alias BrokenOaths.Feudal.Vassalage
  alias BrokenOaths.Game.WorldServer
  alias BrokenOaths.Repo
  alias BrokenOaths.Users

  @type player_id :: term()

  # -------------------------------------------------------------------
  # When vassalization fires
  # -------------------------------------------------------------------

  @doc """
  Filters `capture_events` (`Siege.materialize_captures/2`'s own
  return) down to the ones that actually leave their defeated player
  with zero free cities among `cities` — `Siege.no_free_cities?/2`
  applied per event, deduplicated so the same defeated player is never
  reported twice even if several of their cities fell in the same pass.
  """
  @spec vassalization_events([Siege.capture_event()], [Siege.city()]) :: [Siege.capture_event()]
  def vassalization_events(capture_events, cities) do
    capture_events
    |> Enum.filter(&Siege.no_free_cities?(cities, &1.defeated_player_id))
    |> Enum.uniq_by(& &1.defeated_player_id)
  end

  # -------------------------------------------------------------------
  # Creating the relationship
  # -------------------------------------------------------------------

  @doc """
  Build the changeset for a fresh `Vassalage` row: `lord_player_id`
  captured `vassal_player_id`'s last free city in `world_id`. Every
  forward-looking field defaults per `Vassalage.changeset/2` (25%
  tribute, 0 Oath Strain, no agenda yet, an empty contract-terms bag,
  `:active` status) — the caller persists it.
  """
  @spec vassalize_changeset(term(), player_id(), player_id()) :: Ecto.Changeset.t()
  def vassalize_changeset(world_id, lord_player_id, vassal_player_id) do
    Vassalage.changeset(%Vassalage{}, %{
      world_id: world_id,
      lord_player_id: lord_player_id,
      vassal_player_id: vassal_player_id
    })
  end

  # -------------------------------------------------------------------
  # The Oath screen
  # -------------------------------------------------------------------

  @doc "Whether `vassalage` still awaits its vassal's own secret Hidden Agenda pick — the Oath screen's own trigger."
  @spec agenda_pending?(Vassalage.t()) :: boolean()
  def agenda_pending?(%Vassalage{hidden_agenda: nil}), do: true
  def agenda_pending?(%Vassalage{}), do: false

  @doc "Build the changeset recording the vassal's own secret Hidden Agenda pick."
  @spec choose_agenda_changeset(Vassalage.t(), Vassalage.hidden_agenda()) :: Ecto.Changeset.t()
  def choose_agenda_changeset(vassalage, agenda), do: Vassalage.changeset(vassalage, %{hidden_agenda: agenda})

  # -------------------------------------------------------------------
  # Notifications
  # -------------------------------------------------------------------

  @doc "The fresh vassal's own notification copy — the `\"game:vassalized\"` push both 906 and 907 share."
  @spec vassalized_message(String.t()) :: String.t()
  def vassalized_message(lord_email),
    do: "Your last free city has fallen — you are now sworn to #{lord_email}."

  @doc "The lord's own notification copy for their new vassal — the `\"game:new_vassal\"` push."
  @spec new_vassal_message(String.t()) :: String.t()
  def new_vassal_message(vassal_email), do: "#{vassal_email} has sworn fealty to you."

  # -------------------------------------------------------------------
  # Capture -> vassalization orchestration (stories 906/907) — moved
  # home from `BrokenOaths.Game.WorldServer`; see this module's own
  # "Capture -> vassalization orchestration" moduledoc section above.
  # -------------------------------------------------------------------

  @doc """
  Safe to call after ANY movement-producing change (an immediate
  `queue_move`, or a full tick) — `Siege.materialize_captures/2` is
  itself idempotent, so this never double-reports a city already
  captured on a prior call. A fresh capture that leaves its defeated
  player with zero free cities left also fires vassalization right
  here (`vassalization_events/2`), in the SAME pass — the DB write
  happens immediately (mirrors `WorldServer`'s own "not tick-state,
  persisted immediately" status for alliance proposals), never waiting
  on the tick's own city/unit diff. A no-op while `Game.
  feudal_enabled?/0` reads `false` — belt-and-suspenders alongside
  `attack_city/4`'s own gate, which already keeps every city
  `Siege.broken?/1` (the only way `materialize_captures/2` ever finds
  anything to capture) from ever happening in the first place.
  """
  @spec apply_captures(map()) :: {map(), [term()]}
  def apply_captures(state) do
    if Game.feudal_enabled?() do
      {new_cities, capture_events} = Siege.materialize_captures(state.cities, state.units)
      new_state = %{state | cities: new_cities}

      case capture_events do
        [] ->
          {new_state, []}

        _ ->
          vassalize_events =
            vassalization_events(capture_events, Map.values(new_cities))

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
          world_id
          |> vassalize_changeset(lord_player_id, vassal_player_id)
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
      {:vassalized, vassal_user_id, vassalized_message(lord_email)},
      {:new_vassal, lord_user_id, vassal_user_id, new_vassal_message(vassal_email)}
    ]
  end

  defp owner_user_id(state, player_id), do: Map.fetch!(state.players, player_id).user_id

  @doc """
  Re-vassalizes `vassal_player_id` under `lord_player_id` via the SAME
  real `vassalize_changeset/3` write + `"game:vassalized"`/
  `"game:new_vassal"` notifications `apply_captures/1` already ships —
  a no-op (no double row, no duplicate notification) if an active
  Vassalage between the two already exists. Shared by
  `BrokenOaths.Feudal.Rebellion.War` (peace/crushed endings) and
  `WorldServer`'s own story-917 heir reconciliation sweep
  (`reconcile_heir_vassals_for_user/2`) — see `Rebellion.War`'s own
  moduledoc for the shared-utility rationale.
  """
  @spec maybe_revassalize(map(), integer(), integer()) :: :ok
  def maybe_revassalize(state, lord_player_id, vassal_player_id) do
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

  defp broadcast(world_id, events) do
    Enum.each(events, &Phoenix.PubSub.broadcast(BrokenOaths.PubSub, WorldServer.topic(world_id), &1))
  end
end
