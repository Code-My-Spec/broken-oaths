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

  # QA issue 8aa2c571: a worker mid-dig had no way to back out of it —
  # the Cancel Build button sits beside the dig-progress badge and only
  # ever renders alongside it.
  # QA issue e51a31be "UI issues" — same dismiss affordance as
  # CityPanel.
  describe "the close control" do
    test "renders and bubbles clear_selection to the parent LiveView" do
      html = render_component(UnitPanel, id: "unit-panel", unit: @lord, order: nil)

      assert html =~ ~s(data-test="close-unit-panel")
      assert html =~ ~s(phx-click="clear_selection")
    end
  end

  describe "a worker with a dig in progress" do
    @worker %{type: :worker, hp: 6, max_hp: 6, movement: 2, max_movement: 2}

    test "shows the Cancel Build action beside the dig-progress badge" do
      current_dig = %{kind: :farm, progress: 1}

      html =
        render_component(UnitPanel,
          id: "unit-panel",
          unit: @worker,
          order: nil,
          current_dig: current_dig
        )

      assert html =~ ~s(data-test="dig-progress")
      assert html =~ ~s(data-test="cancel-build")
      assert html =~ "Cancel Build"
    end

    test "hides Cancel Build when there's no dig in progress" do
      html =
        render_component(UnitPanel,
          id: "unit-panel",
          unit: @worker,
          order: nil,
          allowed_improvements: [:farm]
        )

      refute html =~ ~s(data-test="dig-progress")
      refute html =~ ~s(data-test="cancel-build")
    end
  end

  # Story 882 playtest update (issue 1caa87e9 — worker build charges):
  # the selected worker shows how many build charges it has left.
  describe "a worker's build charges" do
    test "shows the worker's remaining charges" do
      worker = %{type: :worker, hp: 6, max_hp: 6, movement: 2, max_movement: 2, charges: 2}

      html = render_component(UnitPanel, id: "unit-panel", unit: worker, order: nil)

      assert html =~ ~s(data-test="unit-charges")
      assert html =~ "2 charges"
    end

    test "defaults to 3 charges when the unit map carries none" do
      worker = %{type: :worker, hp: 6, max_hp: 6, movement: 2, max_movement: 2}

      html = render_component(UnitPanel, id: "unit-panel", unit: worker, order: nil)

      assert html =~ ~s(data-test="unit-charges")
      assert html =~ "3 charges"
    end

    test "never shows charges for a non-worker unit" do
      html = render_component(UnitPanel, id: "unit-panel", unit: @lord, order: nil)

      refute html =~ ~s(data-test="unit-charges")
    end
  end

  # QA issue 56ee521a: the discoverable Attack-city affordance — one
  # button per hostile city `Play`'s own `attackable_cities/3` found
  # adjacent to the selected unit.
  describe "attackable_cities" do
    test "renders no Attack button when nothing is attackable" do
      html = render_component(UnitPanel, id: "unit-panel", unit: @lord, order: nil)

      refute html =~ ~s(data-test="attack-city-)
    end

    test "renders an Attack button per attackable hostile city, wired to the attack handler" do
      html =
        render_component(UnitPanel,
          id: "unit-panel",
          unit: @lord,
          order: nil,
          attackable_cities: [%{id: 7, name: "Rivergate"}]
        )

      assert html =~ ~s(data-test="attack-city-7")
      assert html =~ ~s(phx-click="attack")
      assert html =~ ~s(phx-value-target_city_id="7")
      assert html =~ "Attack Rivergate"
    end

    # QA issue 7f91cff2 — a BROKEN (0 HP, not yet captured) hostile city
    # must swap the discoverable button from "Attack" to "Move In": the
    # capture is a MOVEMENT event, so it dispatches `queue_move`/
    # `to_tile` instead of `attack`/`target_city_id`, and never renders
    # the plain Attack affordance for that city.
    test "renders a Move In button (not Attack) once the attackable city is broken" do
      html =
        render_component(UnitPanel,
          id: "unit-panel",
          unit: @lord,
          order: nil,
          attackable_cities: [%{id: 7, name: "Rivergate", tile_id: 42, broken: true}]
        )

      assert html =~ ~s(data-test="move-in-city-7")
      assert html =~ ~s(phx-click="queue_move")
      assert html =~ ~s(phx-value-to_tile="42")
      assert html =~ "Move In Rivergate"

      refute html =~ ~s(data-test="attack-city-7")
    end
  end

  # Story 920 — the discoverable Fortify affordance: a `:defend`-capable
  # unit not yet braced gets the button; once braced, a "Fortified"
  # badge stands in for it instead — never both at once.
  describe "Fortify (story 920)" do
    test "shows the Fortify button for a defend-capable unit that isn't fortified" do
      html = render_component(UnitPanel, id: "unit-panel", unit: @lord, order: nil)

      assert html =~ ~s(data-test="fortify")
      assert html =~ ~s(phx-click="fortify")
      assert html =~ "Fortify"
      refute html =~ ~s(data-test="unit-fortified")
    end

    test "swaps the button for a Fortified badge once the unit carries the flag" do
      fortified_lord = Map.put(@lord, :fortified, true)

      html = render_component(UnitPanel, id: "unit-panel", unit: fortified_lord, order: nil)

      assert html =~ ~s(data-test="unit-fortified")
      assert html =~ "Fortified"
      refute html =~ ~s(data-test="fortify")
    end

    # Barbarians never carry `:defend` (`Units.Actions.available/1`) —
    # never offer the button, even though this panel doubles as the
    # threat readout for enemy units.
    test "never offers Fortify for a barbarian" do
      barbarian = %{type: :barbarian_warrior, hp: 15, max_hp: 15, movement: 1, max_movement: 1}

      html = render_component(UnitPanel, id: "unit-panel", unit: barbarian, order: nil)

      refute html =~ ~s(data-test="fortify")
      refute html =~ ~s(data-test="unit-fortified")
    end

    test "defaults to not fortified when the unit map carries no :fortified key" do
      html = render_component(UnitPanel, id: "unit-panel", unit: @lord, order: nil)

      refute html =~ ~s(data-test="unit-fortified")
    end
  end
end
