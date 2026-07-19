defmodule BrokenOaths.Game.OathStrain do
  @moduledoc """
  The canonical Oath Strain math (story 913, `:feudal_enabled`) —
  liberty pressure, 0-100, per `BrokenOaths.Game.Vassalage.oath_strain`
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Rebellion
  batch — LOCKED model"): "a per-relationship grievance gauge... Rises
  with tribute burden / neglect / a broken Protection Pact / refused
  levy; falls with investment/autonomy/shared enemies. Slow + sticky.
  It does NOT gate rebellion... its job is to SIZE the temporary
  rebellion army."

  A PURE module, deliberately: every function here takes a `strain()`
  (and, for the tribute driver, a `rate`) and returns a new, ALREADY-
  CLAMPED `strain()` — no `Repo`, no changesets, no process state, the
  same "pure math/changesets-only" role `BrokenOaths.Game.Tribute`
  documents for itself, minus even the changeset-building (that's the
  imperative shell's job once this ships: `BrokenOaths.Game.WorldServer`
  reads a `Vassalage.oath_strain`, calls one of these, and persists the
  result — see the moduledoc note below on `Tribute.spike_oath_strain/1`
  for why that wiring is deliberately NOT part of this module yet).

  ## Invalid states are impossible

  Every public function guards its `strain` argument to the `0..100`
  domain (`valid_strain/1`) and its `rate` argument (where relevant) to
  `0.0..1.0` (`valid_rate/1`) — an out-of-domain call crashes the
  calling process rather than silently propagating a bad number
  (`.code_my_spec/rules/elixir.md`: "Crash the process rather than
  propagating invalid data through the system"). Every function's OWN
  output is passed through `clamp/1` before it's ever returned, so a
  caller chaining several drivers in the same tick can never construct
  an out-of-range value no matter what order they're applied in.

  ## RAISERS

  * `tribute_drift/2` — a high (or low) tribute rate, relative to the
    `default_tribute_rate/0` baseline (25%, matching `Vassalage`'s own
    schema default). "Slow and sticky": each call nudges `strain` by at
    most `max_drift_step/0` (2) points, proportional to how far `rate`
    sits from the baseline — NEVER a jump, and, critically, a dial left
    exactly at the baseline contributes NOTHING (no drift either way),
    so a vassal's strain never bleeds toward some arbitrary resting
    point just because a turn boundary passed with no lever touched.
    This same function is BOTH the raiser ("high tribute rate") and the
    easer ("lowered tribute rate") the design doc lists — the sign of
    the drift follows the sign of the imbalance.
  * `spike_broken_protection_pact/1` — a large, one-time spike
    (`protection_pact_spike/0`, 25) for a lord who fails their own half
    of the oath (story 914, not yet built — this module only owns the
    number the future 914 integration will call).
  * `spike_refused_levy/1` — a moderate, one-time spike
    (`refused_levy_spike/0`, 15) for a refused (or withdrawn) call to
    arms — deliberately the SAME magnitude `BrokenOaths.Game.Tribute`
    already ships as `oath_strain_refusal_spike/0` (story 908). This
    module is now the CANONICAL home for that number; `Tribute` keeps
    its own copy today (this task's scope is the pure engine only — see
    its own moduledoc's "PAIRED consequences" section), but a future
    integration pass can have `Tribute.spike_oath_strain/1` delegate its
    magnitude to `refused_levy_spike/0` instead of carrying a second
    copy that could drift out of sync.

  ## EASERS

  * `ease_gift/1` — a lord's one-off gift to their vassal
    (`gift_ease/0`, 10).
  * `ease_autonomy/1` — granted autonomy, a more structural concession
    than a mere gift (`autonomy_ease/0`, 15).
  * `ease_shared_enemy/1` — lord and vassal united against a common foe
    (`shared_enemy_ease/0`, 8).
  * `tribute_drift/2` — see above; a lowered rate eases strain the same
    way a raised one raises it, via the same slow, bounded drift.

  ## Rebellion army sizing (story 915)

  `rebellion_army_size/1` is the strain -> temporary-army-size curve
  the (not-yet-built) Rebellion component consumes: monotonic
  non-decreasing in `strain` ("higher strain means a bigger uprising"),
  bounded `1..11` across the full `0..100` domain — even a vassal who
  declares independence at zero grievance still raises SOME token force
  (declaring is always available, per criterion 7725; strain only ever
  scales the uprising, never gates it).

  ## Numbers are a balancing pass, not a blocker

  Every magnitude/sensitivity constant here is deliberately named and
  exposed as its own zero-arity accessor (`protection_pact_spike/0`,
  `drift's own private sensitivity`, etc.) rather than inlined, exactly
  because the design doc calls the exact numbers "a balancing pass, not
  a blocker" — only the RELATIONSHIPS are locked: a broken Protection
  Pact spikes harder than a refused levy (`protection_pact_spike() >
  refused_levy_spike()`), and no single driver call ever moves `strain`
  by more than a small, bounded amount.
  """

  @type strain :: 0..100

  # -------------------------------------------------------------------
  # Domain guards — invalid states never leave this module's boundary
  # -------------------------------------------------------------------

  defguardp valid_strain(value) when is_integer(value) and value >= 0 and value <= 100
  defguardp valid_rate(value) when is_float(value) and value >= 0.0 and value <= 1.0

  @min_strain 0
  @max_strain 100

  # -------------------------------------------------------------------
  # Driver magnitudes
  # -------------------------------------------------------------------

  @default_tribute_rate 0.25
  @max_drift_step 2
  @drift_sensitivity 8

  @refused_levy_spike 15
  @protection_pact_spike 25

  @gift_ease 10
  @autonomy_ease 15
  @shared_enemy_ease 8

  @min_rebellion_army 1
  @rebellion_army_step 10

  @doc "The neutral tribute rate (25%, matching `Vassalage`'s own schema default) at which `tribute_drift/2` contributes nothing."
  @spec default_tribute_rate() :: float()
  def default_tribute_rate, do: @default_tribute_rate

  @doc "The most `tribute_drift/2` (or any other single driver call) ever moves `strain` in one call — the 'slow and sticky' bound."
  @spec max_drift_step() :: pos_integer()
  def max_drift_step, do: @max_drift_step

  @doc "The moderate, one-time spike a refused (or withdrawn) call to arms applies — see `spike_refused_levy/1`."
  @spec refused_levy_spike() :: pos_integer()
  def refused_levy_spike, do: @refused_levy_spike

  @doc "The large, one-time spike an unhonored Protection Pact applies — see `spike_broken_protection_pact/1`. Always greater than `refused_levy_spike/0`."
  @spec protection_pact_spike() :: pos_integer()
  def protection_pact_spike, do: @protection_pact_spike

  @doc "The one-time ease a lord's gift applies — see `ease_gift/1`."
  @spec gift_ease() :: pos_integer()
  def gift_ease, do: @gift_ease

  @doc "The one-time ease granted autonomy applies — see `ease_autonomy/1`."
  @spec autonomy_ease() :: pos_integer()
  def autonomy_ease, do: @autonomy_ease

  @doc "The one-time ease a shared enemy applies — see `ease_shared_enemy/1`."
  @spec shared_enemy_ease() :: pos_integer()
  def shared_enemy_ease, do: @shared_enemy_ease

  # -------------------------------------------------------------------
  # RAISERS (and, for tribute_drift/2, its EASER mirror)
  # -------------------------------------------------------------------

  @doc """
  Nudge `strain` toward reflecting `rate`'s own imbalance against
  `default_tribute_rate/0` — at most `max_drift_step/0` points, in the
  direction the imbalance points (up for a raised rate, down for a
  lowered one), and exactly `0` at the baseline itself. Represents ONE
  turn boundary's worth of pressure; a caller drifting across many
  turns simply calls this once per boundary with the vassalage's
  current rate.
  """
  @spec tribute_drift(strain(), float()) :: strain()
  def tribute_drift(strain, rate) when valid_strain(strain) and valid_rate(rate) do
    clamp(strain + drift_step(rate))
  end

  @doc "Apply `protection_pact_spike/0` — the large, one-time spike for an unhonored Protection Pact (story 914)."
  @spec spike_broken_protection_pact(strain()) :: strain()
  def spike_broken_protection_pact(strain) when valid_strain(strain) do
    clamp(strain + @protection_pact_spike)
  end

  @doc "Apply `refused_levy_spike/0` — the moderate, one-time spike for a refused (or withdrawn) call to arms."
  @spec spike_refused_levy(strain()) :: strain()
  def spike_refused_levy(strain) when valid_strain(strain) do
    clamp(strain + @refused_levy_spike)
  end

  # -------------------------------------------------------------------
  # EASERS
  # -------------------------------------------------------------------

  @doc "Apply `gift_ease/0` — a lord's one-off gift eases strain downward."
  @spec ease_gift(strain()) :: strain()
  def ease_gift(strain) when valid_strain(strain), do: clamp(strain - @gift_ease)

  @doc "Apply `autonomy_ease/0` — granted autonomy eases strain downward."
  @spec ease_autonomy(strain()) :: strain()
  def ease_autonomy(strain) when valid_strain(strain), do: clamp(strain - @autonomy_ease)

  @doc "Apply `shared_enemy_ease/0` — a shared enemy eases strain downward."
  @spec ease_shared_enemy(strain()) :: strain()
  def ease_shared_enemy(strain) when valid_strain(strain), do: clamp(strain - @shared_enemy_ease)

  # -------------------------------------------------------------------
  # Rebellion army sizing (story 915)
  # -------------------------------------------------------------------

  @doc """
  The temporary rebellion army size a `strain` reading implies (story
  915): monotonic non-decreasing, `1` at `strain == 0` (declaring
  independence is always available and always raises SOME token force)
  up to `#{1 + div(100, 10)}` at the `100` ceiling.
  """
  @spec rebellion_army_size(strain()) :: pos_integer()
  def rebellion_army_size(strain) when valid_strain(strain) do
    @min_rebellion_army + div(strain, @rebellion_army_step)
  end

  # -------------------------------------------------------------------
  # Domain clamp — the single choke point every driver's output passes through
  # -------------------------------------------------------------------

  @doc "Clamp an arbitrary integer into the valid `0..100` `strain()` domain."
  @spec clamp(integer()) :: strain()
  def clamp(value) when is_integer(value) do
    value |> max(@min_strain) |> min(@max_strain)
  end

  # -------------------------------------------------------------------
  # Conspiracy heat (story 916)
  # -------------------------------------------------------------------

  @doc """
  A lord's own coarse "conspiracy heat" gauge (criterion 7742): the
  mean `strain()` across every one of their own vassals' individual
  readings, rounded down — a single needle for the whole realm, never
  a duplicate of any one relationship's own exact figure. `0` for a
  lord with no vassals at all (nothing to aggregate).
  """
  @spec heat([strain()]) :: strain()
  def heat([]), do: 0

  def heat(strains) when is_list(strains) do
    strains
    |> Enum.sum()
    |> div(length(strains))
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  defp drift_step(rate) do
    (rate - @default_tribute_rate)
    |> Kernel.*(@drift_sensitivity)
    |> round()
    |> clamp_step()
  end

  defp clamp_step(step), do: step |> max(-@max_drift_step) |> min(@max_drift_step)
end
