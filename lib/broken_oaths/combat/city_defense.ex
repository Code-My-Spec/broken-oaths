defmodule BrokenOaths.Combat.CityDefense do
  @moduledoc """
  Pure city-combat core: HP and defensive strength, the garrison
  stacking exception, garrison combat bonuses, pillage-not-capture, and
  the regen/production-halt bookkeeping a turn boundary applies. No
  `Repo`, no process state — mirrors `BrokenOaths.Combat.Resolver`'s role:
  `BrokenOaths.Simulation.WorldServer` (immediate city-target attacks) and
  `BrokenOaths.Simulation.Turn` (regen, production halt, the barbarian-AI
  "hold adjacent to a city" case) are the imperative shells that read a
  city and its garrison out of the canonical tick-state, call into this
  module, and write the result back.

  ## HP and defensive strength

  A city starts at `max_hp/0` (100) and its defensive strength is
  `20 + 5 × size + garrison defense` — the base defense of every
  friendly MILITARY unit standing on the city's own tile, summed
  (`defensive_strength/2`). Civilians (`:settler`, `:worker`) shelter
  on the tile for free: `garrison/2` finds every unit standing there,
  but `military_garrison/2` (and therefore the defense total) only
  ever counts `:lord`/`:warrior`/`:bronze_spearman` (story 903).

  ## Ancient Walls (story 930)

  A city with `:ancient_walls` in its own `buildings` list
  (`BrokenOaths.Cities.Production`'s `:ancient_walls` buildable, gated
  on the owner having completed Masonry) gets `wall_hp_bonus/0` (+50)
  more max HP and `wall_defense_bonus/0` (+5) more defensive strength,
  same "no new city-combat model, just two bonuses folded into the
  existing formulas" scope every other building's effect in this story
  keeps. `max_hp/1` (city-aware, unlike the arity-0 `max_hp/0` every
  OTHER caller in this codebase still uses for the flat 100 baseline —
  city founding, `Siege`, `Camp`) is the one place that reads it;
  `regen/1` is the one caller that NEEDS it, since a walled city's own
  HP now caps above 100.

  ## Garrison stacking (the one stacking exception in the game)

  Everywhere else, a player's own second unit is refused onto a tile
  it already occupies (`WorldServer`'s `occupied_by_own?/3`). A city's
  own tile is the exception: up to `garrison_cap/0` (3) friendly
  military units may stand together there. `garrison_room?/2` is the
  single predicate both the queue-time occupancy check
  (`WorldServer.do_queue_move/4`) and the tick-time movement collision
  check (`BrokenOaths.Simulation.Turn.attempt_step/2`) call to decide whether
  one more unit fits — a civilian mover always fits (and never counts
  against the cap); a military mover fits only while fewer than 3
  military units already stand there.

  ## Garrison combat bonus

  A unit standing on its own city's tile fights at +50% strength
  (`BrokenOaths.Combat.Resolver.garrisoned_strength/2`) whether it's
  striking out at an adjacent barbarian (`garrisoned?/2` is the
  predicate `WorldServer` checks before passing `attacker_garrisoned?:
  true` into `Resolver.resolve/3`) or defending the walls against an
  assault on the city itself (`resolve_attack/4`, below).

  ## Barbarian-vs-city combat

  `resolve_attack/4` resolves a barbarian's (or, per this story's own
  spec convention, a stand-in real player's) assault on a city:
  damage to the city is the same Civ VI curve `Resolver.damage/3` computes
  for unit-vs-unit combat, attacker strength against the city's own
  defensive strength (not a single defender's). The counter-blow comes
  from the single STRONGEST living garrisoned defender (ties break on
  lowest id) at its garrison-boosted strength — an undefended city
  (empty garrison) counters for nothing, so an attacker sacking an
  undefended city never takes damage back. `take_damage/3` applies the
  result to a city's HP, floored at 0, and folds in `pillage/2` the
  instant it lands there.

  ## Pillage, not capture

  A city reduced to 0 HP is pillaged (`pillage/2`): loses one
  population (floored at 1 — a size-1 city can't shrink further),
  banked production freezes for `pillage_halt_boundaries/0` (3) turn
  boundaries counted from the turn the pillage happened
  (`production_halted?/2` reads `production_halted_until` against the
  CURRENT turn — see that function's doc for the exact boundary
  count), and HP resets to `pillage_hp/0` (50, not 0 — the city is
  never destroyed). The in-flight production item itself is untouched:
  once the halt lifts, accrual resumes from whatever was already
  banked, not from zero.

  ## Regeneration

  `regen/1` heals `regen_per_boundary/0` (5) HP, capped at `max_hp/0`.
  `Turn` calls this once per boundary for every city its OWN
  barbarian-AI phase didn't attack that same tick — an attack landed
  through `WorldServer`'s immediate, out-of-tick "attack" surface
  (this story's own spec convention) never suppresses the NEXT
  boundary's regen, since it isn't part of any tick's own AI phase; see
  `Turn`'s "city regeneration" phase doc for exactly how the two
  interact.

  ## Alerts

  `approaching?/4` and `under_attack?/0`'s sibling copy helpers
  (`approach_alert/1`, `under_attack_alert/1`) back the two player
  alerts this story adds: a barbarian (or any foreign unit — the same
  stand-in convention above) closing within `approach_range/0` (3)
  hexes of a player's city, and a city actually taking a hit.
  `approaching?/4` measures distance the same way
  `BrokenOaths.Combat.Camps.ring_band/3` places camps — raw mesh
  adjacency, not the land-only path distance
  `BrokenOaths.Combat.BarbarianAI` uses for targeting — since an alert is
  about how close a threat LOOKS on the globe, not how far it would
  have to walk to arrive.
  """

  alias BrokenOaths.Cities.Buildings
  alias BrokenOaths.Combat.Resolver
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.World

  @type tile_id :: non_neg_integer()
  @type unit :: Resolver.unit()
  @type city :: %{
          optional(atom()) => term(),
          optional(:buildings) => [atom()],
          id: term(),
          player_id: term(),
          name: String.t(),
          tile_id: tile_id(),
          size: pos_integer(),
          hp: non_neg_integer(),
          worked_tiles: [tile_id()],
          production_halted_until: non_neg_integer() | nil
        }
  @type attack_result :: %{
          damage_to_city: non_neg_integer(),
          damage_to_barbarian: non_neg_integer(),
          defender_id: term() | nil
        }
  @type refusal :: :out_of_movement | :not_adjacent | :own_city

  # QA issue da39e50b — the Archer is a genuine (melee-for-now) military
  # unit; it garrisons/counts toward defense exactly like the Warrior
  # and Bronze Spearman.
  @military_types [:lord, :warrior, :bronze_spearman, :archer, :scout]

  @max_hp 100
  @base_defense 20
  @size_defense 5
  @garrison_cap 3
  @regen_per_boundary 5
  @pillage_hp 50
  @pillage_halt_boundaries 3
  @approach_range 3
  # Story 930 — Ancient Walls, see this module's own moduledoc.
  @wall_hp_bonus 50
  @wall_defense_bonus 5

  @doc "A city's max HP — every city is founded at this value."
  @spec max_hp() :: pos_integer()
  def max_hp, do: @max_hp

  @doc "`city`'s own current max HP: `max_hp/0` (100), plus `wall_hp_bonus/0` (50) once it has completed Ancient Walls (story 930)."
  @spec max_hp(city()) :: pos_integer()
  def max_hp(city), do: @max_hp + if(has_walls?(city), do: @wall_hp_bonus, else: 0)

  @doc "How much max HP Ancient Walls adds once built (story 930)."
  @spec wall_hp_bonus() :: pos_integer()
  def wall_hp_bonus, do: @wall_hp_bonus

  @doc "How much defensive strength Ancient Walls adds once built (story 930)."
  @spec wall_defense_bonus() :: pos_integer()
  def wall_defense_bonus, do: @wall_defense_bonus

  @doc "Whether `city` has completed the Ancient Walls building (story 930)."
  @spec has_walls?(city()) :: boolean()
  def has_walls?(city), do: Buildings.has?(city, :ancient_walls)

  @doc "HP a pillaged city resets to — never 0 (pillage, not destruction)."
  @spec pillage_hp() :: pos_integer()
  def pillage_hp, do: @pillage_hp

  @doc "How many turn boundaries a pillaged city's production stays frozen."
  @spec pillage_halt_boundaries() :: pos_integer()
  def pillage_halt_boundaries, do: @pillage_halt_boundaries

  @doc "HP a city regains each unthreatened turn boundary, capped at `max_hp/0`."
  @spec regen_per_boundary() :: pos_integer()
  def regen_per_boundary, do: @regen_per_boundary

  @doc "How many friendly military units may garrison a single city tile."
  @spec garrison_cap() :: pos_integer()
  def garrison_cap, do: @garrison_cap

  @doc "How close (raw mesh hexes) a threat must be to trigger the approach alert."
  @spec approach_range() :: pos_integer()
  def approach_range, do: @approach_range

  @doc "Whether `unit` is a combat-capable (garrison-eligible) type — `:lord`, `:warrior`, `:bronze_spearman` (story 903), or `:archer` (QA issue da39e50b)."
  @spec military?(unit()) :: boolean()
  def military?(%{type: type}), do: type in @military_types

  # -------------------------------------------------------------------
  # Garrison
  # -------------------------------------------------------------------

  @doc "Every unit (military or civilian) standing on `city`'s own tile."
  @spec garrison(city(), [unit()]) :: [unit()]
  def garrison(city, units), do: Enum.filter(units, &(&1.tile_id == city.tile_id))

  @doc "The military subset of `garrison/2` — the only units that count toward the cap or add defense."
  @spec military_garrison(city(), [unit()]) :: [unit()]
  def military_garrison(city, units), do: city |> garrison(units) |> Enum.filter(&military?/1)

  @doc """
  Whether `mover` may join `existing_units_on_tile` — the units already
  standing on the destination tile it's entering. A civilian always
  fits and never counts against the cap; a military mover fits only
  while fewer than `garrison_cap/0` military units are already there.
  Callers are responsible for confirming the destination is actually
  the mover's own city's tile in the first place — this predicate is
  the same regardless of tile identity, so a non-city destination
  should never reach it (see `WorldServer.occupied_by_own?/4`).
  """
  @spec garrison_room?(unit(), [unit()]) :: boolean()
  def garrison_room?(%{type: type}, _existing_units_on_tile) when type not in @military_types,
    do: true

  def garrison_room?(_mover, existing_units_on_tile) do
    existing_units_on_tile |> Enum.filter(&military?/1) |> length() < @garrison_cap
  end

  @doc """
  Whether `unit` currently qualifies for the garrison combat bonus:
  a military unit standing on ITS OWN player's city's own tile.
  """
  @spec garrisoned?(unit(), [city()]) :: boolean()
  def garrisoned?(unit, cities) do
    military?(unit) and
      Enum.any?(cities, &(&1.tile_id == unit.tile_id and &1.player_id == unit.player_id))
  end

  # -------------------------------------------------------------------
  # Defensive strength
  # -------------------------------------------------------------------

  @doc "City defensive strength: `20 + 5 × size` plus the summed base defense of its military garrison, plus `wall_defense_bonus/0` (+5) once it has Ancient Walls (story 930)."
  @spec defensive_strength(city(), [unit()]) :: non_neg_integer()
  def defensive_strength(city, units) do
    garrison_defense =
      city |> military_garrison(units) |> Enum.map(&Resolver.base_strength(&1.type)) |> Enum.sum()

    wall_bonus = if has_walls?(city), do: @wall_defense_bonus, else: 0

    @base_defense + @size_defense * city.size + garrison_defense + wall_bonus
  end

  # -------------------------------------------------------------------
  # Barbarian-vs-city combat
  # -------------------------------------------------------------------

  @doc """
  Resolve `attacker`'s assault on `city`: damage to the city (attacker
  strength against the city's own `defensive_strength/2`, capped at the
  city's current HP so a single hit never drives it negative) and
  counter-damage to `attacker` from the single strongest living
  garrisoned defender at its garrison-boosted strength (0, no
  defender, if the city is undefended). Required `opts`:

    * `:seed` — any term; rolls are deterministic for a given seed
    * `:attacker_aura?` — whether `attacker` stands adjacent to its own
      living lord (default `false`)
    * `:ranged?` — playtest issue 0edd8679, default `false`: when
      `true` (`BrokenOaths.Combat.Siege.shoot_city/4`'s own Archer
      shot), `attacker`'s own strength comes from `Resolver.
      ranged_strength/1` instead of `Resolver.base_strength/1` — the
      SAME attacker-side-only switch `Resolver.combat_strength/3` uses
      for a unit target. `BrokenOaths.Simulation.Turn.BarbarianPhase`'s
      own barbarian-vs-city call never passes this (barbarians can't
      shoot), so that path is untouched.
  """
  @spec resolve_attack(city(), [unit()], unit(), keyword()) :: attack_result()
  def resolve_attack(city, units, attacker, opts) do
    seed = Keyword.fetch!(opts, :seed)
    attacker_aura? = Keyword.get(opts, :attacker_aura?, false)
    ranged? = Keyword.get(opts, :ranged?, false)

    attacker_strength_value =
      if ranged?,
        do: Resolver.ranged_strength(attacker.type),
        else: Resolver.base_strength(attacker.type)

    resisting_strength = defensive_strength(city, units)

    striking_strength =
      Resolver.effective_strength(attacker, attacker_aura?, false, attacker_strength_value)

    damage_to_city =
      min(Resolver.damage(striking_strength, resisting_strength, {seed, :to_city}), city.hp)

    case strongest_defender(city, units) do
      nil ->
        %{damage_to_city: damage_to_city, damage_to_barbarian: 0, defender_id: nil}

      defender ->
        counter_strength = Resolver.garrisoned_strength(defender)

        attacker_strength =
          Resolver.effective_strength(attacker, attacker_aura?, false, attacker_strength_value)

        damage_to_barbarian =
          Resolver.damage(counter_strength, attacker_strength, {seed, :to_attacker})

        %{
          damage_to_city: damage_to_city,
          damage_to_barbarian: damage_to_barbarian,
          defender_id: defender.id
        }
    end
  end

  defp strongest_defender(city, units) do
    city
    |> military_garrison(units)
    |> Enum.filter(&(&1.hp > 0))
    |> Enum.sort_by(&{-Resolver.base_strength(&1.type), &1.id})
    |> List.first()
  end

  @doc """
  Whether `attacker` may legally assault `city` right now: movement
  left, the city on an adjacent tile, and `attacker` isn't the city's
  own owner (a player can never attack their own city; every OTHER
  player's unit is a legal attacker here — city assault doesn't share
  `Resolver.hostile?/2`'s "no Stone Age PvP" restriction on unit-vs-unit
  combat, per this story's own spec convention of standing a second
  real player's unit in for a barbarian).
  """
  @spec validate_attack(unit(), city(), [tile_id()]) :: :ok | {:error, refusal()}
  def validate_attack(attacker, city, adjacent_tile_ids) do
    cond do
      attacker.movement <= 0 -> {:error, :out_of_movement}
      city.tile_id not in adjacent_tile_ids -> {:error, :not_adjacent}
      attacker.player_id == city.player_id -> {:error, :own_city}
      true -> :ok
    end
  end

  # -------------------------------------------------------------------
  # Damage application, pillage, regen
  # -------------------------------------------------------------------

  @doc "Apply `damage` to `city`'s HP, floored at 0 — pillaging it (`pillage/2`) the instant it lands there."
  @spec take_damage(city(), non_neg_integer(), non_neg_integer()) :: city()
  def take_damage(city, damage, current_turn) do
    case max(city.hp - damage, 0) do
      0 -> pillage(%{city | hp: 0}, current_turn)
      hp -> %{city | hp: hp}
    end
  end

  @doc """
  Pillage `city`, pillaged at `current_turn`: -1 population (floored at
  1), HP resets to `pillage_hp/0`, worked tiles trimmed to fit the new
  (smaller) population, and production frozen through
  `pillage_halt_boundaries/0` more boundaries — see
  `production_halted?/2` for exactly which boundaries that covers.
  """
  @spec pillage(city(), non_neg_integer()) :: city()
  def pillage(city, current_turn) do
    new_size = max(city.size - 1, 1)

    %{
      city
      | size: new_size,
        hp: @pillage_hp,
        worked_tiles: Enum.take(city.worked_tiles, new_size),
        production_halted_until: current_turn + @pillage_halt_boundaries
    }
  end

  @doc """
  Whether `city`'s production is still frozen at `turn` (the CURRENT,
  not-yet-incremented turn a boundary is about to advance FROM — see
  `BrokenOaths.Simulation.Turn.tick/1`'s own phase ordering). A city pillaged
  at turn T freezes accrual for exactly the three boundaries that bump
  the turn from T→T+1, T+1→T+2, and T+2→T+3 (`production_halted_until`
  is `T + pillage_halt_boundaries/0`); the boundary that bumps T+3→T+4
  sees `turn == production_halted_until` and resumes.
  """
  @spec production_halted?(city(), non_neg_integer()) :: boolean()
  def production_halted?(city, turn) do
    case Map.get(city, :production_halted_until) do
      nil -> false
      halted_until -> turn < halted_until
    end
  end

  @doc """
  Heal `city` `regen_per_boundary/0` HP, capped at `max_hp/1` (story
  930: 100, or 150 once the city has Ancient Walls — a guard can't call
  a user function, so the cap-aware clause is a plain `min/2` rather
  than a `when hp >= max_hp(city)` guard clause) — effectively a no-op
  already at full HP. Also a no-op at exactly 0 HP: a barbarian assault
  never actually leaves a city sitting at 0 by the time this phase runs
  (`take_damage/3` folds `pillage/2` in the SAME calculation, resetting
  HP to `pillage_hp/0` before `regen/1` is ever called), so a city THIS
  function finds at 0 is always story 906's own player-siege "broken"
  state (`BrokenOaths.Combat.Siege.broken?/1`) — the walls are down, there
  is nothing left to regenerate, and the city stays exactly at 0 until
  it's captured, not healed back onto its feet by a passive boundary.
  """
  @spec regen(city()) :: city()
  def regen(%{hp: 0} = city), do: city
  def regen(city), do: %{city | hp: min(max_hp(city), city.hp + @regen_per_boundary)}

  # -------------------------------------------------------------------
  # Tick-loop regen (story 895 -- moved from `BrokenOaths.Simulation.Turn`'s
  # own private `regen_cities/2`, the tick-decomposition pass, see
  # `.code_my_spec/knowledge/genserver_decomposition.md`)
  # -------------------------------------------------------------------

  @doc """
  Regen every city in `state.cities` via `regen/1`, EXCEPT any city id
  in `attacked_cities` -- this tick's own `BrokenOaths.Simulation.Turn.
  BarbarianPhase` assaults -- which is left exactly as the assault left
  it this boundary. A city hit through `BrokenOaths.Simulation.WorldServer`'s
  immediate, out-of-tick "attack" surface never suppresses this -- only
  an attack that's part of THIS tick's own AI phase does, so the very
  next boundary after an out-of-band hit still regens. `state` is the
  canonical tick-state described in `BrokenOaths.Simulation.Turn`.
  """
  @spec regen_cities(map(), MapSet.t()) :: map()
  def regen_cities(state, attacked_cities) do
    cities =
      Map.new(state.cities, fn {id, city} ->
        if MapSet.member?(attacked_cities, id) do
          {id, city}
        else
          {id, regen(city)}
        end
      end)

    %{state | cities: cities}
  end

  # -------------------------------------------------------------------
  # Alerts
  # -------------------------------------------------------------------

  @doc """
  Whether `unit_tile` sits within `hexes` (default `approach_range/0`)
  raw mesh-adjacency hops of `city_tile` — see this module's doc for
  why raw adjacency, not land-path distance.
  """
  @spec approaching?(World.t(), tile_id(), tile_id(), pos_integer()) :: boolean()
  def approaching?(world, city_tile, unit_tile, hexes \\ @approach_range) do
    MapSet.member?(mesh_disk(world, city_tile, hexes), unit_tile)
  end

  defp mesh_disk(world, start, max_depth) do
    {_frontier, seen} =
      Enum.reduce(1..max_depth, {[start], MapSet.new([start])}, fn _, {frontier, seen} ->
        next =
          frontier
          |> Enum.flat_map(&Regions.adjacent_tiles(world, &1))
          |> Enum.uniq()
          |> Enum.reject(&MapSet.member?(seen, &1))

        {next, MapSet.union(seen, MapSet.new(next))}
      end)

    MapSet.delete(seen, start)
  end

  @doc "Copy for the approach alert (`\"game:alert\"` push) — story copy, §3.3/§10.3."
  @spec approach_alert(String.t()) :: String.t()
  def approach_alert(city_name),
    do: "Barbarians approaching #{city_name}! #{@approach_range} hexes away."

  @doc "Copy for the under-attack alert (`\"game:alert\"` push) — story copy, §3.3/§10.3."
  @spec under_attack_alert(String.t()) :: String.t()
  def under_attack_alert(city_name), do: "Your city #{city_name} is under attack!"
end
