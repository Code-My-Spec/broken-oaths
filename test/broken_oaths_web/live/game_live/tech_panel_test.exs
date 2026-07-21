defmodule BrokenOathsWeb.GameLive.TechPanelTest do
  @moduledoc """
  QA issue ff4400be "Revise tech menu" — regular ConnCase LiveView
  tests, not spex/BDD, guarding the two CSS-layout fixes the story 902
  `Criterion7627Spex`/`Criterion7712Spex` prereq specs don't themselves
  assert on (those check the prereq TEXT/selectors, not the panel's own
  class contract):

    * the open panel escapes `Play`'s own top status bar (`overflow-x-
      auto` below `md:`, see that render/1 clause's own moduledoc note)
      via `fixed` positioning instead of `absolute` below `md:`, so it
      is never clipped by that row's own scrolling ancestor on a
      portrait phone.
    * `max-h-[70vh] overflow-y-auto` bounds the panel so an eleven-tech
      list scrolls inside the card instead of running off-screen.
    * `z-30` — above `BoardOverlays`'s own `z-20` overlay tier — so the
      panel always paints over the board canvas.

  See `BrokenOathsWeb.GameLive.TechPanel`'s own moduledoc, "Mobile
  layering + overflow (QA issue ff4400be)", for the full rationale.
  """

  use BrokenOathsTest.ConnCase, async: false

  import Phoenix.LiveViewTest
  import BrokenOaths.WorldsFixtures

  setup :register_and_log_in_user

  setup do
    {:ok, world: world_fixture(%{seed: 424_242})}
  end

  defp join_and_mount(conn, world) do
    {:ok, join_live, _html} = live(conn, ~p"/play")

    join_live
    |> element("[data-test='join-world-#{world.id}']")
    |> render_click()

    live(conn, ~p"/play/#{world.id}")
  end

  describe "the open panel's own layout contract (QA issue ff4400be)" do
    test "sits above the board on mobile: fixed off-canvas escape + a z-index above BoardOverlays' own z-20 tier",
         %{conn: conn, world: world} do
      {:ok, play_live, _html} = join_and_mount(conn, world)

      html =
        play_live
        |> element("[data-test='tech-tree-button']")
        |> render_click()

      assert has_element?(play_live, "[data-test='tech-panel']")
      assert html =~ "fixed"
      assert html =~ "z-30"
      # Desktop keeps the original dropdown-under-the-button shape —
      # unaffected by the mobile escape above.
      assert html =~ "md:absolute"
      assert html =~ "md:z-10"
    end

    test "never overflows the screen: a viewport-relative max-height with its own scrollbar",
         %{conn: conn, world: world} do
      {:ok, play_live, _html} = join_and_mount(conn, world)

      html =
        play_live
        |> element("[data-test='tech-tree-button']")
        |> render_click()

      assert html =~ "max-h-[70vh]"
      assert html =~ "overflow-y-auto"
    end

    test "is bounded/full-width rather than a fixed w-80 below md:, keeping w-80 at md: and up",
         %{conn: conn, world: world} do
      {:ok, play_live, _html} = join_and_mount(conn, world)

      html =
        play_live
        |> element("[data-test='tech-tree-button']")
        |> render_click()

      assert html =~ "inset-x-3"
      assert html =~ "md:w-80"
    end
  end

  describe "each locked tech names its own prerequisite" do
    test "Writing (gated on Pottery) shows a tech-prereqs row naming Pottery", %{
      conn: conn,
      world: world
    } do
      {:ok, play_live, _html} = join_and_mount(conn, world)

      play_live
      |> element("[data-test='tech-tree-button']")
      |> render_click()

      assert has_element?(play_live, "[data-test='tech-prereqs-writing']", "Pottery")
      assert has_element?(play_live, "[data-test='tech-locked-writing']")
    end

    test "a tier-1 tech with no prerequisite renders no tech-prereqs row", %{
      conn: conn,
      world: world
    } do
      {:ok, play_live, _html} = join_and_mount(conn, world)

      play_live
      |> element("[data-test='tech-tree-button']")
      |> render_click()

      refute has_element?(play_live, "[data-test='tech-prereqs-pottery']")
    end
  end

  describe "the Tech button's own progress fill (playtest issue 2)" do
    alias BrokenOathsWeb.GameLive.TechPanel

    @no_research %{
      completed_techs: [],
      current_research: nil,
      banked_science: %{},
      science_per_turn: 0,
      progress: nil
    }

    defp render_panel(overrides) do
      assigns =
        Map.merge(
          %{
            id: "tech-panel",
            open?: false,
            player_research: @no_research,
            bronze_working_pending?: false
          },
          overrides
        )

      render_component(TechPanel, assigns)
    end

    test "renders a zero-width fill with nothing currently researching" do
      html = render_panel(%{})
      assert html =~ ~s(data-test="tech-button-fill")
      assert html =~ "width: 0%"
    end

    test "fills proportionally to banked/cost of the current research" do
      player_research = %{
        @no_research
        | current_research: :pottery,
          banked_science: %{pottery: 40},
          progress: %{tech: :pottery, banked: 40, cost: 80}
      }

      html = render_panel(%{player_research: player_research})
      assert html =~ "width: 50%"
    end

    test "caps the fill at 100% for an over-banked tech" do
      player_research = %{
        @no_research
        | current_research: :pottery,
          banked_science: %{pottery: 200},
          progress: %{tech: :pottery, banked: 200, cost: 80}
      }

      html = render_panel(%{player_research: player_research})
      assert html =~ "width: 100%"
    end
  end
end
