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

  ## Garrison bonus (story 895)

  A unit standing on its own city's tile fights at +50% strength,
  whichever side of the exchange it's on — `garrisoned_strength/2` is
  `effective_strength/2` (aura folded in, then wounding scaled) times
  1.5. `resolve/3` accepts `:attacker_garrisoned?`/`:defender_garrisoned?`
  opts (default `false`) that switch a side onto this boosted strength
  instead of the plain one; `BrokenOaths.Game.CityDefense` is the seam
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

  ## Attack orchestration (stories 891/893/896/899/914)

  `attack/4` and `resolve_attack/3` are the pragdave-pattern "domain
  model" home (`.code_my_spec/knowledge/genserver_decomposition.md`)
  for the unit-vs-unit "attack" flow `BrokenOaths.Game.WorldServer`
  used to bury inline: they take the WorldServer's own tick-`state`
  (see `BrokenOaths.Game.Turn`'s moduledoc for that shape) plus plain
  args and return either a reply tuple or an updated `state` — no
  `GenServer`, no `handle_*`, no process awareness. `WorldServer`'s own
  `:attack` `handle_call` (and the test-only
  `:resolve_barbarian_attack_for_test` bridge) are thin delegations
  into this section. Coordinates its siblings directly, per the north
  star's "cross-cutting operations are orchestrated by their OWNING
  domain model calling its siblings" rule: `BrokenOaths.Game.
  Rebellion.War` and `BrokenOaths.Game.ProtectionPact` for the two
  feudal PvP exceptions (never duplicated here), `BrokenOaths.Game.
  CityDefense` for the garrison-bonus lookup.
  """

  alias BrokenOaths.Game.BarbarianAI
  alias BrokenOaths.Game.CityDefense
  alias BrokenOaths.Game.ProtectionPact
  alias BrokenOaths.Game.Rebellion.War
  alias BrokenOaths.Worlds.Regions

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
          max_movement: non_neg_integer()
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
    # engine has no ranged-attack model at all; see
    # `BrokenOaths.Game.Production`'s own moduledoc, "The Archer", for
    # the full rationale and the ranged-attack follow-up flag), single
    # strength like every other unit here, between the Warrior (10) and
    # the Bronze Spearman (16).
    archer: 14
  }
  @lord_aura_bonus 2
  @garrison_bonus 1.5
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
  `unit`'s combat strength while garrisoned on its own city's tile
  (story 895): `effective_strength/2`, boosted 50% for fighting from
  the walls. Callers (`BrokenOaths.Game.CityDefense`) determine whether
  a unit qualifies; this module only applies the multiplier.
  """
  @spec garrisoned_strength(unit(), boolean()) :: float()
  def garrisoned_strength(unit, aura? \\ false),
    do: effective_strength(unit, aura?) * @garrison_bonus

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

    if Keyword.get(opts, :"#{side}_garrisoned?", false) do
      garrisoned_strength(unit, aura?)
    else
      effective_strength(unit, aura?)
    end
  end

  @doc """
  The Civ VI damage curve for a single direction of an exchange: 30
  base damage at equal strength, scaling ~4% per point of strength
  difference, with a ±25% random roll seeded from `roll_seed` (see this
  module's Determinism doc). Public so `BrokenOaths.Game.CityDefense`
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
  # from `BrokenOaths.Game.WorldServer`; see this module's own
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
  # to `hostile?/2`'s own unchanged verdict.
  defp validate_pvp_attack(state, attacker, defender, adjacent_tile_ids) do
    cond do
      attacker.movement <= 0 -> {:error, :out_of_movement}
      defender.tile_id not in adjacent_tile_ids -> {:error, :not_adjacent}
      hostile?(attacker, defender) -> :ok
      protecting_lord_may_strike?(state, attacker, defender) -> :ok
      War.rebellion_war?(state, attacker.player_id, defender.player_id) -> :ok
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
  barbarian attacker has no owning session to satisfy it). Applies
  `resolve/3`'s damage, drops whichever side reached 0 HP, schedules an
  heir if a lord fell, pays the barbarian-kill bounty, and
  raises/resolves any Protection Pact call the exchange touches.
  """
  @spec resolve_attack(map(), unit(), unit()) :: {attack_outcome(), map()}
  def resolve_attack(state, attacker, defender) do
    seed = {state.world.seed, state.turn, attacker.id, defender.id}

    %{damage_to_defender: dealt, damage_to_attacker: taken} =
      resolve(attacker, defender,
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
  # into `BrokenOaths.Game.Siege`/`BrokenOaths.Game.Turn`/`WorldServer`
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
end
