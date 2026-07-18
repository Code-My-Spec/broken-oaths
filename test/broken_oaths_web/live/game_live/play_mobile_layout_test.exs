defmodule BrokenOathsWeb.GameLive.PlayMobileLayoutTest do
  @moduledoc """
  QA issue 3525f2ba "sidebar not working on mobile at all" — regular
  ConnCase LiveView tests, not spex/BDD, same status
  `BrokenOathsWeb.GameLive.PlayTest`'s own moduledoc already claims for
  this file's sibling. These assert the server-rendered DOM/CSS-class
  contract the mobile fix depends on: below `md`, the Known Players and
  Progress panels collapse behind a toggle instead of always rendering
  expanded, and neither panel is EVER duplicate-mounted (a second copy
  would collide with `known-player-ID`, breaking the one-match-per-
  selector contract `GameLive.ChatPanel`'s own moduledoc documents).
  Actual responsive rendering at a real phone viewport (Tailwind's
  `md:` breakpoint firing, the JS toggle's own show/hide) is outside
  what `Phoenix.LiveViewTest` can exercise — that's a human/Vibium QA
  pass, same "canvas board itself is never asserted" boundary
  `PlayTest`'s own moduledoc already draws for the board hook.
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

  describe "the Known Players / Progress panels collapse behind a mobile toggle" do
    test "each toggle button exists and is hidden at md: and up", %{conn: conn, world: world} do
      {:ok, play_live, _html} = join_and_mount(conn, world)

      # Both toggle buttons only ever exist below `md:` — a desktop
      # player never sees them, same "toggle button itself never
      # renders there" contract `toggle_mobile_panel/1`'s own doc makes.
      known_button = play_live |> element("[data-test='mobile-known-players-toggle']") |> render()
      progress_button = play_live |> element("[data-test='mobile-progress-toggle']") |> render()

      assert known_button =~ "md:hidden"
      assert progress_button =~ "md:hidden"
    end

    test "each panel's drawer wrapper defaults hidden below md:, always shown at md: and up", %{
      conn: conn,
      world: world
    } do
      {:ok, play_live, _html} = join_and_mount(conn, world)

      known_wrapper = play_live |> element("#mobile-known-players") |> render()
      progress_wrapper = play_live |> element("#mobile-progress-panel") |> render()

      assert known_wrapper =~ "hidden"
      assert known_wrapper =~ "md:block"
      assert progress_wrapper =~ "hidden"
      assert progress_wrapper =~ "md:block"
    end

    test "the underlying panels still render their content — exactly one copy of each", %{
      conn: conn,
      world: world
    } do
      {:ok, play_live, _html} = join_and_mount(conn, world)
      html = render(play_live)

      # A duplicate mount (one desktop copy, one mobile-drawer copy)
      # would double every `known-player-ID`/`progress-*` selector —
      # exactly the ambiguity `ChatPanel`'s own moduledoc warns a second
      # "known-player-ID" source would create. Asserting the panel's OWN
      # `data-test` container appears once is the regression guard.
      assert count_occurrences(html, ~s(data-test="known-players-panel")) == 1
      assert count_occurrences(html, ~s(data-test="progress-panel")) == 1
    end

    test "the Known Players toggle stays hidden while chat is open, same as the panel itself", %{
      conn: conn,
      world: world
    } do
      {:ok, play_live, _html} = join_and_mount(conn, world)

      play_live
      |> element("[data-test='chat-button']")
      |> render_click()

      # `ChatPanel`'s own `"toggle_chat"` handler flips `open?` locally
      # AND `send/2`s `{:chat_open_changed, true}` to the parent — Play
      # only clears `@chat_open` (and, with it, this toggle button) once
      # that `handle_info/2` lands, a beat after `render_click/1` itself
      # returns. `has_element?/2` re-renders fresh at assertion time
      # rather than trusting `render_click/1`'s own return value, so it
      # sees the settled state instead of racing it.
      assert has_element?(play_live, "[data-test='chat-panel']")

      # `ChatPanel`'s own contact list takes over the "known-player-ID"
      # selector while open — the mobile toggle for the OTHER copy of
      # that same list must not offer a way back to a hidden panel.
      refute has_element?(play_live, "[data-test='mobile-known-players-toggle']")
    end
  end

  describe "the top status bar never wraps into extra rows on mobile" do
    test "scrolls horizontally below md:, wraps normally at md: and up", %{
      conn: conn,
      world: world
    } do
      {:ok, play_live, _html} = join_and_mount(conn, world)
      html = render(play_live)

      assert html =~ "flex-nowrap"
      assert html =~ "overflow-x-auto"
      assert html =~ "md:flex-wrap"
    end
  end

  describe "long-press text selection is disabled across the game chrome (QA issue d80792c6)" do
    test "the board root disables user-select and the iOS text-selection callout", %{
      conn: conn,
      world: world
    } do
      {:ok, play_live, _html} = join_and_mount(conn, world)
      html = render(play_live)

      assert html =~ "select-none"
      assert html =~ "-webkit-touch-callout:none"
    end

    test "the Help modal opts back into normal text selection", %{conn: conn, world: world} do
      {:ok, play_live, _html} = join_and_mount(conn, world)

      html =
        play_live
        |> element("[data-test='help-button']")
        |> render_click()

      assert html =~ ~s(data-test="help-modal")
      assert html =~ "select-text"
      assert html =~ "-webkit-touch-callout:default"
    end

    test "the open Chat panel opts back into normal text selection", %{conn: conn, world: world} do
      {:ok, play_live, _html} = join_and_mount(conn, world)

      html =
        play_live
        |> element("[data-test='chat-button']")
        |> render_click()

      assert html =~ ~s(data-test="chat-panel")
      assert html =~ "select-text"
      assert html =~ "-webkit-touch-callout:default"
    end
  end

  defp count_occurrences(haystack, needle) do
    haystack
    |> String.split(needle)
    |> length()
    |> Kernel.-(1)
  end
end
