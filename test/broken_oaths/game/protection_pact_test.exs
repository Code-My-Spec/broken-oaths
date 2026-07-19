defmodule BrokenOaths.Game.ProtectionPactTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Game.OathStrain
  alias BrokenOaths.Game.ProtectionPact

  # -------------------------------------------------------------------
  # raise_call/3 — the trigger (criterion 7726)
  # -------------------------------------------------------------------

  describe "raise_call/3" do
    test "captures the relationship, the raised turn, and a deadline current + response_window/0" do
      call = ProtectionPact.raise_call(:mira, :wes, 10)

      assert call.lord_player_id == :mira
      assert call.vassal_player_id == :wes
      assert call.raised_turn == 10
      assert call.deadline_turn == 10 + ProtectionPact.response_window()
      assert call.window_remaining == ProtectionPact.response_window()
      assert call.status == :pending
    end

    test "response_window/0 defaults to 3 turns" do
      assert ProtectionPact.response_window() == 3
    end

    test "raises for a negative turn" do
      assert_raise FunctionClauseError, fn -> ProtectionPact.raise_call(:mira, :wes, -1) end
    end
  end

  # -------------------------------------------------------------------
  # tick/1 — the countdown (criterion 7727)
  # -------------------------------------------------------------------

  describe "tick/1" do
    test "decrements window_remaining by exactly one" do
      call = ProtectionPact.raise_call(:mira, :wes, 0)
      ticked = ProtectionPact.tick(call)

      assert ticked.window_remaining == call.window_remaining - 1
    end

    test "floors at zero rather than going negative" do
      call = %{ProtectionPact.raise_call(:mira, :wes, 0) | window_remaining: 0}
      ticked = ProtectionPact.tick(call)

      assert ticked.window_remaining == 0
    end

    test "repeated ticks count all the way down to zero and stay there" do
      final =
        :mira
        |> ProtectionPact.raise_call(:wes, 0)
        |> then(fn call ->
          Enum.reduce(1..10, call, fn _turn, acc -> ProtectionPact.tick(acc) end)
        end)

      assert final.window_remaining == 0
    end

    test "ticking an already-resolved call crashes — a caller bug, not valid state" do
      call = ProtectionPact.raise_call(:mira, :wes, 0)
      {resolved, _strain, _honor} = ProtectionPact.score_honored(call, 40, 100)

      # `apply/3` keeps this call dynamically dispatched — the resolved
      # call's own `:honored` status is a genuinely invalid `tick/1`
      # argument, which the compiler's own type checker would otherwise
      # (correctly) flag as statically unreachable code.
      assert_raise FunctionClauseError, fn -> apply(ProtectionPact, :tick, [resolved]) end
    end
  end

  # -------------------------------------------------------------------
  # expired?/1
  # -------------------------------------------------------------------

  describe "expired?/1" do
    test "false while the window still has turns remaining" do
      call = ProtectionPact.raise_call(:mira, :wes, 0)
      refute ProtectionPact.expired?(call)
    end

    test "true once the window has fully counted down" do
      final =
        :mira
        |> ProtectionPact.raise_call(:wes, 0)
        |> then(fn call ->
          Enum.reduce(1..ProtectionPact.response_window(), call, fn _turn, acc ->
            ProtectionPact.tick(acc)
          end)
        end)

      assert ProtectionPact.expired?(final)
    end
  end

  # -------------------------------------------------------------------
  # score_honored/3 — criterion 7728
  # -------------------------------------------------------------------

  describe "score_honored/3" do
    test "eases the vassal's strain via OathStrain.ease_shared_enemy/1 exactly" do
      call = ProtectionPact.raise_call(:mira, :wes, 0)
      {_call, strain_after, _honor_after} = ProtectionPact.score_honored(call, 45, 100)

      assert strain_after == OathStrain.ease_shared_enemy(45)
      assert strain_after < 45
    end

    test "raises the lord's Honor by exactly honored_honor_gain/0" do
      call = ProtectionPact.raise_call(:mira, :wes, 0)
      {_call, _strain_after, honor_after} = ProtectionPact.score_honored(call, 45, 100)

      assert honor_after == 100 + ProtectionPact.honored_honor_gain()
      assert honor_after > 100
    end

    test "resolves the call as :honored" do
      call = ProtectionPact.raise_call(:mira, :wes, 0)
      {resolved, _strain, _honor} = ProtectionPact.score_honored(call, 45, 100)

      assert resolved.status == :honored
    end

    test "scoring an already-resolved call crashes" do
      call = ProtectionPact.raise_call(:mira, :wes, 0)
      {resolved, _strain, _honor} = ProtectionPact.score_honored(call, 45, 100)

      assert_raise FunctionClauseError, fn ->
        apply(ProtectionPact, :score_honored, [resolved, 45, 100])
      end
    end

    test "raises for an out-of-domain strain — OathStrain's own guard propagates" do
      call = ProtectionPact.raise_call(:mira, :wes, 0)
      assert_raise FunctionClauseError, fn -> ProtectionPact.score_honored(call, 101, 100) end
    end

    test "repeated honored calls make vassalage a net-positive (criterion 7730)" do
      # Wes has already refused one call to arms — a real, positive
      # strain baseline unrelated to protection.
      strain_baseline = OathStrain.spike_refused_levy(0)
      assert strain_baseline > 0

      strain_final =
        Enum.reduce(1..3, strain_baseline, fn _siege, strain ->
          call = ProtectionPact.raise_call(:mira, :wes, 0)
          {_resolved, strain_after, _honor} = ProtectionPact.score_honored(call, strain, 100)
          strain_after
        end)

      assert strain_final < strain_baseline
    end
  end

  # -------------------------------------------------------------------
  # score_broken/3 — criterion 7729
  # -------------------------------------------------------------------

  describe "score_broken/3" do
    test "spikes the direct victim's strain via OathStrain.spike_broken_protection_pact/1 exactly" do
      call = ProtectionPact.raise_call(:mira, :wes, 0)
      {_call, strain_after, _honor_after} = ProtectionPact.score_broken(call, 45, 100)

      assert strain_after == OathStrain.spike_broken_protection_pact(45)
      assert strain_after > 45
    end

    test "docks the lord's Honor by exactly broken_honor_penalty/0, unclamped" do
      call = ProtectionPact.raise_call(:mira, :wes, 0)
      {_call, _strain_after, honor_after} = ProtectionPact.score_broken(call, 45, 100)

      assert honor_after == 100 - ProtectionPact.broken_honor_penalty()
      assert honor_after < 100
    end

    test "Honor is never clamped at zero — a broken pact can still push it negative" do
      call = ProtectionPact.raise_call(:mira, :wes, 0)
      {_call, _strain, honor_after} = ProtectionPact.score_broken(call, 45, 2)

      assert honor_after == 2 - ProtectionPact.broken_honor_penalty()
      assert honor_after < 0
    end

    test "resolves the call as :broken" do
      call = ProtectionPact.raise_call(:mira, :wes, 0)
      {resolved, _strain, _honor} = ProtectionPact.score_broken(call, 45, 100)

      assert resolved.status == :broken
    end

    test "scoring an already-resolved call crashes" do
      call = ProtectionPact.raise_call(:mira, :wes, 0)
      {resolved, _strain, _honor} = ProtectionPact.score_broken(call, 45, 100)

      assert_raise FunctionClauseError, fn ->
        apply(ProtectionPact, :score_broken, [resolved, 45, 100])
      end
    end
  end

  # -------------------------------------------------------------------
  # spike_contagion/1 — the realm-wide bystander spike
  # -------------------------------------------------------------------

  describe "spike_contagion/1" do
    test "raises strain by exactly contagion_spike/0" do
      assert ProtectionPact.spike_contagion(20) == 20 + ProtectionPact.contagion_spike()
    end

    test "clamps at 100" do
      assert ProtectionPact.spike_contagion(95) == 100
    end
  end

  # -------------------------------------------------------------------
  # Direct-victim spike > contagion spike — the locked relationship
  # (criterion 7729: "Ada and Bo each take a smaller ... spike than
  # Wes's own")
  # -------------------------------------------------------------------

  describe "direct-victim spike always exceeds the contagion spike" do
    test "the constants themselves are ordered" do
      assert OathStrain.protection_pact_spike() > ProtectionPact.contagion_spike()
    end

    test "the actual deltas from a shared starting strain are ordered the same way" do
      call = ProtectionPact.raise_call(:mira, :wes, 0)
      starting_strain = 20

      {_call, victim_strain_after, _honor} =
        ProtectionPact.score_broken(call, starting_strain, 100)

      bystander_strain_after = ProtectionPact.spike_contagion(starting_strain)

      victim_delta = victim_strain_after - starting_strain
      bystander_delta = bystander_strain_after - starting_strain

      assert victim_delta > bystander_delta
    end
  end

  # -------------------------------------------------------------------
  # broken_honor_penalty/0 > honored_honor_gain/0 — losing Honor this
  # way should hurt more than honoring it helps (the "Honor brake")
  # -------------------------------------------------------------------

  describe "Honor magnitudes are asymmetric by design" do
    test "the penalty for breaking a call exceeds the reward for honoring one" do
      assert ProtectionPact.broken_honor_penalty() > ProtectionPact.honored_honor_gain()
    end
  end
end
