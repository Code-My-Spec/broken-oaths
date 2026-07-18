defmodule BrokenOaths.Game.ResearchTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Game.Research

  describe "techs/0 and catalog/0" do
    test "the four Stone Age techs, at their locked PM costs" do
      assert Enum.sort(Research.techs()) ==
               Enum.sort([:animal_husbandry, :pottery, :mining, :bronze_working])

      assert Research.cost(:animal_husbandry) == 50
      assert Research.cost(:pottery) == 50
      assert Research.cost(:mining) == 75
      assert Research.cost(:bronze_working) == 100
    end

    test "catalog/0 carries every tech's cost and unlock description" do
      catalog = Research.catalog()
      assert catalog[:mining].cost == 75
      assert catalog[:mining].unlock =~ "mines"
    end
  end

  describe "new/0" do
    test "a fresh player has nothing completed, selected, or banked" do
      assert Research.new() == %{completed_techs: [], current_research: nil, banked_science: %{}}
    end
  end

  describe "science_per_turn/1 — science by population" do
    test "2 science per population point, summed across cities" do
      assert Research.science_per_turn([%{size: 1}]) == 2
      assert Research.science_per_turn([%{size: 4}]) == 8
      assert Research.science_per_turn([%{size: 2}, %{size: 3}]) == 10
    end

    test "no cities yields zero science" do
      assert Research.science_per_turn([]) == 0
    end
  end

  describe "set_research/2" do
    test "selects a tech as current_research" do
      assert {:ok, pr} = Research.set_research(Research.new(), :pottery)
      assert pr.current_research == :pottery
    end

    test "refuses an unknown tech" do
      assert Research.set_research(Research.new(), :writing) == {:error, :invalid_tech}
    end

    test "refuses a tech that's already completed" do
      pr = %{Research.new() | completed_techs: [:pottery]}
      assert Research.set_research(pr, :pottery) == {:error, :already_completed}
    end

    test "switching research retains banked progress on every tech (per-tech retention)" do
      pr = %{Research.new() | current_research: :pottery}
      pr = Research.accrue(pr, 20)

      assert {:ok, switched} = Research.set_research(pr, :mining)
      assert switched.current_research == :mining
      assert Research.banked(switched, :pottery) == 20
      assert Research.banked(switched, :mining) == 0

      switched = Research.accrue(switched, 10)
      assert {:ok, back} = Research.set_research(switched, :pottery)
      assert Research.banked(back, :pottery) == 20
      assert Research.banked(back, :mining) == 10
    end
  end

  describe "accrue/2 — one tech at a time" do
    test "banks income toward current_research only" do
      pr = %{Research.new() | current_research: :mining}
      pr = Research.accrue(pr, 30)
      assert Research.banked(pr, :mining) == 30
      assert Research.banked(pr, :pottery) == 0
    end

    test "accumulates across multiple turns" do
      pr = %{Research.new() | current_research: :mining}
      pr = pr |> Research.accrue(30) |> Research.accrue(20)
      assert Research.banked(pr, :mining) == 50
    end

    test "a no-op with nothing selected" do
      assert Research.accrue(Research.new(), 30) == Research.new()
    end
  end

  describe "ready?/1 and complete/1" do
    test "not ready below cost" do
      pr = %{Research.new() | current_research: :pottery} |> Research.accrue(49)
      refute Research.ready?(pr)
      assert Research.complete(pr) == {:error, :not_ready}
    end

    test "ready and completes exactly at cost" do
      pr = %{Research.new() | current_research: :pottery} |> Research.accrue(50)
      assert Research.ready?(pr)

      assert {:ok, completed} = Research.complete(pr)
      assert completed.current_research == nil
      assert :pottery in completed.completed_techs
    end

    test "completes with overflow banked past cost" do
      pr = %{Research.new() | current_research: :mining} |> Research.accrue(90)
      assert {:ok, completed} = Research.complete(pr)
      assert :mining in completed.completed_techs
    end

    test "refuses to complete with nothing selected" do
      assert Research.complete(Research.new()) == {:error, :no_current_research}
    end
  end

  describe "accrue_and_complete/2 — the per-turn entry point" do
    test "banks and auto-completes when the cost is reached, reporting the completed tech" do
      pr = %{Research.new() | current_research: :pottery} |> Research.accrue(48)

      assert {new_pr, :pottery} = Research.accrue_and_complete(pr, 2)
      assert new_pr.current_research == nil
      assert :pottery in new_pr.completed_techs
    end

    test "banks without completing when short of cost" do
      pr = %{Research.new() | current_research: :pottery}
      assert {new_pr, nil} = Research.accrue_and_complete(pr, 10)
      assert Research.banked(new_pr, :pottery) == 10
      assert new_pr.current_research == :pottery
    end

    test "a no-op with nothing selected" do
      assert Research.accrue_and_complete(Research.new(), 10) == {Research.new(), nil}
    end
  end

  describe "progress/1" do
    test "nil with nothing selected" do
      assert Research.progress(Research.new()) == nil
    end

    test "tech/banked/cost for the current research" do
      pr = %{Research.new() | current_research: :bronze_working} |> Research.accrue(40)
      assert Research.progress(pr) == %{tech: :bronze_working, banked: 40, cost: 100}
    end
  end

  describe "unlocks" do
    test "mine_duration/1 is 5 by default, 3 once Mining is completed" do
      assert Research.mine_duration(Research.new()) == 5
      pr = %{Research.new() | completed_techs: [:mining]}
      assert Research.mine_duration(pr) == 3
    end

    test "granary_enabled?/1 flips on Pottery" do
      refute Research.granary_enabled?(Research.new())
      pr = %{Research.new() | completed_techs: [:pottery]}
      assert Research.granary_enabled?(pr)
    end

    test "pasture_enabled?/1 flips on Animal Husbandry (the capability flag story 905 reads)" do
      refute Research.pasture_enabled?(Research.new())
      pr = %{Research.new() | completed_techs: [:animal_husbandry]}
      assert Research.pasture_enabled?(pr)
    end

    test "age/1 flips to :bronze_age on Bronze Working, otherwise :stone_age" do
      assert Research.age(Research.new()) == :stone_age
      pr = %{Research.new() | completed_techs: [:bronze_working]}
      assert Research.age(pr) == :bronze_age
    end

    test "other completed techs never flip the age" do
      pr = %{Research.new() | completed_techs: [:animal_husbandry, :pottery, :mining]}
      assert Research.age(pr) == :stone_age
    end
  end

  describe "end-to-end: research every tech in sequence, one at a time" do
    test "banking, completing, and switching compose across the whole tree" do
      pr = Research.new()

      {:ok, pr} = Research.set_research(pr, :animal_husbandry)
      {pr, completed} = Research.accrue_and_complete(pr, 50)
      assert completed == :animal_husbandry

      {:ok, pr} = Research.set_research(pr, :pottery)
      {pr, nil} = Research.accrue_and_complete(pr, 30)
      {pr, completed} = Research.accrue_and_complete(pr, 20)
      assert completed == :pottery

      {:ok, pr} = Research.set_research(pr, :mining)
      {pr, completed} = Research.accrue_and_complete(pr, 75)
      assert completed == :mining

      {:ok, pr} = Research.set_research(pr, :bronze_working)
      {pr, completed} = Research.accrue_and_complete(pr, 100)
      assert completed == :bronze_working

      assert Enum.sort(pr.completed_techs) ==
               Enum.sort([:animal_husbandry, :pottery, :mining, :bronze_working])

      assert Research.age(pr) == :bronze_age
      assert {:error, :already_completed} = Research.set_research(pr, :mining)
    end
  end
end
