defmodule BrokenOathsWeb.GameLive.AgePanelTest do
  use BrokenOathsTest.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BrokenOathsWeb.GameLive.AgePanel

  @stone_age %{completed_techs: [], current_research: nil, banked_science: %{}}
  @bronze_age %{
    completed_techs: [:bronze_working],
    current_research: nil,
    banked_science: %{bronze_working: 100}
  }

  describe "Stone Age (no completed techs)" do
    test "always renders the age panel, reading Stone Age" do
      html = render_component(AgePanel, id: "age-panel", player_research: @stone_age)

      assert html =~ ~s(data-test="age-panel")
      assert html =~ ~s(data-test="age-status")
      assert html =~ "Stone Age"
      refute html =~ "Bronze Age"
    end
  end

  describe "Bronze Age (bronze_working completed)" do
    test "reads Bronze Age, derived purely from completed_techs" do
      html = render_component(AgePanel, id: "age-panel", player_research: @bronze_age)

      assert html =~ ~s(data-test="age-panel")
      assert html =~ ~s(data-test="age-status")
      assert html =~ "Bronze Age"
    end
  end
end
