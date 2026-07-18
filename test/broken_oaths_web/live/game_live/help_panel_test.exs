defmodule BrokenOathsWeb.GameLive.HelpPanelTest do
  @moduledoc """
  QA issue 937ea82b "There is no help or wiki" — component-level
  coverage for `HelpPanel`'s own closed-state markup and every
  section's `data-test` id (the LiveView-level open/close interaction
  is covered by `BrokenOathsWeb.GameLive.PlayTest`).
  """

  use BrokenOathsTest.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BrokenOathsWeb.GameLive.HelpPanel

  test "closed by default: the button renders but the modal doesn't" do
    html = render_component(HelpPanel, id: "help-panel")

    assert html =~ ~s(data-test="help-button")
    refute html =~ ~s(data-test="help-modal")
  end

  test "every documented section is present once opened" do
    html = render_component(HelpPanel, id: "help-panel", open?: true)

    for section <- ~w(
          help-section-turns
          help-section-movement
          help-section-founding
          help-section-production
          help-section-growth
          help-section-resources
          help-section-improvements
          help-section-units
          help-section-healing
          help-section-combat
          help-section-barbarians
          help-section-city-defense
          help-section-tech
          help-section-progress
        ) do
      assert html =~ ~s(data-test="#{section}")
    end
  end

  test "quotes the real healing/combat numbers, not placeholders" do
    html = render_component(HelpPanel, id: "help-panel", open?: true)

    assert html =~ "15 HP"
    assert html =~ "10 HP"
    assert html =~ "100 HP"
    assert html =~ "30-gold bounty"
  end
end
