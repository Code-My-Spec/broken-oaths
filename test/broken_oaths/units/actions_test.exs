defmodule BrokenOaths.Units.ActionsTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Units.Actions

  describe "available/1" do
    test "nil (nothing selected) carries no actions at all" do
      assert Actions.available(nil) == []
    end

    test "a settler can move, found a city, and defend" do
      assert Actions.available(%{type: :settler}) == [:move, :found_city, :defend]
    end

    test "a worker can move, build improvements, and defend — no :attack, no :found_city" do
      actions = Actions.available(%{type: :worker})

      assert :move in actions
      assert :build_improvement in actions
      assert :defend in actions
      refute :attack in actions
      refute :found_city in actions
      refute :shoot in actions
    end

    # QA issue 12bed1e4 — the Archer's own new action, alongside the
    # melee :attack the first pass (QA issue da39e50b) already gave it.
    test "an archer keeps :attack AND gains :shoot" do
      actions = Actions.available(%{type: :archer})

      assert :move in actions
      assert :attack in actions
      assert :shoot in actions
      assert :defend in actions
    end

    test "a warrior can move, attack, and defend — no :shoot" do
      actions = Actions.available(%{type: :warrior})

      assert :move in actions
      assert :attack in actions
      assert :defend in actions
      refute :shoot in actions
    end

    test "the lord carries the same melee action set as any other military type" do
      assert Actions.available(%{type: :lord}) == [:move, :attack, :defend]
    end

    test "the bronze spearman carries the same melee action set too" do
      assert Actions.available(%{type: :bronze_spearman}) == [:move, :attack, :defend]
    end

    test "a barbarian warrior can move and attack, but never :defend (never player-commanded)" do
      assert Actions.available(%{type: :barbarian_warrior}) == [:move, :attack]
    end

    test "an unrecognized future type degrades to :move only, never crashes" do
      assert Actions.available(%{type: :catapult}) == [:move]
    end

    test "extra keys on the unit map are ignored — only :type is consulted" do
      unit = %{type: :archer, id: 42, hp: 10, tile_id: 5}
      assert Actions.available(unit) == Actions.available(%{type: :archer})
    end
  end
end
