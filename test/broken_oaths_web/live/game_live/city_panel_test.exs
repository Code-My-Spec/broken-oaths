defmodule BrokenOathsWeb.GameLive.CityPanelTest do
  use BrokenOathsTest.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BrokenOathsWeb.GameLive.CityPanel

  @city %{
    id: 1,
    name: "Testville",
    tile_id: 10,
    size: 2,
    food: 3,
    food_threshold: 10,
    production: 5,
    queue: [],
    territory: [10],
    worked_tiles: [],
    hp: 100,
    defense: 5
  }

  @stone_age %{completed_techs: [], current_research: nil, banked_science: %{}}
  @pottery_done %{completed_techs: [:pottery], current_research: nil, banked_science: %{}}
  @bronze_age %{completed_techs: [:bronze_working], current_research: nil, banked_science: %{}}

  defp render_panel(assigns_overrides) do
    assigns =
      Keyword.merge(
        [id: "city-panel", city: @city, assignable_tiles: [], player_research: @stone_age],
        assigns_overrides
      )

    render_component(CityPanel, assigns)
  end

  describe "no research yet (Stone Age)" do
    test "offers exactly Settler, Worker, and Warrior" do
      html = render_panel(player_research: @stone_age)

      assert html =~ ~s(data-test="production-option-settler")
      assert html =~ ~s(data-test="production-option-worker")
      assert html =~ ~s(data-test="production-option-warrior")
      refute html =~ ~s(data-test="production-option-granary")
      refute html =~ ~s(data-test="production-option-bronze_spearman")
    end

    test "still offers the base catalog with a nil player_research" do
      html = render_panel(player_research: nil)

      assert html =~ ~s(data-test="production-option-settler")
      refute html =~ ~s(data-test="production-option-granary")
      refute html =~ ~s(data-test="production-option-bronze_spearman")
    end
  end

  describe "Pottery completed" do
    test "offers the Granary, still no Bronze Spearman" do
      html = render_panel(player_research: @pottery_done)

      assert html =~ ~s(data-test="production-option-granary")
      assert html =~ "Granary"
      refute html =~ ~s(data-test="production-option-bronze_spearman")
    end

    test "Granary is enabled (not disabled) when the city hasn't built one yet" do
      html = render_panel(player_research: @pottery_done)

      assert html =~ ~s(data-test="production-option-granary" data-disabled="false")
    end

    test "Granary renders disabled once the city already has one" do
      city = Map.put(@city, :has_granary, true)
      html = render_panel(city: city, player_research: @pottery_done)

      assert html =~ ~s(data-test="production-option-granary" data-disabled="true")
    end
  end

  describe "Bronze Age reached" do
    test "offers the Bronze Spearman, alongside the always-available types" do
      html = render_panel(player_research: @bronze_age)

      assert html =~ ~s(data-test="production-option-bronze_spearman")
      assert html =~ "Bronze Spearman"
      assert html =~ ~s(data-test="production-option-settler")
      assert html =~ ~s(data-test="production-option-worker")
      assert html =~ ~s(data-test="production-option-warrior")
      refute html =~ ~s(data-test="production-option-granary")
    end

    test "Bronze Spearman renders enabled" do
      html = render_panel(player_research: @bronze_age)

      assert html =~ ~s(data-test="production-option-bronze_spearman" data-disabled="false")
    end
  end
end
