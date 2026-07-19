defmodule BrokenOaths.Game.OathStrainTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Game.OathStrain

  # -------------------------------------------------------------------
  # clamp/1 — the single choke point every driver's output passes through
  # -------------------------------------------------------------------

  describe "clamp/1" do
    test "passes an in-range value through untouched" do
      assert OathStrain.clamp(42) == 42
      assert OathStrain.clamp(0) == 0
      assert OathStrain.clamp(100) == 100
    end

    test "floors a negative value at 0" do
      assert OathStrain.clamp(-1) == 0
      assert OathStrain.clamp(-1000) == 0
    end

    test "ceilings an over-100 value at 100" do
      assert OathStrain.clamp(101) == 100
      assert OathStrain.clamp(1_000_000) == 100
    end
  end

  # -------------------------------------------------------------------
  # tribute_drift/2 — RAISER (high rate) and EASER (low rate) in one
  # -------------------------------------------------------------------

  describe "tribute_drift/2" do
    test "the default 25% rate contributes zero drift — no lever touched, no movement" do
      assert OathStrain.tribute_drift(50, OathStrain.default_tribute_rate()) == 50
      assert OathStrain.tribute_drift(0, OathStrain.default_tribute_rate()) == 0
      assert OathStrain.tribute_drift(100, OathStrain.default_tribute_rate()) == 100
    end

    test "a rate above the default drifts strain upward" do
      assert OathStrain.tribute_drift(30, 0.5) > 30
    end

    test "a rate below the default drifts strain downward" do
      assert OathStrain.tribute_drift(50, 0.1) < 50
    end

    test "a single call never moves strain by more than max_drift_step/0, even at the extremes" do
      up_delta = OathStrain.tribute_drift(50, 1.0) - 50
      down_delta = 50 - OathStrain.tribute_drift(50, 0.0)

      assert up_delta <= OathStrain.max_drift_step()
      assert down_delta <= OathStrain.max_drift_step()
    end

    test "repeated calls accumulate the drift over many turns without ever spiking" do
      raised =
        Enum.reduce(1..40, 30, fn _turn, strain -> OathStrain.tribute_drift(strain, 0.5) end)

      assert raised > 30
    end

    test "clamps at the 100 ceiling under sustained upward drift" do
      raised =
        Enum.reduce(1..200, 90, fn _turn, strain -> OathStrain.tribute_drift(strain, 1.0) end)

      assert raised == 100
    end

    test "clamps at the 0 floor under sustained downward drift" do
      eased = Enum.reduce(1..200, 10, fn _turn, strain -> OathStrain.tribute_drift(strain, 0.0) end)
      assert eased == 0
    end

    test "raises (crashes the process) for an out-of-domain strain" do
      assert_raise FunctionClauseError, fn -> OathStrain.tribute_drift(101, 0.5) end
      assert_raise FunctionClauseError, fn -> OathStrain.tribute_drift(-1, 0.5) end
    end

    test "raises (crashes the process) for an out-of-domain rate" do
      assert_raise FunctionClauseError, fn -> OathStrain.tribute_drift(50, 1.5) end
      assert_raise FunctionClauseError, fn -> OathStrain.tribute_drift(50, -0.1) end
    end
  end

  # -------------------------------------------------------------------
  # spike_broken_protection_pact/1 — the large, one-time RAISER
  # -------------------------------------------------------------------

  describe "spike_broken_protection_pact/1" do
    test "raises strain by exactly protection_pact_spike/0" do
      assert OathStrain.spike_broken_protection_pact(45) ==
               45 + OathStrain.protection_pact_spike()
    end

    test "clamps at 100" do
      assert OathStrain.spike_broken_protection_pact(90) == 100
    end

    test "spikes harder than a refused levy does — the locked relationship" do
      assert OathStrain.protection_pact_spike() > OathStrain.refused_levy_spike()
    end

    test "raises for an out-of-domain strain" do
      assert_raise FunctionClauseError, fn -> OathStrain.spike_broken_protection_pact(101) end
    end
  end

  # -------------------------------------------------------------------
  # spike_refused_levy/1 — the moderate, one-time RAISER
  # -------------------------------------------------------------------

  describe "spike_refused_levy/1" do
    test "raises strain by exactly refused_levy_spike/0 (15, matching Tribute's own real spike)" do
      assert OathStrain.refused_levy_spike() == 15
      assert OathStrain.spike_refused_levy(0) == 15
    end

    test "clamps at 100 across repeated refusals" do
      spiked = Enum.reduce(1..7, 0, fn _refusal, strain -> OathStrain.spike_refused_levy(strain) end)
      assert spiked == 100
    end

    test "raises for an out-of-domain strain" do
      assert_raise FunctionClauseError, fn -> OathStrain.spike_refused_levy(-1) end
    end
  end

  # -------------------------------------------------------------------
  # EASERS — ease_gift/1, ease_autonomy/1, ease_shared_enemy/1
  # -------------------------------------------------------------------

  describe "ease_gift/1" do
    test "eases strain downward by exactly gift_ease/0" do
      assert OathStrain.ease_gift(50) == 50 - OathStrain.gift_ease()
    end

    test "clamps at the 0 floor" do
      assert OathStrain.ease_gift(5) == 0
    end
  end

  describe "ease_autonomy/1" do
    test "eases strain downward by exactly autonomy_ease/0" do
      assert OathStrain.ease_autonomy(50) == 50 - OathStrain.autonomy_ease()
    end

    test "clamps at the 0 floor" do
      assert OathStrain.ease_autonomy(5) == 0
    end
  end

  describe "ease_shared_enemy/1" do
    test "eases strain downward by exactly shared_enemy_ease/0" do
      assert OathStrain.ease_shared_enemy(50) == 50 - OathStrain.shared_enemy_ease()
    end

    test "clamps at the 0 floor" do
      assert OathStrain.ease_shared_enemy(5) == 0
    end
  end

  describe "combined concessions ease strain further than any single one alone" do
    test "a lowered rate, a gift, and a shared enemy each push strain lower in turn" do
      after_rate_drop = OathStrain.tribute_drift(75, 0.2)
      after_gift = OathStrain.ease_gift(after_rate_drop)
      after_shared_enemy = OathStrain.ease_shared_enemy(after_gift)

      assert after_rate_drop <= 75
      assert after_gift < after_rate_drop
      assert after_shared_enemy < after_gift
    end
  end

  # -------------------------------------------------------------------
  # rebellion_army_size/1 — the strain -> army-size curve (story 915)
  # -------------------------------------------------------------------

  describe "rebellion_army_size/1" do
    test "a zero-grievance vassal still raises a token force — declaring is always available" do
      assert OathStrain.rebellion_army_size(0) == 1
    end

    test "max grievance raises the biggest uprising" do
      assert OathStrain.rebellion_army_size(100) == 11
    end

    test "monotonic non-decreasing across the entire 0..100 domain" do
      sizes = for strain <- 0..100, do: OathStrain.rebellion_army_size(strain)
      assert sizes == Enum.sort(sizes)
    end

    test "every size stays within sane bounds" do
      for strain <- 0..100 do
        size = OathStrain.rebellion_army_size(strain)
        assert size >= 1
        assert size <= 11
      end
    end

    test "raises for an out-of-domain strain" do
      assert_raise FunctionClauseError, fn -> OathStrain.rebellion_army_size(101) end
      assert_raise FunctionClauseError, fn -> OathStrain.rebellion_army_size(-1) end
    end
  end
end
