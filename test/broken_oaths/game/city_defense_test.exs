defmodule BrokenOaths.Game.CityDefenseTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Game.CityDefense
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.World

  @frequency 8
  @seed 424_242

  defp world, do: %World{seed: @seed, frequency: @frequency}

  defp unit(id, opts) do
    max_hp = Keyword.get(opts, :max_hp, 100)
    max_movement = Keyword.get(opts, :max_movement, 1)

    %{
      id: id,
      player_id: Keyword.get(opts, :player_id, 1),
      type: Keyword.get(opts, :type, :warrior),
      tile_id: Keyword.fetch!(opts, :tile),
      hp: Keyword.get(opts, :hp, max_hp),
      max_hp: max_hp,
      movement: Keyword.get(opts, :movement, max_movement),
      max_movement: max_movement
    }
  end

  defp city(id, opts) do
    %{
      id: id,
      player_id: Keyword.get(opts, :player_id, 1),
      name: Keyword.get(opts, :name, "Test City"),
      tile_id: Keyword.fetch!(opts, :tile),
      size: Keyword.get(opts, :size, 1),
      hp: Keyword.get(opts, :hp, CityDefense.max_hp()),
      worked_tiles: Keyword.get(opts, :worked_tiles, []),
      production_halted_until: Keyword.get(opts, :production_halted_until)
    }
  end

  describe "constants" do
    test "the design doc's numbers" do
      assert CityDefense.max_hp() == 100
      assert CityDefense.pillage_hp() == 50
      assert CityDefense.pillage_halt_boundaries() == 3
      assert CityDefense.regen_per_boundary() == 5
      assert CityDefense.garrison_cap() == 3
      assert CityDefense.approach_range() == 3
    end
  end

  describe "military?/1" do
    test "lord and warrior are military" do
      assert CityDefense.military?(unit(1, type: :lord, tile: 1))
      assert CityDefense.military?(unit(1, type: :warrior, tile: 1))
    end

    test "settler and worker are civilian" do
      refute CityDefense.military?(unit(1, type: :settler, tile: 1))
      refute CityDefense.military?(unit(1, type: :worker, tile: 1))
    end

    # QA issue da39e50b "No archer" — a genuine (melee-for-now) military
    # unit: garrison-eligible and counts toward city defense.
    test "the Archer is military" do
      assert CityDefense.military?(unit(1, type: :archer, tile: 1))
    end
  end

  describe "garrison/2 and military_garrison/2" do
    test "garrison/2 finds every unit standing on the city's own tile, civilians included" do
      c = city(1, tile: 10)
      warrior = unit(1, type: :warrior, tile: 10)
      worker = unit(2, type: :worker, tile: 10)
      elsewhere = unit(3, type: :warrior, tile: 11)

      assert CityDefense.garrison(c, [warrior, worker, elsewhere])
             |> Enum.map(& &1.id)
             |> Enum.sort() ==
               [1, 2]
    end

    test "military_garrison/2 excludes civilians" do
      c = city(1, tile: 10)
      warrior = unit(1, type: :warrior, tile: 10)
      worker = unit(2, type: :worker, tile: 10)

      assert CityDefense.military_garrison(c, [warrior, worker]) |> Enum.map(& &1.id) == [1]
    end
  end

  describe "garrison_room?/2" do
    test "a civilian always fits, regardless of how many military units already stand there" do
      three_warriors = for id <- 1..3, do: unit(id, type: :warrior, tile: 10)
      worker = unit(4, type: :worker, tile: 10)
      assert CityDefense.garrison_room?(worker, three_warriors)
    end

    test "a military unit fits under the cap" do
      two_warriors = for id <- 1..2, do: unit(id, type: :warrior, tile: 10)
      assert CityDefense.garrison_room?(unit(3, type: :warrior, tile: 10), two_warriors)
    end

    test "a military unit is refused once the cap (3) is already full" do
      three_warriors = for id <- 1..3, do: unit(id, type: :warrior, tile: 10)
      refute CityDefense.garrison_room?(unit(4, type: :lord, tile: 10), three_warriors)
    end

    test "civilians already present don't count against the military cap" do
      garrison = [unit(1, type: :worker, tile: 10), unit(2, type: :worker, tile: 10)]
      assert CityDefense.garrison_room?(unit(3, type: :warrior, tile: 10), garrison)
    end
  end

  describe "garrisoned?/2" do
    test "a military unit standing on its own city's own tile qualifies" do
      c = city(1, player_id: 1, tile: 10)
      warrior = unit(1, player_id: 1, type: :warrior, tile: 10)
      assert CityDefense.garrisoned?(warrior, [c])
    end

    test "a civilian on the same tile does not qualify" do
      c = city(1, player_id: 1, tile: 10)
      worker = unit(1, player_id: 1, type: :worker, tile: 10)
      refute CityDefense.garrisoned?(worker, [c])
    end

    test "a military unit on a DIFFERENT player's city tile does not qualify" do
      c = city(1, player_id: 2, tile: 10)
      warrior = unit(1, player_id: 1, type: :warrior, tile: 10)
      refute CityDefense.garrisoned?(warrior, [c])
    end

    test "a military unit not standing on any city tile does not qualify" do
      c = city(1, player_id: 1, tile: 10)
      warrior = unit(1, player_id: 1, type: :warrior, tile: 11)
      refute CityDefense.garrisoned?(warrior, [c])
    end
  end

  describe "defensive_strength/2" do
    test "criterion 7562's exact figure: size-1 city, one garrisoned warrior — 20 + 5×1 + 10 = 35" do
      c = city(1, size: 1, tile: 10)
      warrior = unit(1, type: :warrior, tile: 10)
      assert CityDefense.defensive_strength(c, [warrior]) == 35
    end

    test "an undefended city is just the base + size formula" do
      c = city(1, size: 2, tile: 10)
      assert CityDefense.defensive_strength(c, []) == 20 + 5 * 2
    end

    test "every military garrisoned unit's base strength adds in" do
      c = city(1, size: 1, tile: 10)
      warrior = unit(1, type: :warrior, tile: 10)
      lord = unit(2, type: :lord, tile: 10)
      assert CityDefense.defensive_strength(c, [warrior, lord]) == 20 + 5 * 1 + 10 + 12
    end

    test "a civilian garrisoned alongside adds nothing" do
      c = city(1, size: 1, tile: 10)
      warrior = unit(1, type: :warrior, tile: 10)
      worker = unit(2, type: :worker, tile: 10)

      assert CityDefense.defensive_strength(c, [warrior, worker]) ==
               CityDefense.defensive_strength(c, [warrior])
    end
  end

  describe "resolve_attack/4" do
    test "an undefended city takes damage but its attacker takes none back" do
      c = city(1, size: 1, tile: 10, hp: 100)
      barbarian = unit(1, player_id: nil, type: :warrior, tile: 11)

      result = CityDefense.resolve_attack(c, [], barbarian, seed: {:test, 1})

      assert result.damage_to_city > 0
      assert result.damage_to_barbarian == 0
      assert result.defender_id == nil
    end

    test "a garrisoned city counter-attacks the barbarian" do
      c = city(1, size: 1, tile: 10, hp: 100)
      warrior = unit(1, type: :warrior, tile: 10)
      barbarian = unit(2, player_id: nil, type: :warrior, tile: 11)

      result = CityDefense.resolve_attack(c, [warrior], barbarian, seed: {:test, 2})

      assert result.damage_to_city > 0
      assert result.damage_to_barbarian > 0
      assert result.defender_id == warrior.id
    end

    test "damage to the city never exceeds its current HP" do
      c = city(1, size: 1, tile: 10, hp: 3)
      barbarian = unit(1, player_id: nil, type: :warrior, tile: 11)

      result = CityDefense.resolve_attack(c, [], barbarian, seed: {:test, 3})
      assert result.damage_to_city == 3
    end

    test "the strongest living garrisoned defender counters, ties break on lowest id" do
      c = city(1, size: 1, tile: 10, hp: 100)
      lord = unit(2, type: :lord, tile: 10)
      warrior = unit(1, type: :warrior, tile: 10)
      barbarian = unit(3, player_id: nil, type: :warrior, tile: 11)

      result = CityDefense.resolve_attack(c, [warrior, lord], barbarian, seed: {:test, 4})
      assert result.defender_id == lord.id
    end

    test "a dead garrisoned unit never counters" do
      c = city(1, size: 1, tile: 10, hp: 100)
      dead_warrior = unit(1, type: :warrior, tile: 10, hp: 0)
      barbarian = unit(2, player_id: nil, type: :warrior, tile: 11)

      result = CityDefense.resolve_attack(c, [dead_warrior], barbarian, seed: {:test, 5})
      assert result.damage_to_barbarian == 0
      assert result.defender_id == nil
    end

    test "same seed, same result — deterministic" do
      c = city(1, size: 1, tile: 10, hp: 100)
      warrior = unit(1, type: :warrior, tile: 10)
      barbarian = unit(2, player_id: nil, type: :warrior, tile: 11)

      a = CityDefense.resolve_attack(c, [warrior], barbarian, seed: {:pin, 42})
      b = CityDefense.resolve_attack(c, [warrior], barbarian, seed: {:pin, 42})
      assert a == b
    end
  end

  describe "validate_attack/3" do
    test "refuses an attacker with no movement left" do
      c = city(1, player_id: 2, tile: 10)
      attacker = unit(1, player_id: 1, tile: 11, movement: 0)
      assert CityDefense.validate_attack(attacker, c, [10]) == {:error, :out_of_movement}
    end

    test "refuses a city that isn't adjacent" do
      c = city(1, player_id: 2, tile: 10)
      attacker = unit(1, player_id: 1, tile: 99)
      assert CityDefense.validate_attack(attacker, c, [20, 21]) == {:error, :not_adjacent}
    end

    test "refuses attacking your own city" do
      c = city(1, player_id: 1, tile: 10)
      attacker = unit(1, player_id: 1, tile: 11)
      assert CityDefense.validate_attack(attacker, c, [10]) == {:error, :own_city}
    end

    test "allows a barbarian (nil player_id) to attack any player's city" do
      c = city(1, player_id: 1, tile: 10)
      barbarian = unit(1, player_id: nil, tile: 11)
      assert CityDefense.validate_attack(barbarian, c, [10]) == :ok
    end

    test "allows one player's unit to attack another player's city" do
      c = city(1, player_id: 2, tile: 10)
      attacker = unit(1, player_id: 1, tile: 11)
      assert CityDefense.validate_attack(attacker, c, [10]) == :ok
    end
  end

  describe "take_damage/3" do
    test "damage below current HP simply lowers it" do
      c = city(1, tile: 10, hp: 50)
      assert CityDefense.take_damage(c, 10, 5).hp == 40
    end

    test "damage that reaches exactly 0 pillages the city instead of leaving it at 0" do
      c = city(1, tile: 10, hp: 10, size: 2)
      new_city = CityDefense.take_damage(c, 10, 5)

      assert new_city.hp == CityDefense.pillage_hp()
      assert new_city.size == 1
    end

    test "damage that would overkill still floors at 0 before pillaging" do
      c = city(1, tile: 10, hp: 10, size: 2)
      new_city = CityDefense.take_damage(c, 999, 5)
      assert new_city.hp == CityDefense.pillage_hp()
    end
  end

  describe "pillage/2" do
    test "loses one population, floored at 1" do
      assert CityDefense.pillage(city(1, tile: 10, size: 2), 5).size == 1
      assert CityDefense.pillage(city(1, tile: 10, size: 1), 5).size == 1
    end

    test "HP resets to pillage_hp/0, not 0" do
      assert CityDefense.pillage(city(1, tile: 10, size: 3, hp: 0), 5).hp ==
               CityDefense.pillage_hp()
    end

    test "worked tiles are trimmed to fit the smaller population" do
      c = city(1, tile: 10, size: 2, worked_tiles: [11, 12])
      assert CityDefense.pillage(c, 5).worked_tiles == [11]
    end

    test "production_halted_until is set 3 boundaries out from the current turn" do
      c = city(1, tile: 10, size: 2)
      assert CityDefense.pillage(c, 5).production_halted_until == 8
    end
  end

  describe "production_halted?/2" do
    test "a city that's never been pillaged is never halted" do
      c = city(1, tile: 10)
      refute CityDefense.production_halted?(c, 100)
    end

    test "halted for exactly the three boundaries after a pillage at turn T, resuming on the fourth" do
      # Pillaged at turn 5 -> production_halted_until: 8 (see pillage/2 test above).
      c = city(1, tile: 10, production_halted_until: 8)

      assert CityDefense.production_halted?(c, 5)
      assert CityDefense.production_halted?(c, 6)
      assert CityDefense.production_halted?(c, 7)
      refute CityDefense.production_halted?(c, 8)
      refute CityDefense.production_halted?(c, 9)
    end
  end

  describe "regen/1" do
    test "heals regen_per_boundary/0 HP" do
      c = city(1, tile: 10, hp: 50)
      assert CityDefense.regen(c).hp == 55
    end

    test "caps at max_hp/0" do
      c = city(1, tile: 10, hp: 98)
      assert CityDefense.regen(c).hp == CityDefense.max_hp()
    end

    test "a full-HP city is a no-op" do
      c = city(1, tile: 10, hp: CityDefense.max_hp())
      assert CityDefense.regen(c) == c
    end
  end

  describe "approaching?/4" do
    test "a threat sitting exactly on the approach range's outer edge counts" do
      city_tile = 0

      ring3 =
        Enum.reduce(1..3, {[city_tile], MapSet.new([city_tile])}, fn _, {frontier, seen} ->
          next =
            frontier
            |> Enum.flat_map(&Regions.adjacent_tiles(world(), &1))
            |> Enum.uniq()
            |> Enum.reject(&MapSet.member?(seen, &1))

          {next, MapSet.union(seen, MapSet.new(next))}
        end)
        |> elem(0)

      [threat_tile | _] = ring3
      assert CityDefense.approaching?(world(), city_tile, threat_tile)
    end

    test "a threat beyond the approach range does not count" do
      city_tile = 0

      far =
        Enum.reduce(
          1..(CityDefense.approach_range() + 2),
          {[city_tile], MapSet.new([city_tile])},
          fn
            _, {frontier, seen} ->
              next =
                frontier
                |> Enum.flat_map(&Regions.adjacent_tiles(world(), &1))
                |> Enum.uniq()
                |> Enum.reject(&MapSet.member?(seen, &1))

              {next, MapSet.union(seen, MapSet.new(next))}
          end
        )
        |> elem(0)

      [threat_tile | _] = far
      refute CityDefense.approaching?(world(), city_tile, threat_tile)
    end

    test "a threat standing on the city's own tile does not count as 'approaching'" do
      refute CityDefense.approaching?(world(), 0, 0)
    end
  end

  describe "approach_alert/1 and under_attack_alert/1" do
    test "story copy, exact wording" do
      assert CityDefense.approach_alert("Riverdale") ==
               "Barbarians approaching Riverdale! 3 hexes away."

      assert CityDefense.under_attack_alert("Riverdale") == "Your city Riverdale is under attack!"
    end
  end
end
