defmodule BrokenOaths.Feudal.StewardshipTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Feudal.Stewardship

  describe "steward_role/4" do
    test "the owner's own lord resolves to :lord" do
      assert Stewardship.steward_role(1, 1, nil, false) == :lord
    end

    test "a fellow vassal sworn to the same lord resolves to :fellow_vassal" do
      assert Stewardship.steward_role(1, 2, 1, false) == :fellow_vassal
    end

    test "an accepted ally resolves to :ally regardless of vassalage" do
      assert Stewardship.steward_role(nil, 2, nil, true) == :ally
      assert Stewardship.steward_role(1, 3, 9, true) == :ally
    end

    test "a stranger with none of the three relationships resolves to :none" do
      assert Stewardship.steward_role(nil, 2, nil, false) == :none
      assert Stewardship.steward_role(1, 2, 9, false) == :none
    end

    test "a vassal can never steward their own lord — the lord clause never matches in reverse" do
      # owner (the lord) has no lord of their own (owner_lord_id: nil);
      # the vassal (steward_player_id: 2, steward_lord_id: 1) has no
      # relationship that resolves to :lord here — it falls all the way
      # through to :none.
      assert Stewardship.steward_role(nil, 2, 1, false) == :none
    end
  end

  describe "eligible?/1" do
    test "every role except :none is eligible" do
      assert Stewardship.eligible?(:lord)
      assert Stewardship.eligible?(:fellow_vassal)
      assert Stewardship.eligible?(:ally)
      refute Stewardship.eligible?(:none)
    end
  end

  describe "constructive_item?/1" do
    test "every buildable item in the current catalog is constructive" do
      for type <- [:settler, :worker, :warrior, :granary, :bronze_spearman] do
        assert Stewardship.constructive_item?(type)
      end
    end

    test "an unknown item is never constructive" do
      refute Stewardship.constructive_item?(:catapult)
    end
  end

  describe "under_attack?/1" do
    test "false when every unit sits at full HP" do
      units = [%{hp: 150, max_hp: 150}, %{hp: 100, max_hp: 100}]
      refute Stewardship.under_attack?(units)
    end

    test "true the instant any one unit carries live damage" do
      units = [%{hp: 150, max_hp: 150}, %{hp: 40, max_hp: 100}]
      assert Stewardship.under_attack?(units)
    end

    test "false for an empty roster" do
      refute Stewardship.under_attack?([])
    end
  end

  describe "defend_target_allowed?/3" do
    test "an adjacent tile is allowed" do
      assert Stewardship.defend_target_allowed?(10, 11, [11, 12, 13])
    end

    test "a tile that isn't adjacent is refused — marching the army off" do
      refute Stewardship.defend_target_allowed?(10, 99, [11, 12, 13])
    end

    test "the unit's own current tile is refused — not a real move" do
      refute Stewardship.defend_target_allowed?(10, 10, [10, 11, 12])
    end
  end

  describe "sabotage_honor_penalty/0 and apply_sabotage_penalty/1" do
    test "the penalty is a fixed, positive figure" do
      assert Stewardship.sabotage_honor_penalty() > 0
    end

    test "applying it lowers Honor by exactly that figure" do
      assert Stewardship.apply_sabotage_penalty(100) == 100 - Stewardship.sabotage_honor_penalty()
    end
  end

  describe "log_attrs/7" do
    test "builds the shared attrs shape for a StewardLog insert, sabotage defaulting to false" do
      attrs = Stewardship.log_attrs(1, 10, 20, :bank_collect, %{amount: 5}, 3)

      assert attrs == %{
               world_id: 1,
               steward_player_id: 10,
               owner_player_id: 20,
               action: :bank_collect,
               details: %{amount: 5},
               turn: 3,
               sabotage: false
             }
    end

    test "sabotage can be flagged explicitly" do
      attrs = Stewardship.log_attrs(1, 10, 20, :emergency_defense, %{}, 3, true)
      assert attrs.sabotage == true
    end
  end
end
