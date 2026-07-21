defmodule BrokenOaths.Technology.ResearchTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Technology.Research

  @all_techs [
    :pottery,
    :animal_husbandry,
    :mining,
    :sailing,
    :astrology,
    :writing,
    :irrigation,
    :archery,
    :masonry,
    :the_wheel,
    :bronze_working
  ]

  describe "techs/0 and catalog/0" do
    test "the eleven Ancient-era techs, at their rebalanced PM costs (QA issue d95ea179)" do
      assert Enum.sort(Research.techs()) == Enum.sort(@all_techs)

      assert Research.cost(:pottery) == 80
      assert Research.cost(:animal_husbandry) == 80
      assert Research.cost(:mining) == 110
      assert Research.cost(:sailing) == 150
      assert Research.cost(:astrology) == 150
      assert Research.cost(:writing) == 150
      assert Research.cost(:irrigation) == 150
      assert Research.cost(:archery) == 150
      assert Research.cost(:masonry) == 240
      assert Research.cost(:the_wheel) == 240
      assert Research.cost(:bronze_working) == 240
    end

    test "catalog/0 carries every tech's cost, unlock description, and prerequisites" do
      catalog = Research.catalog()
      assert catalog[:mining].cost == 110
      assert catalog[:mining].unlock =~ "mines"
      assert catalog[:mining].prereqs == []
      assert catalog[:bronze_working].prereqs == [:mining]
    end
  end

  describe "prereqs/1 — the Civ-6-accurate prerequisite edges" do
    test "tier-1 techs have no prerequisite" do
      for tech <- [:pottery, :animal_husbandry, :mining, :sailing, :astrology] do
        assert Research.prereqs(tech) == []
      end
    end

    test "Writing and Irrigation require Pottery" do
      assert Research.prereqs(:writing) == [:pottery]
      assert Research.prereqs(:irrigation) == [:pottery]
    end

    test "Archery requires Animal Husbandry" do
      assert Research.prereqs(:archery) == [:animal_husbandry]
    end

    test "Masonry, The Wheel, and Bronze Working all require Mining" do
      assert Research.prereqs(:masonry) == [:mining]
      assert Research.prereqs(:the_wheel) == [:mining]
      assert Research.prereqs(:bronze_working) == [:mining]
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

  describe "prereqs_met?/2" do
    test "always true for a tier-1 tech" do
      assert Research.prereqs_met?(Research.new(), :pottery)
      assert Research.prereqs_met?(Research.new(), :mining)
    end

    test "false for a tier-2 tech before its prerequisite is completed" do
      refute Research.prereqs_met?(Research.new(), :bronze_working)
      refute Research.prereqs_met?(Research.new(), :writing)
      refute Research.prereqs_met?(Research.new(), :archery)
    end

    test "true once the prerequisite is completed" do
      pr = %{Research.new() | completed_techs: [:mining]}
      assert Research.prereqs_met?(pr, :bronze_working)
      assert Research.prereqs_met?(pr, :masonry)
      assert Research.prereqs_met?(pr, :the_wheel)
    end

    test "completing an unrelated tech doesn't satisfy a different prerequisite" do
      pr = %{Research.new() | completed_techs: [:animal_husbandry]}
      refute Research.prereqs_met?(pr, :bronze_working)
      refute Research.prereqs_met?(pr, :writing)
      assert Research.prereqs_met?(pr, :archery)
    end
  end

  describe "tech_state/2" do
    test ":locked when a prerequisite is outstanding" do
      assert Research.tech_state(Research.new(), :bronze_working) == :locked
    end

    test ":available when prereq-free or prerequisites are all met" do
      assert Research.tech_state(Research.new(), :pottery) == :available

      pr = %{Research.new() | completed_techs: [:mining]}
      assert Research.tech_state(pr, :bronze_working) == :available
    end

    test ":in_progress when it's the current_research" do
      pr = %{Research.new() | current_research: :pottery}
      assert Research.tech_state(pr, :pottery) == :in_progress
    end

    test ":completed once it's in completed_techs, even if it was current_research" do
      pr = %{Research.new() | completed_techs: [:pottery]}
      assert Research.tech_state(pr, :pottery) == :completed
    end
  end

  describe "set_research/2" do
    test "selects a tech as current_research" do
      assert {:ok, pr} = Research.set_research(Research.new(), :pottery)
      assert pr.current_research == :pottery
    end

    test "refuses an unknown tech" do
      assert Research.set_research(Research.new(), :astronomy) == {:error, :invalid_tech}
    end

    test "refuses a tech that's already completed" do
      pr = %{Research.new() | completed_techs: [:pottery]}
      assert Research.set_research(pr, :pottery) == {:error, :already_completed}
    end

    test "refuses a tech whose prerequisite isn't completed yet" do
      assert Research.set_research(Research.new(), :bronze_working) ==
               {:error, :prereqs_not_met}

      assert Research.set_research(Research.new(), :writing) == {:error, :prereqs_not_met}
      assert Research.set_research(Research.new(), :archery) == {:error, :prereqs_not_met}
    end

    test "selects a tier-2 tech once its prerequisite is completed" do
      pr = %{Research.new() | completed_techs: [:mining]}
      assert {:ok, selected} = Research.set_research(pr, :bronze_working)
      assert selected.current_research == :bronze_working
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
      pr = %{Research.new() | current_research: :pottery} |> Research.accrue(79)
      refute Research.ready?(pr)
      assert Research.complete(pr) == {:error, :not_ready}
    end

    test "ready and completes exactly at cost" do
      pr = %{Research.new() | current_research: :pottery} |> Research.accrue(80)
      assert Research.ready?(pr)

      assert {:ok, completed} = Research.complete(pr)
      assert completed.current_research == nil
      assert :pottery in completed.completed_techs
    end

    test "completes with overflow banked past cost" do
      pr = %{Research.new() | current_research: :mining} |> Research.accrue(130)
      assert {:ok, completed} = Research.complete(pr)
      assert :mining in completed.completed_techs
    end

    test "refuses to complete with nothing selected" do
      assert Research.complete(Research.new()) == {:error, :no_current_research}
    end
  end

  describe "accrue_and_complete/2 — the per-turn entry point" do
    test "banks and auto-completes when the cost is reached, reporting the completed tech" do
      pr = %{Research.new() | current_research: :pottery} |> Research.accrue(78)

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
      assert Research.progress(pr) == %{tech: :bronze_working, banked: 40, cost: 240}
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

    # Story 921 — Sailing's own unlock, finally wired (see this
    # module's own moduledoc, "Unlocks").
    test "sailing_enabled?/1 flips on Sailing (the Galley's own gate)" do
      refute Research.sailing_enabled?(Research.new())
      pr = %{Research.new() | completed_techs: [:sailing]}
      assert Research.sailing_enabled?(pr)
    end

    test "age/1 flips to :bronze_age on Bronze Working, otherwise :stone_age" do
      assert Research.age(Research.new()) == :stone_age
      pr = %{Research.new() | completed_techs: [:bronze_working]}
      assert Research.age(pr) == :bronze_age
    end

    test "other completed techs never flip the age" do
      pr = %{
        Research.new()
        | completed_techs: [:animal_husbandry, :pottery, :mining, :sailing, :astrology]
      }

      assert Research.age(pr) == :stone_age
    end
  end

  describe "end-to-end: research every tech in sequence, one at a time, respecting prerequisites" do
    test "banking, completing, and switching compose across the whole eleven-tech tree" do
      pr = Research.new()

      {:ok, pr} = Research.set_research(pr, :animal_husbandry)
      {pr, completed} = Research.accrue_and_complete(pr, 80)
      assert completed == :animal_husbandry

      {:ok, pr} = Research.set_research(pr, :pottery)
      {pr, nil} = Research.accrue_and_complete(pr, 50)
      {pr, completed} = Research.accrue_and_complete(pr, 30)
      assert completed == :pottery

      {:ok, pr} = Research.set_research(pr, :mining)
      {pr, completed} = Research.accrue_and_complete(pr, 110)
      assert completed == :mining

      # Only reachable now that Pottery/Animal Husbandry/Mining are done.
      {:ok, pr} = Research.set_research(pr, :archery)
      {pr, completed} = Research.accrue_and_complete(pr, 150)
      assert completed == :archery

      {:ok, pr} = Research.set_research(pr, :writing)
      {pr, completed} = Research.accrue_and_complete(pr, 150)
      assert completed == :writing

      {:ok, pr} = Research.set_research(pr, :bronze_working)
      {pr, completed} = Research.accrue_and_complete(pr, 240)
      assert completed == :bronze_working

      assert Enum.sort(pr.completed_techs) ==
               Enum.sort([
                 :animal_husbandry,
                 :pottery,
                 :mining,
                 :archery,
                 :writing,
                 :bronze_working
               ])

      assert Research.age(pr) == :bronze_age
      assert {:error, :already_completed} = Research.set_research(pr, :mining)
    end
  end
end
