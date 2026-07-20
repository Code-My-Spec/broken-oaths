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

  # QA issue 1c47edff "Granary confusion" — a built Granary had no
  # visible trace anywhere in the city UI.
  describe "the Granary indicator" do
    test "renders with the real food bonus when the city has a granary" do
      city = Map.put(@city, :has_granary, true)
      html = render_panel(city: city, player_research: @pottery_done)

      assert html =~ ~s(data-test="city-granary")
      assert html =~ "Granary"
      assert html =~ "+#{BrokenOaths.Cities.Yields.granary_food_bonus()} food"
    end

    test "is absent when the city has no granary" do
      html = render_panel(player_research: @pottery_done)

      refute html =~ ~s(data-test="city-granary")
    end
  end

  # QA issue e51a31be "UI issues" — the detail pane needed a dismiss
  # affordance.
  describe "the close control" do
    test "renders and bubbles clear_selection to the parent LiveView" do
      html = render_panel([])

      assert html =~ ~s(data-test="close-city-panel")
      assert html =~ ~s(phx-click="clear_selection")
    end
  end

  describe "Bronze Age reached" do
    test "offers the Bronze Spearman, alongside the always-available types" do
      html = render_panel(player_research: @bronze_age, copper_access?: true)

      assert html =~ ~s(data-test="production-option-bronze_spearman")
      assert html =~ "Bronze Spearman"
      assert html =~ ~s(data-test="production-option-settler")
      assert html =~ ~s(data-test="production-option-worker")
      assert html =~ ~s(data-test="production-option-warrior")
      refute html =~ ~s(data-test="production-option-granary")
    end

    test "Bronze Spearman is still offered (but disabled) without copper_access? at all" do
      html = render_panel(player_research: @bronze_age)

      assert html =~ ~s(data-test="production-option-bronze_spearman")
    end
  end

  # Story 911 — Bronze Spearman needs Copper access, ON TOP of the
  # Bronze Age itself (story 903), to actually be queueable.
  describe "story 911 — the Bronze Spearman's Copper gate" do
    test "renders enabled once both the Bronze Age and Copper access are met" do
      html = render_panel(player_research: @bronze_age, copper_access?: true)

      assert html =~ ~s(data-test="production-option-bronze_spearman" data-disabled="false")
    end

    test "renders disabled in the Bronze Age without Copper access" do
      html = render_panel(player_research: @bronze_age, copper_access?: false)

      assert html =~ ~s(data-test="production-option-bronze_spearman" data-disabled="true")
    end

    test "renders disabled when copper_access? is omitted entirely (defaults to false)" do
      html = render_panel(player_research: @bronze_age)

      assert html =~ ~s(data-test="production-option-bronze_spearman" data-disabled="true")
    end

    test "the requirement is legible and shows MET once Copper access is present" do
      html = render_panel(player_research: @bronze_age, copper_access?: true)

      assert html =~ ~s(data-test="production-requirement-bronze_spearman" data-copper-met="true")
      assert html =~ "Requires Copper"
    end

    test "the requirement is legible and shows NOT MET without Copper access" do
      html = render_panel(player_research: @bronze_age, copper_access?: false)

      assert html =~ ~s(data-test="production-requirement-bronze_spearman" data-copper-met="false")
      assert html =~ "Requires Copper"
    end

    test "the requirement note is absent for every other buildable" do
      html = render_panel(player_research: @bronze_age, copper_access?: true)

      refute html =~ ~s(data-test="production-requirement-settler")
      refute html =~ ~s(data-test="production-requirement-worker")
      refute html =~ ~s(data-test="production-requirement-warrior")
    end
  end
end
