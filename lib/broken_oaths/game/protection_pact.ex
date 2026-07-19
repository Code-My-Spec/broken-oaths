defmodule BrokenOaths.Game.ProtectionPact do
  @moduledoc """
  The Protection Pact scoring engine (story 914, `:feudal_enabled`) —
  the lord's binding half of the oath
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Rebellion
  batch — LOCKED model": "the lord's binding duty to defend a vassal
  under attack. Failing = a public Honor hit + an Oath Strain spike;
  honoring builds Honor + eases strain."). A PURE module, deliberately
  — mirrors `BrokenOaths.Game.OathStrain`'s/`BrokenOaths.Game.Siege`'s
  own "no `Repo`, no process state" role: every function here takes
  plain values (a `call()`, a `BrokenOaths.Game.OathStrain.strain()`,
  an integer Honor reading) and returns new ones. The imperative shell
  — `BrokenOaths.Game.WorldServer` raising a real call the moment a
  real attack lands on a vassal, ticking it every turn boundary
  alongside `BrokenOaths.Game.Turn`'s own pipeline, and persisting the
  `BrokenOaths.Game.Vassalage.oath_strain` / `BrokenOaths.Game.Player.honor`
  results this module computes — is explicitly OUT OF SCOPE for this
  task (a separate, coordinated wiring pass); this module only owns the
  decision math the future integration will call.

  ## No Ecto schema — transient, in-memory tick state

  A protection call is exactly as long-lived as the siege that raised
  it (at most `response_window/0` turns) and, once resolved, has no
  further life of its own — nothing about it needs to survive a
  `WorldServer` restart any more than an in-flight combat resolution
  does. It is represented here as a plain map (`call/0`), the same
  "typed map, not a struct, not a schema" convention
  `BrokenOaths.Game.CityDefense.city/0` and `BrokenOaths.Game.Siege`
  already use for combat-adjacent entities the `WorldServer` holds in
  its own tick-state — a future `WorldServer` integration keeps a list
  of these per world (or per lord), exactly like it already keeps
  units and cities, with no migration required.

  ## Lifecycle

    * `raise_call/3` — opens a fresh call the moment a real attack
      lands on a vassal's city or units (criterion 7726): captures the
      relationship, the turn it was raised, and the turn it expires
      (`raised_turn + response_window/0`).
    * `tick/1` — one turn boundary's worth of countdown (criterion
      7727: "counts down by exactly one turn as a boundary passes").
      Only a still-`:pending` call may tick; ticking an already-scored
      call is a caller bug and crashes
      (`.code_my_spec/rules/elixir.md`: "crash the process rather than
      propagating invalid data").
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
  rises by `honored_honor_gain/0`.

  ## BROKEN (criterion 7729) — three separate consequences

  Letting the window lapse unanswered fires three independent deltas:

    * the direct victim's own strain spike —
      `OathStrain.spike_broken_protection_pact/1`, the LARGE, one-time
      spike (`OathStrain.protection_pact_spike/0`, 25) that module's
      own moduledoc already reserves for this exact story;
    * the lord's own Honor, docked by `broken_honor_penalty/0`
      ("a public Honor hit" — deliberately unclamped, mirroring
      `BrokenOaths.Game.Tribute.apply_refusal_honor_penalty/1` and
      `BrokenOaths.Game.Siege.apply_execute_honor_penalty/1`'s own
      `honor - N` shape: Honor has no floor in this codebase);
    * a smaller, realm-wide contagion spike (`spike_contagion/1`) on
      every OTHER vassal of the same lord — "every vassal in the
      lord's realm takes an Oath Strain spike," but strictly smaller
      than the direct victim's own (`contagion_spike/0 <
      OathStrain.protection_pact_spike/0`, asserted as a relational
      fact below, never a hardcoded ratio). `score_broken/3` itself
      only resolves the direct victim + the lord; the caller (a future
      `WorldServer` integration, iterating every fellow vassalage) maps
      `spike_contagion/1` over each bystander's own reading — this
      module never needs to see the whole household roster to decide
      one relationship's own consequence.

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

  alias BrokenOaths.Game.OathStrain

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
end
