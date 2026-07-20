defmodule BrokenOaths.Combat.ResolverTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Combat.Resolver

  # Same unit() shape/defaults as turn_test.exs, plus player_id/type
  # defaults suited to combat fixtures.
  defp unit(id, opts \\ []) do
    max_hp = Keyword.get(opts, :max_hp, 100)
    max_movement = Keyword.get(opts, :max_movement, 1)

    %{
      id: id,
      player_id: Keyword.get(opts, :player_id, 1),
      type: Keyword.get(opts, :type, :warrior),
      tile_id: Keyword.get(opts, :tile_id, id),
      hp: Keyword.get(opts, :hp, max_hp),
      max_hp: max_hp,
      movement: Keyword.get(opts, :movement, max_movement),
      max_movement: max_movement
    }
  end

  # The Civ VI curve, computed independently of Combat's own constants
  # — the spec these tests check Combat against, not a copy of its
  # implementation.
  defp expected_band(striking_strength, resisting_strength) do
    base = 30 * :math.exp(0.04 * (striking_strength - resisting_strength))
    {round(base * 0.75), round(base * 1.25)}
  end

  describe "base_strength/1" do
    test "matches the design doc's per-type table" do
      assert Resolver.base_strength(:lord) == 12
      assert Resolver.base_strength(:warrior) == 10
      assert Resolver.base_strength(:settler) == 0
      assert Resolver.base_strength(:worker) == 0
    end

    test "the Bronze Spearman (story 903) matches civ6_tech_tree.md's recommendation" do
      assert Resolver.base_strength(:bronze_spearman) == 16
    end

    # QA issue da39e50b "No archer" — a first-pass MELEE unit (this
    # engine has no ranged-attack model), strength 14: above the
    # Warrior (10), below the Bronze Spearman (16).
    test "the Archer (QA issue da39e50b) sits between the Warrior and the Bronze Spearman" do
      assert Resolver.base_strength(:archer) == 14
    end
  end

  describe "effective_strength/2" do
    test "a full-HP unit fights at its plain base strength" do
      assert Resolver.effective_strength(unit(1, hp: 100, max_hp: 100)) == 10.0
    end

    test "a unit at 0 HP fights at half strength — the wounded floor" do
      assert Resolver.effective_strength(unit(1, hp: 0, max_hp: 100)) == 5.0
    end

    test "criterion 7575's exact figure: a warrior at 20/100 HP fights at strength 6" do
      assert Resolver.effective_strength(unit(1, hp: 20, max_hp: 100)) == 6.0
    end

    test "the lord's aura adds +2 strength before the wounded penalty scales it" do
      full = unit(1, type: :warrior, hp: 100, max_hp: 100)
      assert Resolver.effective_strength(full, true) == 12.0

      # At 20/100 HP (0.6x), the aura is folded in BEFORE scaling:
      # (10 + 2) * 0.6 = 7.2 — not 6.0 (aura ignored) or 6.5 (a raw +2
      # tacked on after scaling the base alone). No spec asserts a
      # wounded+aura'd unit (see this module's moduledoc for the
      # judgment call); this test pins the chosen behavior.
      wounded = unit(1, type: :warrior, hp: 20, max_hp: 100)
      assert_in_delta Resolver.effective_strength(wounded, true), 7.2, 1.0e-9
    end

    test "the lord itself carries innate strength 12 with no self-aura" do
      lord = unit(1, type: :lord, hp: 150, max_hp: 150)
      assert Resolver.effective_strength(lord) == 12.0
    end
  end

  describe "resolve/3 — the Civ VI damage curve" do
    test "equal strength always lands within the ±25% band around 30 base damage" do
      {lo, hi} = expected_band(10, 10)
      a = unit(1, hp: 100, max_hp: 100)
      d = unit(2, hp: 100, max_hp: 100, player_id: nil)

      for seed <- 1..50 do
        %{damage_to_defender: dealt, damage_to_attacker: taken} =
          Resolver.resolve(a, d, seed: {:equal, seed})

        assert dealt in lo..hi
        assert taken in lo..hi
      end
    end

    test "a weaker attacker (10) still lands a hit on a stronger defender (12), within its band" do
      {lo, hi} = expected_band(10, 12)
      {counter_lo, counter_hi} = expected_band(12, 10)

      a = unit(1, type: :warrior, hp: 100, max_hp: 100)
      d = unit(2, type: :lord, hp: 150, max_hp: 150, player_id: nil)

      for seed <- 1..100 do
        %{damage_to_defender: dealt, damage_to_attacker: taken} =
          Resolver.resolve(a, d, seed: {:asymmetric, seed})

        assert dealt in lo..hi
        assert taken in counter_lo..counter_hi
      end
    end

    test "criterion 7541's exact band: an aura'd strength-12 attacker vs a strength-12 defender lands harder than unaura'd strength-10 would" do
      {lo, hi} = expected_band(12, 12)

      a = unit(1, type: :warrior, hp: 100, max_hp: 100)
      d = unit(2, type: :lord, hp: 150, max_hp: 150, player_id: nil)

      for seed <- 1..100 do
        dealt =
          Resolver.resolve(a, d, seed: {:aura, seed}, attacker_aura?: true).damage_to_defender

        assert dealt in lo..hi
      end
    end

    test "the roll is deterministic: the same seed always reproduces the same exchange" do
      a = unit(1)
      d = unit(2, player_id: nil)

      first = Resolver.resolve(a, d, seed: "fixed-seed")
      second = Resolver.resolve(a, d, seed: "fixed-seed")

      assert first == second
    end

    test "different seeds vary the outcome across a wide sample" do
      a = unit(1)
      d = unit(2, player_id: nil)

      outcomes =
        for seed <- 1..30, into: MapSet.new() do
          Resolver.resolve(a, d, seed: seed).damage_to_defender
        end

      assert MapSet.size(outcomes) > 1
    end

    test "a dying defender still lands its counter-blow, computed from its pre-combat strength" do
      a = unit(1, hp: 100, max_hp: 100)
      dying = unit(2, hp: 1, max_hp: 100, player_id: nil)
      full_hp = %{dying | hp: 100}

      dying_result = Resolver.resolve(a, dying, seed: "same")
      full_hp_result = Resolver.resolve(a, full_hp, seed: "same")

      # A near-dead defender is weaker (its own wounded strength deals
      # less), never zero — the counter-blow always lands.
      assert dying_result.damage_to_attacker > 0
      assert dying_result.damage_to_attacker < full_hp_result.damage_to_attacker
    end
  end

  describe "resolve/3 — Bronze Spearman vs Barbarian Warrior (story 903, criterion 7633)" do
    test "a Bronze Spearman (16) always lands within its own asymmetric band against a Barbarian Warrior (15)" do
      {lo, hi} = expected_band(16, 15)
      {counter_lo, counter_hi} = expected_band(15, 16)

      spearman = unit(1, type: :bronze_spearman, hp: 120, max_hp: 120)
      barbarian = unit(2, type: :barbarian_warrior, hp: 120, max_hp: 120, player_id: nil)

      for seed <- 1..100 do
        %{damage_to_defender: dealt, damage_to_attacker: taken} =
          Resolver.resolve(spearman, barbarian, seed: {:bronze_spearman, seed})

        assert dealt in lo..hi
        assert taken in counter_lo..counter_hi
      end
    end

    test "the Bronze Spearman's expected damage output exceeds the Barbarian Warrior's, on average, across a wide sample — the strength edge that lets it win a 1v1" do
      spearman = unit(1, type: :bronze_spearman, hp: 120, max_hp: 120)
      barbarian = unit(2, type: :barbarian_warrior, hp: 120, max_hp: 120, player_id: nil)

      {dealt_total, taken_total} =
        Enum.reduce(1..200, {0, 0}, fn seed, {dealt_acc, taken_acc} ->
          %{damage_to_defender: dealt, damage_to_attacker: taken} =
            Resolver.resolve(spearman, barbarian, seed: {:bronze_spearman_avg, seed})

          {dealt_acc + dealt, taken_acc + taken}
        end)

      assert dealt_total > taken_total
    end
  end

  describe "resolve/3 — Archer vs Barbarian Warrior (QA issue da39e50b, melee-for-now)" do
    test "an Archer (14) always lands within its own asymmetric band against a Barbarian Warrior (15)" do
      {lo, hi} = expected_band(14, 15)
      {counter_lo, counter_hi} = expected_band(15, 14)

      archer = unit(1, type: :archer, hp: 100, max_hp: 100)
      barbarian = unit(2, type: :barbarian_warrior, hp: 120, max_hp: 120, player_id: nil)

      for seed <- 1..100 do
        %{damage_to_defender: dealt, damage_to_attacker: taken} =
          Resolver.resolve(archer, barbarian, seed: {:archer, seed})

        assert dealt in lo..hi
        assert taken in counter_lo..counter_hi
      end
    end

    test "an Archer trades blows on an even adjacency exchange — genuinely melee, not ranged (both sides land a hit)" do
      archer = unit(1, type: :archer, hp: 100, max_hp: 100)
      warrior = unit(2, type: :warrior, hp: 100, max_hp: 100, player_id: 2)

      %{damage_to_defender: dealt, damage_to_attacker: taken} =
        Resolver.resolve(archer, warrior, seed: {:archer_melee, 1})

      assert dealt > 0
      assert taken > 0
    end
  end

  describe "camp_damage/2" do
    test "a strength-10 Warrior deals 10 flat damage, no roll" do
      assert Resolver.camp_damage(unit(1, type: :warrior, hp: 100, max_hp: 100)) == 10
    end

    test "a strength-12 Lord deals 12 flat damage" do
      assert Resolver.camp_damage(unit(1, type: :lord, hp: 150, max_hp: 150)) == 12
    end

    test "a wounded attacker deals proportionally less camp damage" do
      wounded = unit(1, type: :warrior, hp: 20, max_hp: 100)
      assert Resolver.camp_damage(wounded) == 6
    end

    test "the lord's aura raises camp damage the same way it raises combat strength" do
      assert Resolver.camp_damage(unit(1, type: :warrior, hp: 100, max_hp: 100), true) == 12
    end
  end

  describe "hostile?/2" do
    test "a unit with a real owning player is never a legal target — no Stone Age PvP" do
      attacker = unit(1, player_id: 1)
      other_player = unit(2, player_id: 2)
      refute Resolver.hostile?(attacker, other_player)
    end

    test "a unit's own side is never hostile to itself" do
      attacker = unit(1, player_id: 1)
      same_player = unit(2, player_id: 1)
      refute Resolver.hostile?(attacker, same_player)
    end

    test "a nil-owned unit is the barbarian seam — hostile" do
      attacker = unit(1, player_id: 1)
      barbarian = unit(2, player_id: nil)
      assert Resolver.hostile?(attacker, barbarian)
    end
  end

  describe "validate_attack/3" do
    test "refuses an attacker with no movement left" do
      a = unit(1, movement: 0, tile_id: 1)
      d = unit(2, tile_id: 2, player_id: nil)

      assert Resolver.validate_attack(a, d, [2]) == {:error, :out_of_movement}
    end

    test "refuses a defender on a non-adjacent tile" do
      a = unit(1, tile_id: 1)
      d = unit(2, tile_id: 99, player_id: nil)

      assert Resolver.validate_attack(a, d, [2, 3, 4]) == {:error, :not_adjacent}
    end

    test "refuses an adjacent, in-movement attack on a real player's unit" do
      a = unit(1, tile_id: 1, player_id: 1)
      d = unit(2, tile_id: 2, player_id: 2)

      assert Resolver.validate_attack(a, d, [2]) == {:error, :not_hostile}
    end

    test "allows an adjacent, in-movement attack on a hostile (nil-owned) unit" do
      a = unit(1, tile_id: 1, player_id: 1)
      d = unit(2, tile_id: 2, player_id: nil)

      assert Resolver.validate_attack(a, d, [2]) == :ok
    end
  end
end
