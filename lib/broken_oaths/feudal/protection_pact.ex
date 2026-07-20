defmodule BrokenOaths.Feudal.ProtectionPact do
  @moduledoc """
  The Protection Pact scoring engine (story 914, `:feudal_enabled`) —
  the lord's binding half of the oath
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Rebellion
  batch — LOCKED model": "the lord's binding duty to defend a vassal
  under attack. Failing = a public Honor hit + an Oath Strain spike;
  honoring builds Honor + eases strain.").

  ## Two layers in this one module

  The scoring math itself (`raise_call/3`, `tick/1`, `expired?/1`,
  `score_honored/3`, `score_broken/3`, `spike_contagion/1`) is PURE,
  deliberately — mirrors `BrokenOaths.Feudal.OathStrain`'s/`BrokenOaths.
  Game.Siege`'s own "no `Repo`, no process state" role: every function
  takes plain values (a `call()`, an `OathStrain.strain()`, an integer
  Honor reading) and returns new ones.

  The board-application layer below it (`maybe_raise_protection_call/3`,
  `resolve_protection_call_if_dead/2`, `apply_protection_pact_ticks/1`,
  `honor_protection_call/3`) is the imperative shell this module's own
  original moduledoc anticipated as a "separate, coordinated wiring
  pass" — moved HOME here from `BrokenOaths.Game.WorldServer` per the
  pragdave-pattern "logic lives with the domain model that owns it"
  rule (see `.code_my_spec/knowledge/genserver_decomposition.md`).
  Every function in this layer takes the WorldServer's own tick-`state`
  (or the relevant substructure) plus plain args and returns either a
  reply tuple/value or an updated `state` — no `GenServer`, no
  `handle_*`, no process awareness; `WorldServer`'s own combat/tick
  call sites are thin delegations into it.

  ## No Ecto schema — transient, in-memory tick state

  A protection call is exactly as long-lived as the siege that raised
  it (at most `response_window/0` turns) and, once resolved, has no
  further life of its own — nothing about it needs to survive a
  `WorldServer` restart any more than an in-flight combat resolution
  does. It is represented here as a plain map (`call/0`), the same
  "typed map, not a struct, not a schema" convention
  `BrokenOaths.Combat.CityDefense.city/0` and `BrokenOaths.Combat.Siege`
  already use for combat-adjacent entities the `WorldServer` holds in
  its own tick-state (`state.protection_calls`, `state.
  protection_honored_counts` — both plain, un-initialized-at-boot maps
  the WorldServer's own accessors default to `%{}`).

  ## Lifecycle

    * `raise_call/3` — opens a fresh call the moment a real attack
      lands on a vassal's city or units (criterion 7726): captures the
      relationship, the turn it was raised, and the turn it expires
      (`raised_turn + response_window/0`). Applied by
      `maybe_raise_protection_call/3` below, the moment a real attack
      lands on a vassal's city or unit via one of the two real combat
      surfaces (`WorldServer`'s own `resolve_attack/3`/
      `resolve_city_attack/2`) — a no-op while a call is ALREADY
      pending for this vassal, while the attacker IS their own lord, or
      while `Game.feudal_enabled?/0` reads `false`.
    * `tick/1` — one turn boundary's worth of countdown (criterion
      7727: "counts down by exactly one turn as a boundary passes").
      Only a still-`:pending` call may tick; ticking an already-scored
      call is a caller bug and crashes
      (`.code_my_spec/rules/elixir.md`: "crash the process rather than
      propagating invalid data"). Applied every turn boundary by
      `apply_protection_pact_ticks/1` below.
    * `expired?/1` — whether the window has fully lapsed with no
      relieving action — the signal the BROKEN branch below hangs off.
    * `score_honored/3` / `score_broken/3` — the two resolution
      branches (criteria 7728/7729), each below.

  ## HONORED (criterion 7728) — a shared-enemy defeat

  "Lord Mira's army defeats or drives off the attacker" IS, precisely,
  lord and vassal uniting against a common foe — the exact case
  `OathStrain.ease_shared_enemy/1` already documents itself as owning
  ("lord and vassal united against a common foe"). Rather than invent
  a second, redundant easing constant, `score_honored/3` reuses that
  function directly: one fewer magic number, and a strain reading that
  reflects a real, already-designed relationship. The lord's Honor
  rises by `honored_honor_gain/0`. Applied by
  `resolve_protection_call_if_dead/2` below the moment the tracked
  besieger dies — whether from the lord's own follow-up strike or the
  city's own counter-fire — no window-expiry wait needed.

  ## BROKEN (criterion 7729) — three separate consequences

  Letting the window lapse unanswered fires three independent deltas:

    * the direct victim's own strain spike —
      `OathStrain.spike_broken_protection_pact/1`, the LARGE, one-time
      spike (`OathStrain.protection_pact_spike/0`, 25) that module's
      own moduledoc already reserves for this exact story;
    * the lord's own Honor, docked by `broken_honor_penalty/0`
      ("a public Honor hit" — deliberately unclamped, mirroring
      `BrokenOaths.Feudal.Tribute.apply_refusal_honor_penalty/1` and
      `BrokenOaths.Combat.Siege.apply_execute_honor_penalty/1`'s own
      `honor - N` shape: Honor has no floor in this codebase);
    * a smaller, realm-wide contagion spike (`spike_contagion/1`) on
      every OTHER vassal of the same lord — "every vassal in the
      lord's realm takes an Oath Strain spike," but strictly smaller
      than the direct victim's own (`contagion_spike/0 <
      OathStrain.protection_pact_spike/0`, asserted as a relational
      fact below, never a hardcoded ratio). Applied once a call's own
      `expired?/1` reads true (`apply_protection_pact_ticks/1` below).

  ## Numbers are a balancing pass, not a blocker

  Same posture `OathStrain` already documents for itself — every
  magnitude below is its own named, zero-arity accessor, chosen to sit
  in a documented relationship with the rest of the codebase's existing
  Honor/Strain constants, not to be treated as locked:

    * `response_window/0` (3 turns) — the story's own "Three Amigos"
      open question (".code_my_spec/knowledge/feudal_vassalage_design.md"
      flags "illustratively 3 turns" as unresolved); every 914 spex
      (7727-7730) assumes 3 as a plain GIVEN fact, so this module picks
      3 as its working default.
    * `honored_honor_gain/0` (3) — the positive mirror of
      `Tribute.refusal_honor_penalty/0` (3): honoring a Protection Pact
      is worth exactly as much Honor as a refused levy costs.
    * `broken_honor_penalty/0` (5) — deliberately GREATER than both
      `Tribute.refusal_honor_penalty/0` (3) and
      `Siege.execute_garrison_honor_penalty/0` (2): breaking your own
      binding half of the oath is a worse breach of Honor than either
      a vassal's refusal or a conqueror's ruthlessness, and strictly
      greater than `honored_honor_gain/0` — losing Honor this way hurts
      more than honoring it helps, the same asymmetric-brake posture
      the design doc's own "Honor brake" section calls for ("tyranny
      works but makes every future vassal... warier").
    * `contagion_spike/0` (10) — smaller than
      `OathStrain.protection_pact_spike/0` (25, the direct victim's
      own spike) by construction; chosen equal to
      `OathStrain.gift_ease/0` (10) purely as a memorable anchor, not a
      derived ratio.
  """

  import Ecto.Query

  alias BrokenOaths.Game
  alias BrokenOaths.Feudal.OathStrain
  alias BrokenOaths.Feudal.Vassalage
  alias BrokenOaths.Repo

  @type player_id :: term()
  @type turn :: non_neg_integer()
  @type status :: :pending | :honored | :broken

  @type call :: %{
          optional(atom()) => term(),
          lord_player_id: player_id(),
          vassal_player_id: player_id(),
          raised_turn: turn(),
          deadline_turn: turn(),
          window_remaining: non_neg_integer(),
          status: status()
        }

  @response_window 3
  @honored_honor_gain 3
  @broken_honor_penalty 5
  @contagion_spike 10

  # -------------------------------------------------------------------
  # Balancing constants — see moduledoc's "Numbers are a balancing
  # pass, not a blocker"
  # -------------------------------------------------------------------

  @doc "The default response window (turns) a freshly-raised call carries — an open Three Amigos balancing item, see moduledoc."
  @spec response_window() :: pos_integer()
  def response_window, do: @response_window

  @doc "How much Honor the lord gains for honoring a call in time — see `score_honored/3`."
  @spec honored_honor_gain() :: pos_integer()
  def honored_honor_gain, do: @honored_honor_gain

  @doc "How much Honor the lord loses, unclamped, for letting a call lapse unanswered — see `score_broken/3`."
  @spec broken_honor_penalty() :: pos_integer()
  def broken_honor_penalty, do: @broken_honor_penalty

  @doc "The realm-wide contagion spike every OTHER vassal takes when their lord breaks a call — always smaller than `OathStrain.protection_pact_spike/0`. See `spike_contagion/1`."
  @spec contagion_spike() :: pos_integer()
  def contagion_spike, do: @contagion_spike

  # -------------------------------------------------------------------
  # Lifecycle
  # -------------------------------------------------------------------

  @doc """
  Raise a fresh, `:pending` call for `vassal_player_id` against
  `lord_player_id`, opened on `current_turn`, with `response_window/0`
  turns to respond (criterion 7726 — the trigger).
  """
  @spec raise_call(player_id(), player_id(), turn()) :: call()
  def raise_call(lord_player_id, vassal_player_id, current_turn)
      when is_integer(current_turn) and current_turn >= 0 do
    %{
      lord_player_id: lord_player_id,
      vassal_player_id: vassal_player_id,
      raised_turn: current_turn,
      deadline_turn: current_turn + @response_window,
      window_remaining: @response_window,
      status: :pending
    }
  end

  @doc """
  One turn boundary's worth of countdown — decrements `window_remaining`
  by exactly one, floored at `0` (criterion 7727). Only a still-`:pending`
  call may tick; an already-scored call has nothing left to count down.
  """
  @spec tick(call()) :: call()
  def tick(%{status: :pending, window_remaining: remaining} = call) do
    %{call | window_remaining: max(remaining - 1, 0)}
  end

  @doc "Whether `call`'s own response window has fully lapsed with no relieving action yet."
  @spec expired?(call()) :: boolean()
  def expired?(%{window_remaining: remaining}), do: remaining <= 0

  # -------------------------------------------------------------------
  # HONORED — criterion 7728
  # -------------------------------------------------------------------

  @doc """
  Score a HONORED call: the lord relieved the vassal within the
  window. Eases the vassal's own Oath Strain via
  `OathStrain.ease_shared_enemy/1` (defeating the besieger together IS
  the shared-enemy case) and raises the lord's Honor by
  `honored_honor_gain/0`. Returns the resolved (`:honored`) call
  alongside the new strain and Honor readings — only a still-`:pending`
  call may be scored.
  """
  @spec score_honored(call(), OathStrain.strain(), integer()) ::
          {call(), OathStrain.strain(), integer()}
  def score_honored(%{status: :pending} = call, vassal_strain, lord_honor) do
    {
      %{call | status: :honored},
      OathStrain.ease_shared_enemy(vassal_strain),
      lord_honor + @honored_honor_gain
    }
  end

  # -------------------------------------------------------------------
  # BROKEN — criterion 7729
  # -------------------------------------------------------------------

  @doc """
  Score a BROKEN call: the window expired with no relieving action.
  Spikes the direct victim's own Oath Strain via
  `OathStrain.spike_broken_protection_pact/1` and docks the lord's
  Honor, unclamped, by `broken_honor_penalty/0`. Returns the resolved
  (`:broken`) call alongside the victim's new strain and the lord's new
  Honor — only a still-`:pending` call may be scored.

  Does NOT touch any fellow vassal's own strain — see `spike_contagion/1`
  for the smaller realm-wide consequence a caller applies separately to
  every OTHER vassal of the same lord.
  """
  @spec score_broken(call(), OathStrain.strain(), integer()) ::
          {call(), OathStrain.strain(), integer()}
  def score_broken(%{status: :pending} = call, vassal_strain, lord_honor) do
    {
      %{call | status: :broken},
      OathStrain.spike_broken_protection_pact(vassal_strain),
      lord_honor - @broken_honor_penalty
    }
  end

  @doc """
  Apply the smaller, realm-wide contagion spike (`contagion_spike/0`)
  a broken Protection Pact deals to a BYSTANDER — one of the lord's
  OTHER vassals, not the direct victim of the expired call. Always a
  strictly smaller delta than `OathStrain.spike_broken_protection_pact/1`'s
  own direct-victim spike, by construction (`contagion_spike/0 <
  OathStrain.protection_pact_spike/0`). A caller resolving a broken
  call maps this over every fellow vassal's own strain reading.
  """
  @spec spike_contagion(OathStrain.strain()) :: OathStrain.strain()
  def spike_contagion(strain), do: OathStrain.clamp(strain + @contagion_spike)

  # -------------------------------------------------------------------
  # Board application — moved home from `WorldServer` (see moduledoc)
  # -------------------------------------------------------------------

  @doc """
  Story 914 (criterion 7726): the moment a genuine THIRD PARTY (never
  the vassal's own lord) lands a real attack on a vassal's city or
  unit, raises a Protection Pact obligation against their lord — called
  from the two real attack surfaces `WorldServer`'s own combat already
  resolves through (`resolve_attack/3`, `resolve_city_attack/2`). A
  no-op while a call is ALREADY pending for this vassal (one obligation
  at a time), while the attacker IS their own lord (no self-protection),
  or while `Game.feudal_enabled?/0` reads `false`.
  """
  @spec maybe_raise_protection_call(map(), map(), term() | nil) :: map()
  def maybe_raise_protection_call(state, _attacker, nil), do: state

  def maybe_raise_protection_call(state, attacker, victim_player_id) do
    with true <- Game.feudal_enabled?(),
         %Vassalage{} = vassalage <- active_vassalage_for_vassal(state, victim_player_id),
         true <- attacker.player_id != vassalage.lord_player_id,
         nil <- Map.get(protection_calls(state), victim_player_id) do
      call =
        vassalage.lord_player_id
        |> raise_call(victim_player_id, state.turn)
        |> Map.put(:attacker_unit_id, attacker.id)

      Map.put(state, :protection_calls, Map.put(protection_calls(state), victim_player_id, call))
    else
      _ -> state
    end
  end

  @doc """
  The HONORED branch (criteria 7728/7730): the moment the tracked
  besieger dies — whether from the lord's own follow-up strike or the
  CITY's own counter-fire in the very same clash that raised the call —
  the call resolves honored right here, no window-expiry wait needed.
  Only ever matches a call still tracking THIS exact dead unit's own id.
  """
  @spec resolve_protection_call_if_dead(map(), map()) :: map()
  def resolve_protection_call_if_dead(state, %{hp: 0} = dead_unit) do
    protection_calls(state)
    |> Enum.find(fn {_vassal_player_id, call} -> call.attacker_unit_id == dead_unit.id end)
    |> case do
      nil -> state
      {vassal_player_id, call} -> resolve_honored(state, vassal_player_id, call)
    end
  end

  def resolve_protection_call_if_dead(state, _unit), do: state

  defp resolve_honored(state, vassal_player_id, call) do
    {:ok, vassalage} = fetch_vassalage(state, call.lord_player_id, vassal_player_id)
    lord_honor = state.players[call.lord_player_id].honor

    {_resolved_call, new_strain, new_honor} =
      score_honored(call, vassalage.oath_strain, lord_honor)

    Vassalage.changeset(vassalage, %{oath_strain: new_strain}) |> Repo.update!()

    state = put_in(state.players[call.lord_player_id].honor, new_honor)

    state
    |> Map.put(:protection_calls, Map.delete(protection_calls(state), vassal_player_id))
    |> Map.put(
      :protection_honored_counts,
      Map.update(protection_honored_counts(state), vassal_player_id, 1, &(&1 + 1))
    )
  end

  defp resolve_broken(state, vassal_player_id, call) do
    {:ok, vassalage} = fetch_vassalage(state, call.lord_player_id, vassal_player_id)
    lord_honor = state.players[call.lord_player_id].honor

    {_resolved_call, new_strain, new_honor} =
      score_broken(call, vassalage.oath_strain, lord_honor)

    Vassalage.changeset(vassalage, %{oath_strain: new_strain}) |> Repo.update!()
    apply_protection_pact_contagion(state, call.lord_player_id, vassal_player_id)

    state = put_in(state.players[call.lord_player_id].honor, new_honor)
    Map.put(state, :protection_calls, Map.delete(protection_calls(state), vassal_player_id))
  end

  # Every OTHER active vassal of `lord_player_id` (never the direct
  # victim, `victim_vassal_player_id`) takes `spike_contagion/1` —
  # persisted immediately, side-effect only (the caller's own `state`
  # is untouched by this).
  defp apply_protection_pact_contagion(state, lord_player_id, victim_vassal_player_id) do
    Vassalage
    |> where(
      [v],
      v.world_id == ^state.world.id and v.lord_player_id == ^lord_player_id and
        v.status == :active and v.vassal_player_id != ^victim_vassal_player_id
    )
    |> Repo.all()
    |> Enum.each(fn vassalage ->
      new_strain = spike_contagion(vassalage.oath_strain)
      Vassalage.changeset(vassalage, %{oath_strain: new_strain}) |> Repo.update!()
    end)
  end

  @doc """
  Runs every turn boundary, alongside `BrokenOaths.Feudal.OathStrain.
  Ledger.apply_oath_strain_drift/1` — counts every still-pending call
  down by exactly one (`tick/1`, criterion 7727); an expired, still-
  unanswered one resolves BROKEN right here (criterion 7729). A no-op
  while `Game.feudal_enabled?/0` reads `false`.
  """
  @spec apply_protection_pact_ticks(map()) :: map()
  def apply_protection_pact_ticks(state) do
    if Game.feudal_enabled?() do
      Enum.reduce(protection_calls(state), state, fn {vassal_player_id, call}, acc ->
        ticked_call = tick(call)

        if expired?(ticked_call) do
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

  @doc """
  Story 913 (criterion 7722, ProtectionPact's own narrow half): `user`
  (the lord) honors `vassal_user_id`'s Protection Pact — eases the
  vassal's Oath Strain by `OathStrain.ease_autonomy/1`. Distinct from
  the real 914 call/expiry engine above; this handler only ever touches
  Oath Strain.
  """
  @spec honor_protection_call(map(), map(), integer()) :: {:ok, Vassalage.t()} | {:error, atom()}
  def honor_protection_call(state, user, vassal_user_id) do
    with {:ok, lord_player} <- fetch_player(state, user.id),
         {:ok, vassal_player} <- fetch_player(state, vassal_user_id),
         {:ok, vassalage} <- fetch_vassalage(state, lord_player.id, vassal_player.id) do
      new_strain = OathStrain.ease_autonomy(vassalage.oath_strain)
      Vassalage.changeset(vassalage, %{oath_strain: new_strain}) |> Repo.update()
    end
  end

  # -------------------------------------------------------------------
  # Shared, trivial lookups — duplicated rather than reaching back into
  # `WorldServer` (or reaching sideways into `Vassalage`, out of scope
  # for this slice), matching this module's own "pure, process-unaware,
  # unit-testable with no GenServer running" contract.
  # -------------------------------------------------------------------

  defp protection_calls(state), do: Map.get(state, :protection_calls, %{})
  defp protection_honored_counts(state), do: Map.get(state, :protection_honored_counts, %{})

  defp find_player(state, user_id) do
    state.players |> Map.values() |> Enum.find(&(&1.user_id == user_id))
  end

  defp fetch_player(state, user_id) do
    case find_player(state, user_id) do
      nil -> {:error, :not_a_player}
      player -> {:ok, player}
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
end
