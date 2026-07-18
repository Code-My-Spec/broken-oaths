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
    players_discovered: 0
  }

  defp render_panel(overrides),
    do: render_component(ProgressPanel, Map.merge(@base_assigns, overrides))

  # Isolates a single `data-test="ID"` `<span>`'s own text out of the
  # full rendered HTML — robust to whatever whitespace HEEx renders
  # around an interpolation, unlike matching a raw substring against
  # the whole document (which risks colliding with an unrelated span
  # that happens to carry the same digit).
  defp span(html, test_id) do
    [_, fragment] = String.split(html, ~s(data-test="#{test_id}">), parts: 2)
    [text | _] = String.split(fragment, "</span>", parts: 2)
    text
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
      assert span(html, "progress-bronze-working") == "0 / 100"
    end

    test "shows the projected turns to Bronze Working at the current rate" do
      player_research = %{@no_research | science_per_turn: 4}
      html = render_panel(%{player_research: player_research})

      assert span(html, "progress-science-per-turn") == "4"
      # 100 science cost / 4 per turn == 25 turns, no rounding needed.
      assert span(html, "progress-turns-to-bronze") == "25"
    end

    test "rounds the turns-to-Bronze projection UP to a whole turn" do
      player_research = %{@no_research | science_per_turn: 3}
      html = render_panel(%{player_research: player_research})

      # ceil(100 / 3) == 34, not the truncated 33.
      assert span(html, "progress-turns-to-bronze") == "34"
    end

    test "reflects science already banked toward Bronze Working" do
      player_research = %{
        @no_research
        | science_per_turn: 5,
          banked_science: %{bronze_working: 40}
      }

      html = render_panel(%{player_research: player_research})

      assert span(html, "progress-bronze-working") == "40 / 100"
      # (100 - 40) / 5 == 12
      assert span(html, "progress-turns-to-bronze") == "12"
    end

    test "never crashes with zero science income — renders a placeholder instead" do
      html = render_panel(%{player_research: @no_research})
      assert span(html, "progress-turns-to-bronze") == "—"
    end

    test "reads Bronze Age once bronze_working is completed" do
      player_research = %{
        @no_research
        | completed_techs: [:bronze_working],
          science_per_turn: 6,
          banked_science: %{bronze_working: 100}
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
