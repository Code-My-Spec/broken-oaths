defmodule BrokenOaths.Combat.Resolver do
  @moduledoc """
  Pure combat core: effective strength, the Civ VI damage curve,
  simultaneous attacker/defender resolution, the lord's adjacency aura,
  flat-strength camp damage, and adjacency/target-legality validation.
  No `Repo`, no process state — `BrokenOaths.Simulation.WorldServer` is the
  imperative shell that reads units out of its canonical tick-state
  (see `BrokenOaths.Simulation.Turn`'s moduledoc for that shape), calls into
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

  ## Fortify (story 920)

  `fortify/3`-driven (see `BrokenOaths.Units.Unit.fortify/3`) — a
  `:defend`-capable unit's own defensive stance, applied the instant
  it's chosen, no dig-in turn: +50% of the unit's BASE strength,
  DEFENSE ONLY (the attacker never gets it, even if the attacker itself
  happens to be fortified — see `combat_strength/3`'s own `side` check
  below), folded into strength BEFORE the wounded penalty scales it,
  same ordering as the lord's aura above — `(base + aura + round(base *
  0.5)) * wounded`. Composes with the garrison bonus (story 895) the
  same way the aura does: `garrisoned_strength/3` multiplies the WHOLE
  fortified-and-wounded figure by 1.5, never the other way around.
  Clears the instant the unit itself moves (`Simulation.Turn.Movement.
  apply_positions/3`) or attacks (`resolve_attack/4` below, `Combat.
  Camps.resolve_camp_attack/3`, `Combat.Siege`'s own
  `resolve_city_attack/4`) — being attacked while fortified never
  clears it, so a defender that survives an exchange keeps the bonus
  for the next one.

  ## Garrison bonus (story 895)

  A unit standing on its own city's tile fights at +50% strength,
  whichever side of the exchange it's on — `garrisoned_strength/2` is
  `effective_strength/2` (aura folded in, then wounding scaled) times
  1.5. `resolve/3` accepts `:attacker_garrisoned?`/`:defender_garrisoned?`
  opts (default `false`) that switch a side onto this boosted strength
  instead of the plain one; `BrokenOaths.Combat.CityDefense` is the seam
  that decides whether a unit qualifies (standing on its own city's own
  tile) — this module only knows the two numbers that decision
  produces, exactly like the lord's aura above.

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
  `pvp_target_allowed?/3` is `hostile?/2` widened by the SAME two
  narrow feudal exceptions `validate_pvp_attack/4` (below) already
  carved out for melee — extracted to a public predicate so
  `shoot/4`'s own ranged targeting can share it verbatim rather than
  duplicating (and risking drifting from) the real gate.

  ## Ranged (QA issue 12bed1e4 "Archers don't have a shoot action")

  `shoot/4` is the Archer's own ranged sibling to `attack/4`: same
  target-legality rules (`pvp_target_allowed?/3` — barbarians always
  hostile, two real players only under the SAME war/rebellion/
  protection-pact exceptions melee gets), but RANGE
  (`in_shoot_range?/3`, `shoot_range/0` hexes — 2, raw mesh-adjacency
  distance, no line-of-sight model, no land-path walk) instead of
  bare adjacency, and no moving onto the target's tile. The whole
  "ranged advantage" is `resolve_attack/4`'s own `ranged?: true` opt:
  it runs the SAME damage curve (aura, garrison bonus, wounding, the
  ±25% roll) `resolve_attack/3`'s melee callers already get, then
  zeroes the counter-blow the defender would otherwise land — an
  Archer that shoots never takes a return hit, whatever it's shooting
  at. Refuses `:not_archer` for any other unit type; `Combat.Camps.
  shoot_camp/4` and `Combat.Siege.shoot_city/4` are this same shape's
  camp/city siblings, both reusing `in_shoot_range?/3` here instead of
  a second, drifting range check.

  ## Attack orchestration (stories 891/893/896/899/914)

  `attack/4` and `resolve_attack/4` are the pragdave-pattern "domain
  model" home (`.code_my_spec/knowledge/genserver_decomposition.md`)
  for the unit-vs-unit "attack" flow `BrokenOaths.Simulation.WorldServer`
  used to bury inline: they take the WorldServer's own tick-`state`
  (see `BrokenOaths.Simulation.Turn`'s moduledoc for that shape) plus plain
  args and return either a reply tuple or an updated `state` — no
  `GenServer`, no `handle_*`, no process awareness. `WorldServer`'s own
  `:attack` `handle_call` (and the test-only
  `:resolve_barbarian_attack_for_test` bridge) are thin delegations
  into this section, as is `shoot/4` above. Coordinates its siblings
  directly, per the north star's "cross-cutting operations are
  orchestrated by their OWNING domain model calling its siblings"
  rule: `BrokenOaths.Game.Rebellion.War` and `BrokenOaths.Feudal.
  ProtectionPact` for the two feudal PvP exceptions (never duplicated
  here), `BrokenOaths.Game.CityDefense` for the garrison-bonus lookup.
  """

  alias BrokenOaths.Combat.BarbarianAI
  alias BrokenOaths.Combat.CityDefense
  alias BrokenOaths.Feudal.ProtectionPact
  alias BrokenOaths.Feudal.Rebellion.War
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.World

  @type tile_id :: non_neg_integer()
  @type unit_type ::
          :lord | :settler | :warrior | :worker | :barbarian_warrior | :bronze_spearman | :archer

  @type unit :: %{
          id: term(),
          player_id: term() | nil,
          type: unit_type(),
          tile_id: tile_id(),
          hp: non_neg_integer(),
          max_hp: pos_integer(),
          movement: non_neg_integer(),
          max_movement: non_neg_integer(),
          fortified: boolean()
        }

  @type attack_result :: %{
          damage_to_defender: pos_integer(),
          damage_to_attacker: pos_integer()
        }

  @type attack_outcome :: %{damage_dealt: non_neg_integer(), damage_taken: non_neg_integer()}

  @type camp :: %{
          id: term(),
          tile_id: tile_id(),
          hp: non_neg_integer(),
          destroyed_at: term() | nil
        }

  @type refusal :: :out_of_movement | :not_adjacent | :not_hostile
  @type ranged_refusal :: :out_of_movement | :out_of_range | :not_hostile | :not_archer

  @base_strength %{
    lord: 12,
    warrior: 10,
    settler: 0,
    worker: 0,
    barbarian_warrior: 15,
    # Story 903: the Bronze Age's own melee unit — single strength, no
    # attack/defense split (`.code_my_spec/knowledge/civ6_tech_tree.md`
    # §5's recommendation), comfortably above a Barbarian Warrior's 15
    # so it reliably wins a 1v1 (criterion 7633).
    bronze_spearman: 16,
    # QA issue da39e50b "No archer" — a first-pass MELEE Archer (this
    # engine originally shipped with no ranged-attack model at all; QA
    # issue 12bed1e4 is what actually adds one — see `shoot/4` and this
    # module's own "Ranged" doc above), single strength like every
    # other unit here, between the Warrior (10) and the Bronze Spearman
    # (16). Unchanged by the ranged-attack fix: `shoot/4` reads this
    # SAME base strength, `resolve_attack/4`'s `ranged?: true` opt only
    # zeroes the counter-blow, never the archer's own damage curve.
    archer: 14
  }
  @lord_aura_bonus 2
  # Story 920 — the Fortify stance's own defensive bonus: half the
  # unit's BASE strength (see `fortify_bonus/2` and this module's own
  # "Fortify" doc above).
  @fortify_bonus_ratio 0.5
  @garrison_bonus 1.5
  @base_damage 30
  @damage_scale 0.04
  @roll_floor 0.75
  @roll_span 0.5
  # QA issue 12bed1e4 — how far an Archer's `shoot/4` reaches: raw
  # mesh-adjacency hexes (see `in_shoot_range?/3`'s own doc for why not
  # a land-path distance), not a strategic-scale number like
  # `BrokenOaths.Combat.CityDefense.approach_range/0` (3) or
  # `BrokenOaths.Combat.Camps`'s own far-camp band (8-15) — just far
  # enough that "don't move onto the target's tile" reads as a real
  # tactical choice rather than a same-as-melee no-op.
  @shoot_range 2

  @doc "A unit type's base combat strength, before wounding or the lord's aura."
  @spec base_strength(unit_type()) :: non_neg_integer()
  def base_strength(type), do: Map.fetch!(@base_strength, type)

  @doc """
  `unit`'s effective strength right now: base strength plus the lord's
  aura (when `aura?` is true) plus the Fortify stance's own bonus (when
  `fortified?` is true — story 920, see this module's own "Fortify"
  doc), scaled by the linear wounded penalty (100% at full HP, 50% at 0
  HP). Callers determine `aura?` by checking whether a living,
  same-player lord stands adjacent to `unit`; `fortified?` is DEFENSE
  ONLY (`combat_strength/3` below is the one caller that ever passes
  `true`, and only for the defending side of an exchange) — this module
  has no notion of "adjacent," "same player," or "which side of the
  fight," only the numbers those decisions produce.
  """
  @spec effective_strength(unit(), boolean(), boolean()) :: float()
  def effective_strength(unit, aura? \\ false, fortified? \\ false) do
    (base_strength(unit.type) + aura_bonus(aura?) + fortify_bonus(unit, fortified?)) *
      wounded_multiplier(unit)
  end

  defp aura_bonus(true), do: @lord_aura_bonus
  defp aura_bonus(false), do: 0

  defp fortify_bonus(unit, true), do: round(base_strength(unit.type) * @fortify_bonus_ratio)
  defp fortify_bonus(_unit, false), do: 0

  defp wounded_multiplier(%{hp: hp, max_hp: max_hp}), do: 0.5 + 0.5 * (hp / max_hp)

  @doc """
  `unit`'s combat strength while garrisoned on its own city's tile
  (story 895): `effective_strength/3`, boosted 50% for fighting from
  the walls — the fortify bonus (story 920), if any, is folded in
  BEFORE this multiplier, same "whole figure times 1.5" ordering the
  aura already gets. Callers (`BrokenOaths.Combat.CityDefense`) determine
  whether a unit qualifies; this module only applies the multiplier.
  """
  @spec garrisoned_strength(unit(), boolean(), boolean()) :: float()
  def garrisoned_strength(unit, aura? \\ false, fortified? \\ false),
    do: effective_strength(unit, aura?, fortified?) * @garrison_bonus

  @doc """
  Resolve a single simultaneous exchange: damage `attacker` deals to
  `defender` and damage `defender` deals back to `attacker`, both
  computed from the same pre-combat strengths (a dying defender still
  lands its blow). Required `opts`:

    * `:seed` — any term; rolls are deterministic for a given seed
    * `:attacker_aura?` / `:defender_aura?` — whether each side stands
      adjacent to its own living lord (default `false`)
    * `:attacker_garrisoned?` / `:defender_garrisoned?` — whether each
      side fights from its own city's walls, `garrisoned_strength/2`
      instead of `effective_strength/2` (default `false`, story 895)
  """
  @spec resolve(unit(), unit(), keyword()) :: attack_result()
  def resolve(attacker, defender, opts) do
    seed = Keyword.fetch!(opts, :seed)
    attacker_strength = combat_strength(attacker, opts, :attacker)
    defender_strength = combat_strength(defender, opts, :defender)

    %{
      damage_to_defender: damage(attacker_strength, defender_strength, {seed, :to_defender}),
      damage_to_attacker: damage(defender_strength, attacker_strength, {seed, :to_attacker})
    }
  end

  defp combat_strength(unit, opts, side) do
    aura? = Keyword.get(opts, :"#{side}_aura?", false)
    # Story 920 — defense only: `unit.fortified` never inflates the
    # ATTACKING side's own strength, even for a unit that happens to
    # still carry the flag mid-exchange (see this module's own
    # "Fortify" doc for why that can briefly be true).
    fortified? = side == :defender and Map.get(unit, :fortified, false)

    if Keyword.get(opts, :"#{side}_garrisoned?", false) do
      garrisoned_strength(unit, aura?, fortified?)
    else
      effective_strength(unit, aura?, fortified?)
    end
  end

  @doc """
  The Civ VI damage curve for a single direction of an exchange: 30
  base damage at equal strength, scaling ~4% per point of strength
  difference, with a ±25% random roll seeded from `roll_seed` (see this
  module's Determinism doc). Public so `BrokenOaths.Combat.CityDefense`
  can resolve a barbarian-vs-city exchange (one side a city's
  defensive strength, not a unit) against the SAME curve `resolve/3`
  uses for unit-vs-unit combat, rather than a second, drifting copy of
  this formula.
  """
  @spec damage(number(), number(), term()) :: pos_integer()
  def damage(striking_strength, resisting_strength, roll_seed) do
    @base_damage
    |> Kernel.*(:math.exp(@damage_scale * (striking_strength - resisting_strength)))
    |> Kernel.*(roll(roll_seed))
    |> round()
  end

  @doc """
  Flat camp damage: `attacker`'s own effective strength, rounded, with
  no random roll (camps don't counter-attack). Pure and unwired —
  `BrokenOaths.Combat.Camps` (story 892) doesn't exist yet; this is the
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

  @doc """
  Whether `attacker` may legally target `defender` under the SAME PvP
  rules `attack/4` enforces: `hostile?/2`'s barbarian check, OR one of
  the two narrow feudal exceptions (a lord striking back at their own
  vassal's tracked besieger; an active rebellion war between the two
  players) `validate_pvp_attack/4` (below) already carves out for
  melee. Movement/range/adjacency are NOT this predicate's concern —
  callers check those separately. Extracted to a public function
  (never inlined twice) so `shoot/4`'s own ranged targeting shares
  EXACTLY this gate rather than a second copy that could quietly
  drift — `hostile?/2` itself is never weakened by either caller.
  """
  @spec pvp_target_allowed?(map(), unit(), unit()) :: boolean()
  def pvp_target_allowed?(state, attacker, defender) do
    hostile?(attacker, defender) or
      protecting_lord_may_strike?(state, attacker, defender) or
      War.rebellion_war?(state, attacker.player_id, defender.player_id)
  end

  @doc """
  Whether `attacker` may legally attack `camp` right now: movement
  left, camp on an adjacent tile. Every camp is a legal target while it
  stands (no `hostile?/2`-style ownership check — a camp has no
  player_id to compare) — the caller looks the camp up by id and
  refuses `:invalid_target` before ever reaching here if it's already
  destroyed.
  """
  @spec validate_camp_attack(unit(), camp(), [tile_id()]) :: :ok | {:error, refusal()}
  def validate_camp_attack(attacker, camp, adjacent_tile_ids) do
    cond do
      attacker.movement <= 0 -> {:error, :out_of_movement}
      camp.tile_id not in adjacent_tile_ids -> {:error, :not_adjacent}
      true -> :ok
    end
  end

  @doc """
  How many hexes an Archer's `shoot/4` reaches (QA issue 12bed1e4).
  """
  @spec shoot_range() :: pos_integer()
  def shoot_range, do: @shoot_range

  @doc """
  Whether `to_tile` sits within `shoot_range/0` raw mesh-adjacency
  hexes of `from_tile` — the same "physical closeness on the globe,"
  never a land-path walking distance, `BrokenOaths.Combat.CityDefense.
  approaching?/4` already measures its own alert range with (an arrow
  flies over water/mountains same as open ground;
  `BrokenOaths.Combat.BarbarianAI`'s land-path distance is for a
  WALKING unit's own approach, not a standing shot). `from_tile` itself
  is never in range of itself — an archer doesn't "shoot" the tile
  it's already standing on.
  """
  @spec in_shoot_range?(World.t(), tile_id(), tile_id()) :: boolean()
  def in_shoot_range?(world, from_tile, to_tile) do
    MapSet.member?(shoot_disk(world, from_tile), to_tile)
  end

  # Same growing-ring BFS shape `CityDefense`'s own private `mesh_disk/3`
  # uses for its approach alert — duplicated (not shared) per this
  # codebase's established "small pure state-accessor helpers live
  # wherever they're needed" convention.
  defp shoot_disk(world, start) do
    {_frontier, seen} =
      Enum.reduce(1..@shoot_range, {[start], MapSet.new([start])}, fn _, {frontier, seen} ->
        next =
          frontier
          |> Enum.flat_map(&Regions.adjacent_tiles(world, &1))
          |> Enum.uniq()
          |> Enum.reject(&MapSet.member?(seen, &1))

        {next, MapSet.union(seen, MapSet.new(next))}
      end)

    MapSet.delete(seen, start)
  end

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

  # -------------------------------------------------------------------
  # Attack orchestration (stories 891/893/896/899/914) — moved home
  # from `BrokenOaths.Simulation.WorldServer`; see this module's own
  # "Attack orchestration" moduledoc section above.
  # -------------------------------------------------------------------

  @doc """
  Resolve an immediate "attack" request: `user`'s own `unit_id` strikes
  `target_unit_id` right now, against whatever movement the attacker
  has left — an order resolves immediately, not queued (see this
  module's moduledoc for the damage math and target-legality rules).
  `WorldServer`'s own `:attack` `handle_call` wraps this with
  persistence and the broadcast.
  """
  @spec attack(map(), term(), term(), term()) ::
          {:ok, attack_outcome(), map()} | {:error, term()}
  def attack(state, user, unit_id, target_unit_id) do
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

        case validate_pvp_attack(state, attacker, defender, adjacent_tile_ids) do
          :ok ->
            {result, new_state} = resolve_attack(state, attacker, defender)
            {:ok, result, new_state}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # Story 914: `validate_attack/3`'s own general "no PvP in the Stone
  # Age" rule (`hostile?/2` — false for any two real players, LOCKED,
  # see `BrokenOathsSpex.Story899.Criterion7603Spex`) stays untouched
  # for everyone ELSE — this only widens the CALLER-side gate
  # `attack/4` itself applies, with one narrow, story-914-scoped
  # exception: a lord may always strike the SPECIFIC unit currently
  # tracked as the besieger of one of their OWN vassal's active
  # Protection Pact calls ("the lord is notified and is expected to
  # defend" — the design doc's own words require the lord be ABLE to
  # fight back). Every other pairing of two real players falls through
  # to `hostile?/2`'s own unchanged verdict. `pvp_target_allowed?/3`
  # (above) is this SAME widened check, extracted to a public function
  # `shoot/4` also calls — this stays the melee-only movement/adjacency
  # wrapper around it.
  defp validate_pvp_attack(state, attacker, defender, adjacent_tile_ids) do
    cond do
      attacker.movement <= 0 -> {:error, :out_of_movement}
      defender.tile_id not in adjacent_tile_ids -> {:error, :not_adjacent}
      pvp_target_allowed?(state, attacker, defender) -> :ok
      true -> {:error, :not_hostile}
    end
  end

  defp protecting_lord_may_strike?(state, attacker, defender) do
    Enum.any?(protection_calls(state), fn {_vassal_player_id, call} ->
      call.attacker_unit_id == defender.id and call.lord_player_id == attacker.player_id
    end)
  end

  @doc """
  Resolve a single already-validated exchange: `attack/4`'s own
  post-`validate_pvp_attack/4` step, also reused by `WorldServer`'s
  test-only `:resolve_barbarian_attack_for_test` bridge, which needs
  the SAME pipeline without `attack/4`'s player-ownership check (a
  barbarian attacker has no owning session to satisfy it), and by
  `shoot/4` (QA issue 12bed1e4). Applies `resolve/3`'s damage, drops
  whichever side reached 0 HP, schedules an heir if a lord fell, pays
  the barbarian-kill bounty, and raises/resolves any Protection Pact
  call the exchange touches. `opts`:

    * `:ranged?` — when `true` (the Archer's own `shoot/4`), the
      defender's own counter-blow is computed exactly like every other
      melee exchange (so the SAME aura/garrison/wounding curve applies
      either way) and then discarded before it's ever applied to
      `attacker` — the whole "no counterattack" ranged advantage.
      Defaults `false` (ordinary melee, unchanged).
  """
  @spec resolve_attack(map(), unit(), unit(), keyword()) :: {attack_outcome(), map()}
  def resolve_attack(state, attacker, defender, opts \\ []) do
    seed = {state.world.seed, state.turn, attacker.id, defender.id}
    ranged? = Keyword.get(opts, :ranged?, false)

    %{damage_to_defender: dealt, damage_to_attacker: countered} =
      resolve(attacker, defender,
        seed: seed,
        attacker_aura?: lord_adjacent?(state, attacker),
        defender_aura?: lord_adjacent?(state, defender),
        attacker_garrisoned?: CityDefense.garrisoned?(attacker, Map.values(state.cities)),
        defender_garrisoned?: CityDefense.garrisoned?(defender, Map.values(state.cities))
      )

    taken = if ranged?, do: 0, else: countered

    # Story 920 — attacking (melee or a ranged shot) drops the
    # attacker's own Fortify stance, if any; the defender's own stance
    # (if it has one) is untouched by simply being attacked — see this
    # module's "Fortify" doc. `Map.put/3` (not the strict `%{... | ...}`
    # update syntax) so this never raises on a hand-built test unit map
    # that predates the `fortified` field.
    new_attacker =
      %{attacker | hp: max(attacker.hp - taken, 0), movement: 0} |> Map.put(:fortified, false)

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
      |> ProtectionPact.maybe_raise_protection_call(attacker, defender.player_id)
      |> ProtectionPact.resolve_protection_call_if_dead(new_attacker)
      |> ProtectionPact.resolve_protection_call_if_dead(new_defender)

    {%{damage_dealt: dealt, damage_taken: taken}, state}
  end

  defp apply_combat_unit(units, id, %{hp: 0}), do: Map.delete(units, id)
  defp apply_combat_unit(units, id, unit), do: Map.put(units, id, unit)

  # Story 893, criterion 7557: whichever side of a resolved exchange
  # was a barbarian (`player_id: nil`) and reached 0 HP pays the OTHER
  # side's owner the bounty. Story 904: the same kill also bumps the
  # payee's own `barbarians_killed` career total.
  defp pay_bounty_if_barbarian_fell(state, %{player_id: nil, hp: 0}, %{player_id: payee_id})
       when not is_nil(payee_id) do
    state = update_in(state.players[payee_id].gold, &(&1 + BarbarianAI.bounty_gold()))
    update_in(state.players[payee_id].barbarians_killed, &(&1 + 1))
  end

  defp pay_bounty_if_barbarian_fell(state, _fallen, _other), do: state

  # A living unit of the SAME player standing next door — dead units
  # are already gone from `state.units`, so presence alone means
  # living, and a lord's own tile is never its own neighbor, so this
  # never accidentally self-buffs the lord. Duplicated (not shared)
  # into `BrokenOaths.Combat.Siege`/`BrokenOaths.Simulation.Turn`/`WorldServer`
  # per this codebase's own established "small pure state-accessor
  # helpers live wherever they're needed" convention (see e.g. `Turn`'s
  # own `lord_adjacent?/2`).
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
  # persisted. `Turn.tick/1` resolves this map every boundary.
  defp schedule_heir_if_lord_fell(state, %{type: :lord, player_id: player_id}, %{hp: 0}) do
    pending_heirs =
      state
      |> Map.get(:pending_heirs, %{})
      |> Map.put(player_id, state.turn + 10)

    Map.put(state, :pending_heirs, pending_heirs)
  end

  defp schedule_heir_if_lord_fell(state, _original, _new), do: state

  defp protection_calls(state), do: Map.get(state, :protection_calls, %{})

  defp find_player(state, user_id) do
    state.players |> Map.values() |> Enum.find(&(&1.user_id == user_id))
  end

  # -------------------------------------------------------------------
  # Ranged (QA issue 12bed1e4) — the Archer's own `shoot/4`, mirroring
  # `attack/4`'s own shape; see this module's "Ranged" moduledoc
  # section above.
  # -------------------------------------------------------------------

  @doc """
  Resolve an immediate ranged "shoot" request: `user`'s own Archer
  `unit_id` strikes `target_unit_id` from up to `shoot_range/0` hexes
  away, without moving there and without taking `target_unit_id`'s own
  counter-blow — see this module's "Ranged" doc. Same target-legality
  rules `attack/4` enforces (`pvp_target_allowed?/3`), just RANGE
  instead of adjacency; refuses `:not_archer` for any other attacking
  unit type. `WorldServer`'s own `:shoot` `handle_call` wraps this with
  persistence and the broadcast, mirroring `attack/4`'s own wrapper.
  """
  @spec shoot(map(), term(), term(), term()) ::
          {:ok, attack_outcome(), map()} | {:error, term()}
  def shoot(state, user, unit_id, target_unit_id) do
    player = find_player(state, user.id)
    attacker = Map.get(state.units, unit_id)
    defender = Map.get(state.units, target_unit_id)

    cond do
      is_nil(player) or is_nil(attacker) or attacker.player_id != player.id ->
        {:error, :not_owner}

      is_nil(defender) ->
        {:error, :invalid_target}

      true ->
        case validate_shoot(state, attacker, defender) do
          :ok ->
            {result, new_state} = resolve_attack(state, attacker, defender, ranged?: true)
            {:ok, result, new_state}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp validate_shoot(state, attacker, defender) do
    cond do
      attacker.type != :archer -> {:error, :not_archer}
      attacker.movement <= 0 -> {:error, :out_of_movement}
      not in_shoot_range?(state.world, attacker.tile_id, defender.tile_id) ->
        {:error, :out_of_range}

      pvp_target_allowed?(state, attacker, defender) ->
        :ok

      true ->
        {:error, :not_hostile}
    end
  end
end
