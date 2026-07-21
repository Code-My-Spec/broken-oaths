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
  # Story 930 — Library/Ancient Walls/Water Mill's own gates.
  @writing_done %{completed_techs: [:writing], current_research: nil, banked_science: %{}}
  @masonry_done %{completed_techs: [:masonry], current_research: nil, banked_science: %{}}
  @the_wheel_done %{completed_techs: [:the_wheel], current_research: nil, banked_science: %{}}
  # Story 933 — the Hanging Gardens wonder's own gate.
  @irrigation_done %{completed_techs: [:irrigation], current_research: nil, banked_science: %{}}

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

  # Story 930 — Library, Ancient Walls, Barracks, Water Mill: each is
  # hidden until its own tech, offered (and enabled) once it is —
  # mirrors the Granary's own "Pottery completed" describe block above.
  describe "story 930 — Library (Writing)" do
    test "hidden in the Stone Age" do
      html = render_panel(player_research: @stone_age)
      refute html =~ ~s(data-test="production-option-library")
    end

    test "offered and enabled once Writing is researched" do
      html = render_panel(player_research: @writing_done)
      assert html =~ ~s(data-test="production-option-library" data-disabled="false")
      assert html =~ "Library"
    end

    test "renders disabled once the city already has one" do
      city = Map.put(@city, :buildings, [:library])
      html = render_panel(city: city, player_research: @writing_done)
      assert html =~ ~s(data-test="production-option-library" data-disabled="true")
    end
  end

  describe "story 930 — Ancient Walls (Masonry)" do
    test "hidden in the Stone Age" do
      html = render_panel(player_research: @stone_age)
      refute html =~ ~s(data-test="production-option-ancient_walls")
    end

    test "offered and enabled once Masonry is researched" do
      html = render_panel(player_research: @masonry_done)
      assert html =~ ~s(data-test="production-option-ancient_walls" data-disabled="false")
      assert html =~ "Ancient Walls"
    end
  end

  describe "story 930 — Barracks (Bronze Working)" do
    test "hidden before the Bronze Age" do
      html = render_panel(player_research: @stone_age)
      refute html =~ ~s(data-test="production-option-barracks")
    end

    test "offered and enabled once the Bronze Age is reached" do
      html = render_panel(player_research: @bronze_age)
      assert html =~ ~s(data-test="production-option-barracks" data-disabled="false")
      assert html =~ "Barracks"
    end
  end

  describe "story 930 — Water Mill (The Wheel)" do
    test "hidden in the Stone Age" do
      html = render_panel(player_research: @stone_age)
      refute html =~ ~s(data-test="production-option-water_mill")
    end

    test "offered and enabled once The Wheel is researched" do
      html = render_panel(player_research: @the_wheel_done)
      assert html =~ ~s(data-test="production-option-water_mill" data-disabled="false")
      assert html =~ "Water Mill"
    end
  end

  describe "story 930 — building indicators" do
    test "each built building renders its own badge with its real effect numbers" do
      city = Map.put(@city, :buildings, [:library, :ancient_walls, :barracks, :water_mill])
      html = render_panel(city: city, player_research: @writing_done)

      assert html =~ ~s(data-test="city-building-library")
      assert html =~ "+#{BrokenOaths.Technology.Research.library_science_bonus()} science"

      assert html =~ ~s(data-test="city-building-ancient_walls")
      assert html =~ "+#{BrokenOaths.Combat.CityDefense.wall_hp_bonus()} HP"

      assert html =~ ~s(data-test="city-building-barracks")
      assert html =~ ~s(data-test="city-building-water_mill")
    end

    test "no badges render for a city with none of the four built" do
      html = render_panel(player_research: @writing_done)

      refute html =~ ~s(data-test="city-building-library")
      refute html =~ ~s(data-test="city-building-ancient_walls")
      refute html =~ ~s(data-test="city-building-barracks")
      refute html =~ ~s(data-test="city-building-water_mill")
    end

    # Story 930 — Ancient Walls raises a city's own max HP; the "N/max"
    # readout has to reflect that per-city, not the flat 100 every
    # unwalled city still shows.
    test "the HP readout reflects a walled city's own higher max" do
      city = @city |> Map.put(:buildings, [:ancient_walls]) |> Map.put(:hp, 140)
      html = render_panel(city: city, player_research: @masonry_done)

      assert html =~ "140/150"
    end

    test "an unwalled city still shows the plain 100 max" do
      html = render_panel(player_research: @stone_age)
      assert html =~ "100/100"
    end
  end

  # Story 933 — the Pyramids/Hanging Gardens world wonders: hidden
  # until their own tech, offered once it is, AND (unlike every story
  # 930 building) dropped from the list entirely once claimed anywhere
  # in the world — mirrors `Production.available_items/1`'s own
  # `wonder_offerable?/3`.
  describe "story 933 — the Pyramids (Masonry)" do
    test "hidden in the Stone Age" do
      html = render_panel(player_research: @stone_age)
      refute html =~ ~s(data-test="production-option-pyramids")
    end

    test "offered and enabled once Masonry is researched and nobody has claimed it" do
      html = render_panel(player_research: @masonry_done, wonders_claimed: %{pyramids: false})
      assert html =~ ~s(data-test="production-option-pyramids" data-disabled="false")
      assert html =~ "Pyramids"
    end

    test "dropped from the list entirely once claimed anywhere in the world — even with Masonry done" do
      html = render_panel(player_research: @masonry_done, wonders_claimed: %{pyramids: true})
      refute html =~ ~s(data-test="production-option-pyramids")
    end

    test "defaults to unclaimed when wonders_claimed is omitted" do
      html = render_panel(player_research: @masonry_done)
      assert html =~ ~s(data-test="production-option-pyramids" data-disabled="false")
    end
  end

  describe "story 933 — the Hanging Gardens (Irrigation)" do
    test "hidden in the Stone Age" do
      html = render_panel(player_research: @stone_age)
      refute html =~ ~s(data-test="production-option-hanging_gardens")
    end

    test "offered and enabled once Irrigation is researched and nobody has claimed it" do
      html =
        render_panel(player_research: @irrigation_done, wonders_claimed: %{hanging_gardens: false})

      assert html =~ ~s(data-test="production-option-hanging_gardens" data-disabled="false")
      assert html =~ "Hanging Gardens"
    end

    test "dropped from the list entirely once claimed anywhere in the world" do
      html =
        render_panel(player_research: @irrigation_done, wonders_claimed: %{hanging_gardens: true})

      refute html =~ ~s(data-test="production-option-hanging_gardens")
    end
  end

  describe "story 933 — wonder building indicators" do
    test "a built wonder renders its own badge with its real effect description" do
      city = Map.put(@city, :buildings, [:pyramids, :hanging_gardens])
      html = render_panel(city: city, player_research: @masonry_done)

      assert html =~ ~s(data-test="city-building-pyramids")
      assert html =~ "Free Worker"

      assert html =~ ~s(data-test="city-building-hanging_gardens")
      assert html =~ "+15% city growth"
    end

    test "no wonder badges render for a city with neither built" do
      html = render_panel(player_research: @masonry_done)

      refute html =~ ~s(data-test="city-building-pyramids")
      refute html =~ ~s(data-test="city-building-hanging_gardens")
    end
  end
end
