defmodule BrokenOaths.Game.Combat do
  @moduledoc """
  Pure combat core: effective strength, the Civ VI damage curve,
  simultaneous attacker/defender resolution, the lord's adjacency aura,
  flat-strength camp damage, and adjacency/target-legality validation.
  No `Repo`, no process state — `BrokenOaths.Game.WorldServer` is the
  imperative shell that reads units out of its canonical tick-state
  (see `BrokenOaths.Game.Turn`'s moduledoc for that shape), calls into
  this module, and writes the result back.

  ## Effective strength

  `effective_strength/2` scales a unit's base strength by a linear
  wounded penalty — 100% at full HP, falling to 50% as HP approaches
  zero — then adds the lord's adjacency aura on top:

      effective = (base_strength + aura_bonus) * (0.5 + 0.5 * hp / max_hp)

  The aura is folded into strength BEFORE the wounded penalty scales
  it, not added on top of an already-wounded number — a wounded unit's
  aura bonus is worth less than a fresh one's, exactly like the rest of
  its strength. Every criterion this module was built against (story
  891 criteria 7541/7575, story 896 criteria 7570/7571) only exercises
  full-HP auras or aura-free wounds, so this ordering is a judgment
  call, not something asserted by a spec — the alternative (aura added
  after wounding) would only diverge on a wounded, aura'd unit.

  ## Damage

  `resolve/3` computes the Civ VI curve — 30 base damage at equal
  strength, scaling ~4% per point of strength difference, with a ±25%
  random roll — for both directions of a single exchange at once, from
  the SAME pre-combat strengths: a dying defender still lands its
  counter-blow (story 891, criterion 7538). `camp_damage/2` is the flat
  variant with no roll, for a future camp assault (story 894); it takes
  the attacker's own effective strength directly, matching the design
  doc's worked example (a strength-10 Warrior deals 10 camp damage).

  ## Determinism

  Every roll is seeded from caller-supplied terms (typically world
  seed + turn + the two unit ids) via `:rand.seed_s/2` — the same
  functional, non-global pattern `BrokenOaths.Worlds.Noise` and
  `BrokenOaths.Worlds.Regions` already use — never bare `:rand.uniform/0`
  against the process dictionary. Two callers computing the same combat
  from the same tick-state always agree, which lockstep resolution
  requires.

  ## Target legality

  `hostile?/2` is the seam for barbarian identity: a unit with a `nil`
  `player_id` (`Game.Camps`, story 892 — a camp-spawned warrior, or a
  test-spawned one via `WorldServer`'s `:spawn_barbarian_for_test`) is
  hostile to everyone, and everyone is hostile to it — checked on
  EITHER side of the pairing, so a barbarian can both be attacked by a
  player and (once story 893 gives it a way to act) attack one back.
  Two real players are never hostile to each other ("no Stone Age PvP"
  — story 891, criterion 7542): `validate_attack/3` refuses every
  cross-player attack where neither side is a barbarian.
  """

  @type tile_id :: non_neg_integer()
  @type unit_type :: :lord | :settler | :warrior | :worker | :barbarian_warrior

  @type unit :: %{
          id: term(),
          player_id: term() | nil,
          type: unit_type(),
          tile_id: tile_id(),
          hp: non_neg_integer(),
          max_hp: pos_integer(),
          movement: non_neg_integer(),
          max_movement: non_neg_integer()
        }

  @type attack_result :: %{
          damage_to_defender: pos_integer(),
          damage_to_attacker: pos_integer()
        }

  @type refusal :: :out_of_movement | :not_adjacent | :not_hostile

  @base_strength %{lord: 12, warrior: 10, settler: 0, worker: 0, barbarian_warrior: 15}
  @lord_aura_bonus 2
  @base_damage 30
  @damage_scale 0.04
  @roll_floor 0.75
  @roll_span 0.5

  @doc "A unit type's base combat strength, before wounding or the lord's aura."
  @spec base_strength(unit_type()) :: non_neg_integer()
  def base_strength(type), do: Map.fetch!(@base_strength, type)

  @doc """
  `unit`'s effective strength right now: base strength plus the lord's
  aura (when `aura?` is true), scaled by the linear wounded penalty
  (100% at full HP, 50% at 0 HP). Callers determine `aura?` by checking
  whether a living, same-player lord stands adjacent to `unit` — this
  module has no notion of "adjacent" or "same player," only the two
  numbers that decision produces.
  """
  @spec effective_strength(unit(), boolean()) :: float()
  def effective_strength(unit, aura? \\ false) do
    (base_strength(unit.type) + aura_bonus(aura?)) * wounded_multiplier(unit)
  end

  defp aura_bonus(true), do: @lord_aura_bonus
  defp aura_bonus(false), do: 0

  defp wounded_multiplier(%{hp: hp, max_hp: max_hp}), do: 0.5 + 0.5 * (hp / max_hp)

  @doc """
  Resolve a single simultaneous exchange: damage `attacker` deals to
  `defender` and damage `defender` deals back to `attacker`, both
  computed from the same pre-combat strengths (a dying defender still
  lands its blow). Required `opts`:

    * `:seed` — any term; rolls are deterministic for a given seed
    * `:attacker_aura?` / `:defender_aura?` — whether each side stands
      adjacent to its own living lord (default `false`)
  """
  @spec resolve(unit(), unit(), keyword()) :: attack_result()
  def resolve(attacker, defender, opts) do
    seed = Keyword.fetch!(opts, :seed)
    attacker_strength = effective_strength(attacker, Keyword.get(opts, :attacker_aura?, false))
    defender_strength = effective_strength(defender, Keyword.get(opts, :defender_aura?, false))

    %{
      damage_to_defender: damage(attacker_strength, defender_strength, {seed, :to_defender}),
      damage_to_attacker: damage(defender_strength, attacker_strength, {seed, :to_attacker})
    }
  end

  defp damage(striking_strength, resisting_strength, roll_seed) do
    @base_damage
    |> Kernel.*(:math.exp(@damage_scale * (striking_strength - resisting_strength)))
    |> Kernel.*(roll(roll_seed))
    |> round()
  end

  @doc """
  Flat camp damage: `attacker`'s own effective strength, rounded, with
  no random roll (camps don't counter-attack). Pure and unwired —
  `BrokenOaths.Game.Camps` (story 892) doesn't exist yet; this is the
  function a future camp-assault handler calls once it does.
  """
  @spec camp_damage(unit(), boolean()) :: pos_integer()
  def camp_damage(attacker, aura? \\ false) do
    attacker |> effective_strength(aura?) |> round()
  end

  @doc """
  Whether `attacker` may legally attack `defender` right now:
  the attacker has movement left, the defender stands on an adjacent
  tile, and the defender is a hostile (barbarian) target.
  """
  @spec validate_attack(unit(), unit(), [tile_id()]) :: :ok | {:error, refusal()}
  def validate_attack(attacker, defender, adjacent_tile_ids) do
    cond do
      attacker.movement <= 0 -> {:error, :out_of_movement}
      defender.tile_id not in adjacent_tile_ids -> {:error, :not_adjacent}
      not hostile?(attacker, defender) -> {:error, :not_hostile}
      true -> :ok
    end
  end

  @doc "Whether `attacker` and `defender` are legal (barbarian) combatants — see this module's doc."
  @spec hostile?(unit(), unit()) :: boolean()
  def hostile?(%{player_id: nil}, _defender), do: true
  def hostile?(_attacker, %{player_id: nil}), do: true
  def hostile?(_attacker, _defender), do: false

  # A deterministic roll in [0.75, 1.25] for `seed` (any term). Hashed
  # into a 3-integer state via `:erlang.phash2/2` — the same shape
  # `BrokenOaths.Worlds.Noise.init/1` seeds with — then drawn through
  # the functional (non-global) `_s` random API so two calls with the
  # same seed always agree, regardless of what else is happening in
  # this process.
  defp roll(seed) do
    state = :rand.seed_s(:exsss, seed_tuple(seed))
    {value, _state} = :rand.uniform_s(state)
    @roll_floor + value * @roll_span
  end

  defp seed_tuple(term) do
    h = :erlang.phash2(term, 1_000_000_000)
    {h, h * 7 + 13, h * 31 + 97}
  end
end
