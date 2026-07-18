defmodule BrokenOathsWeb.GameLive.UnitPanelTest do
  use BrokenOathsTest.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BrokenOathsWeb.GameLive.UnitPanel

  @lord %{type: :lord, hp: 12, max_hp: 12, movement: 2, max_movement: 2}
  @settler %{type: :settler, hp: 8, max_hp: 8, movement: 1, max_movement: 1}
  @bronze_spearman %{type: :bronze_spearman, hp: 120, max_hp: 120, movement: 1, max_movement: 1}

  describe "no unit selected" do
    test "renders without the unit panel" do
      html = render_component(UnitPanel, id: "unit-panel", unit: nil, order: nil)

      refute html =~ ~s(data-test="unit-panel")
    end
  end

  describe "a unit is selected" do
    test "shows the unit's type, hit points, and movement remaining" do
      html = render_component(UnitPanel, id: "unit-panel", unit: @lord, order: nil)

      assert html =~ ~s(data-test="unit-panel")
      assert html =~ ~s(data-test="unit-type")
      assert html =~ "Lord"
      assert html =~ ~s(data-test="unit-hp")
      assert html =~ ~s(data-test="unit-movement")
    end

    test "labels a settler correctly" do
      html = render_component(UnitPanel, id: "unit-panel", unit: @settler, order: nil)

      assert html =~ ~s(data-test="unit-type")
      assert html =~ "Settler"
    end

    # Regression for issue b8f4ce10: selecting a bronze_spearman raised
    # a FunctionClauseError in unit_type_label/1 and killed the LiveView.
    test "labels a bronze_spearman correctly without raising" do
      html = render_component(UnitPanel, id: "unit-panel", unit: @bronze_spearman, order: nil)

      assert html =~ ~s(data-test="unit-panel")
      assert html =~ ~s(data-test="unit-type")
      assert html =~ "Bronze Spearman"
    end

    test "shows no orders queued when the unit has no order" do
      html = render_component(UnitPanel, id: "unit-panel", unit: @lord, order: nil)

      assert html =~ ~s(data-test="unit-order")
      assert html =~ "No orders queued"
    end

    test "shows the queued order's destination" do
      order = %{target_tile: 42, status: :pending}

      html = render_component(UnitPanel, id: "unit-panel", unit: @settler, order: order)

      assert html =~ ~s(data-test="unit-order")
      assert html =~ "42"
      refute html =~ ~s(data-test="order-interrupted")
    end

    test "flags an interrupted order" do
      order = %{target_tile: 42, status: :interrupted}

      html = render_component(UnitPanel, id: "unit-panel", unit: @settler, order: order)

      assert html =~ ~s(data-test="order-interrupted")
    end
  end
end
