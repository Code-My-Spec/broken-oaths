defmodule BrokenOathsWeb.GameLive.KnownPlayersPanelTest do
  use BrokenOathsTest.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BrokenOathsWeb.GameLive.KnownPlayersPanel

  describe "no known players yet" do
    test "renders the empty state" do
      html = render_component(KnownPlayersPanel, id: "known-players-panel", known_players: [])

      assert html =~ ~s(data-test="known-players-empty")
      refute html =~ ~s(data-test="known-player-)
    end
  end

  describe "one or more known players" do
    test "lists each discovered player by display name, never the email" do
      known_players = [%{user_id: 7, display_name: "Sir Rival"}]

      html =
        render_component(KnownPlayersPanel,
          id: "known-players-panel",
          known_players: known_players
        )

      refute html =~ ~s(data-test="known-players-empty")
      assert html =~ ~s(data-test="known-player-7")
      assert html =~ "Sir Rival"
      # Playtest issue 2a9df843: the panel only ever receives display names,
      # so an email can never reach the other player's screen.
      refute html =~ "@example.com"
    end

    test "each row carries a chat-link affordance" do
      known_players = [%{user_id: 7, display_name: "Sir Rival"}]

      html =
        render_component(KnownPlayersPanel,
          id: "known-players-panel",
          known_players: known_players
        )

      assert html =~ ~s(data-test="chat-link")
    end

    test "each row pushes center_on_player with the player's own user_id (playtest issue 4)" do
      known_players = [%{user_id: 7, display_name: "Sir Rival"}]

      html =
        render_component(KnownPlayersPanel,
          id: "known-players-panel",
          known_players: known_players
        )

      assert html =~ ~s(phx-click="center_on_player")
      assert html =~ ~s(phx-value-user_id="7")
    end

    test "renders one row per discovered player" do
      known_players = [
        %{user_id: 7, display_name: "Sir Rival"},
        %{user_id: 9, display_name: "Lady Foe"}
      ]

      html =
        render_component(KnownPlayersPanel,
          id: "known-players-panel",
          known_players: known_players
        )

      assert html =~ ~s(data-test="known-player-7")
      assert html =~ ~s(data-test="known-player-9")
    end
  end
end
