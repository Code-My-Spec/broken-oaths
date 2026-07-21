defmodule BrokenOathsWeb.GameLive.ProgressPanelTest do
  use BrokenOathsTest.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BrokenOathsWeb.GameLive.ProgressPanel

  @no_research %{
    completed_techs: [],
    current_research: nil,
    banked_science: %{},
    science_per_turn: 0
  }

  @base_assigns %{
    id: "progress-panel",
    player_research: @no_research,
    cities_founded: 0,
    camps_destroyed: 0,
    barbarians_killed: 0,
    players_discovered: 0,
    gold_per_turn: %{income: 0, upkeep: 0, net: 0}
  }

  defp render_panel(overrides),
    do: render_component(ProgressPanel, Map.merge(@base_assigns, overrides))

  # Isolates a single `data-test="ID"` `<span>`'s own text out of the
  # full rendered HTML — robust to a trailing attribute after
  # `data-test` (stories 922/923's own `class={...}` on the gold/turn
  # span, split on the FIRST `>` after `data-test="ID"` rather than
  # requiring it to close the tag immediately) and to whatever
  # whitespace HEEx renders around a multi-line interpolation
  # (trimmed), unlike matching a raw substring against the whole
  # document (which risks colliding with an unrelated span that
  # happens to carry the same digit).
  defp span(html, test_id) do
    [_, fragment] = String.split(html, ~s(data-test="#{test_id}"), parts: 2)
    [_, opened] = String.split(fragment, ">", parts: 2)
    [text | _] = String.split(opened, "</span>", parts: 2)
    String.trim(text)
  end

  # Same idea as `span/2`, for a milestone row's own `<div>`.
  defp milestone_row(html, test_id) do
    [_, fragment] = String.split(html, ~s(data-test="#{test_id}"), parts: 2)
    [row | _] = String.split(fragment, "</div>", parts: 2)
    row
  end

  describe "age, science, and Bronze Working progress" do
    test "reads Stone Age with no science income yet" do
      html = render_panel(%{})

      assert html =~ ~s(data-test="progress-panel")
      assert span(html, "progress-age") == "Stone Age"
      assert span(html, "progress-science-per-turn") == "0"
      # Bronze Working costs 240 (QA issue d95ea179 rebalance).
      assert span(html, "progress-bronze-working") == "0 / 240"
    end

    test "shows the projected turns to Bronze Working at the current rate" do
      player_research = %{@no_research | science_per_turn: 4}
      html = render_panel(%{player_research: player_research})

      assert span(html, "progress-science-per-turn") == "4"
      # 240 science cost / 4 per turn == 60, no rounding needed.
      assert span(html, "progress-turns-to-bronze") == "60"
    end

    test "rounds the turns-to-Bronze projection UP to a whole turn" do
      player_research = %{@no_research | science_per_turn: 7}
      html = render_panel(%{player_research: player_research})

      # ceil(240 / 7) == 35, not the truncated 34.
      assert span(html, "progress-turns-to-bronze") == "35"
    end

    test "reflects science already banked toward Bronze Working" do
      player_research = %{
        @no_research
        | science_per_turn: 5,
          banked_science: %{bronze_working: 40}
      }

      html = render_panel(%{player_research: player_research})

      assert span(html, "progress-bronze-working") == "40 / 240"
      # (240 - 40) / 5 == 40
      assert span(html, "progress-turns-to-bronze") == "40"
    end

    test "never crashes with zero science income — renders a placeholder instead" do
      html = render_panel(%{player_research: @no_research})
      assert span(html, "progress-turns-to-bronze") == "—"
    end

    test "shows \"nothing\" with no current research selected" do
      html = render_panel(%{player_research: @no_research})
      assert span(html, "progress-current-research") == "Researching: nothing"
    end

    test "shows the current research, banked/cost, and turns remaining" do
      player_research = %{
        @no_research
        | current_research: :pottery,
          science_per_turn: 8,
          banked_science: %{pottery: 16}
      }

      html = render_panel(%{player_research: player_research})

      # Pottery costs 80 (QA issue d95ea179 rebalance); ceil((80-16)/8) == 8.
      assert span(html, "progress-current-research") ==
               "Researching: Pottery — 16/80 (8 turns)"
    end

    test "shows a placeholder turn count with zero science income" do
      player_research = %{@no_research | current_research: :mining}
      html = render_panel(%{player_research: player_research})

      assert span(html, "progress-current-research") == "Researching: Mining — 0/110 (— turns)"
    end

    test "reads Bronze Age once bronze_working is completed" do
      player_research = %{
        @no_research
        | completed_techs: [:bronze_working],
          science_per_turn: 6,
          banked_science: %{bronze_working: 240}
      }

      html = render_panel(%{player_research: player_research})
      assert span(html, "progress-age") == "Bronze Age"
      # Already complete: no turns remain.
      assert span(html, "progress-turns-to-bronze") == "0"
    end
  end

  describe "career totals" do
    test "shows the running totals it was handed" do
      html = render_panel(%{cities_founded: 3, camps_destroyed: 2, barbarians_killed: 5})

      assert span(html, "progress-cities") == "3"
      assert span(html, "progress-camps") == "2"
      assert span(html, "progress-barbarians") == "5"
    end
  end

  describe "Gold/turn (stories 922/923)" do
    test "a surplus renders signed positive" do
      html = render_panel(%{gold_per_turn: %{income: 5, upkeep: 2, net: 3}})
      assert span(html, "progress-gold-per-turn") == "+3"
    end

    test "a deficit renders signed negative" do
      html = render_panel(%{gold_per_turn: %{income: 1, upkeep: 4, net: -3}})
      assert span(html, "progress-gold-per-turn") == "-3"
    end

    test "no income and no upkeep renders a signed zero, not a bare number" do
      html = render_panel(%{gold_per_turn: %{income: 0, upkeep: 0, net: 0}})
      assert span(html, "progress-gold-per-turn") == "+0"
    end
  end

  describe "milestones" do
    test "every milestone row always renders, unachieved by default" do
      html = render_panel(%{})

      for test_id <-
            ~w(milestone-first-city milestone-first-kill milestone-first-camp milestone-first-discovery) do
        assert html =~ ~s(data-test="#{test_id}")
        refute milestone_row(html, test_id) =~ "Achieved"
      end
    end

    test "first city founded flips independently of the other milestones" do
      html = render_panel(%{cities_founded: 1})

      assert milestone_row(html, "milestone-first-city") =~ "Achieved"
      refute milestone_row(html, "milestone-first-kill") =~ "Achieved"
      refute milestone_row(html, "milestone-first-camp") =~ "Achieved"
      refute milestone_row(html, "milestone-first-discovery") =~ "Achieved"
    end

    test "first barbarian killed flips independently of the other milestones" do
      html = render_panel(%{barbarians_killed: 1})

      assert milestone_row(html, "milestone-first-kill") =~ "Achieved"
      refute milestone_row(html, "milestone-first-city") =~ "Achieved"
      refute milestone_row(html, "milestone-first-camp") =~ "Achieved"
      refute milestone_row(html, "milestone-first-discovery") =~ "Achieved"
    end

    test "first camp destroyed flips independently of the other milestones" do
      html = render_panel(%{camps_destroyed: 1})

      assert milestone_row(html, "milestone-first-camp") =~ "Achieved"
      refute milestone_row(html, "milestone-first-city") =~ "Achieved"
      refute milestone_row(html, "milestone-first-kill") =~ "Achieved"
      refute milestone_row(html, "milestone-first-discovery") =~ "Achieved"
    end

    test "first player discovered flips independently of the other milestones" do
      html = render_panel(%{players_discovered: 1})

      assert milestone_row(html, "milestone-first-discovery") =~ "Achieved"
      refute milestone_row(html, "milestone-first-city") =~ "Achieved"
      refute milestone_row(html, "milestone-first-kill") =~ "Achieved"
      refute milestone_row(html, "milestone-first-camp") =~ "Achieved"
    end

    test "every milestone achieved at once still renders each one" do
      html =
        render_panel(%{
          cities_founded: 1,
          barbarians_killed: 1,
          camps_destroyed: 1,
          players_discovered: 1
        })

      for test_id <-
            ~w(milestone-first-city milestone-first-kill milestone-first-camp milestone-first-discovery) do
        assert milestone_row(html, test_id) =~ "Achieved"
      end
    end
  end
end
