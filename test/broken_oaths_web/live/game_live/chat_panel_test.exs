defmodule BrokenOathsWeb.GameLive.ChatPanelTest do
  # async: false — exercises a real `Game.WorldServer` (via
  # `Game.join_world/2`), the same reason `BrokenOaths.ChatTest` opts
  # out of async.
  use BrokenOathsTest.DataCase, async: false

  # `@endpoint` + `Phoenix.ConnTest` are only needed by the
  # "blocking and unblocking" describe block below, which drives a
  # full `GameLive.Play` mount (`live/2`) the same way story 900's own
  # spex under `test/spex/900_player-to-player_chat/` do — a bare
  # `render_component/2` call can't preserve `ChatPanel`'s LiveComponent
  # state (`:blocked_by_me`) across the block -> unblock event sequence.
  @endpoint BrokenOathsWeb.Endpoint

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias BrokenOaths.Chat
  alias BrokenOaths.Game
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures
  alias BrokenOathsWeb.GameLive.ChatPanel

  defp discovered_pair_fixture(world_attrs \\ %{seed: 424_242, frequency: 8}) do
    world = WorldsFixtures.world_fixture(world_attrs)
    user = UsersFixtures.user_fixture()
    other_user = UsersFixtures.user_fixture()

    {:ok, player} = Game.join_world(world, user)
    {:ok, other_player} = Game.join_world(world, other_user)

    Repo.insert!(
      Game.KnownPlayer.changeset(%Game.KnownPlayer{}, %{
        world_id: world.id,
        viewer_player_id: player.id,
        discovered_player_id: other_player.id
      })
    )

    Repo.insert!(
      Game.KnownPlayer.changeset(%Game.KnownPlayer{}, %{
        world_id: world.id,
        viewer_player_id: other_player.id,
        discovered_player_id: player.id
      })
    )

    Game.restart_world_server(world)

    %{world: world, user: user, other_user: other_user}
  end

  describe "closed by default" do
    test "always renders the chat-button, with the panel closed" do
      %{world: world, user: user} = discovered_pair_fixture()

      html =
        render_component(ChatPanel,
          id: "chat-panel",
          world: world,
          user: user,
          chat_target_user_id: nil
        )

      assert html =~ ~s(data-test="chat-button")
      refute html =~ ~s(data-test="chat-panel")
    end

    test "no unread badge when nothing is unread" do
      %{world: world, user: user} = discovered_pair_fixture()

      html =
        render_component(ChatPanel,
          id: "chat-panel",
          world: world,
          user: user,
          chat_target_user_id: nil
        )

      refute html =~ ~s(data-test="chat-badge")
    end
  end

  describe "unread badge" do
    test "shows the total unread count on the chat-button, even while closed" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()
      {:ok, _message} = Chat.send_message(world, other_user, user, "Are you there?")

      html =
        render_component(ChatPanel,
          id: "chat-panel",
          world: world,
          user: user,
          chat_target_user_id: nil
        )

      assert html =~ ~s(data-test="chat-badge")
      assert html =~ "1"
    end
  end

  # QA issue c702b6c8: `:blocked_by_me` was seeded empty on every mount,
  # so after a page reload a player who had blocked someone saw a
  # normal composer instead of `chat-blocked-notice` — the block was
  # still enforced server-side (`Chat.send_message/4` still refuses
  # it), the UI just lied about it until a send failed. Uses
  # `render_component/2` directly (a fresh component build, no prior
  # `"block-player"` click in this process) to prove the notice comes
  # from server truth, not from having clicked block earlier in the
  # same live session.
  describe "blocked_by_me is seeded from server truth on mount" do
    test "a block placed before this component ever mounted still shows the blocked-notice" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()

      assert {:ok, _block} = Chat.block(world, user, other_user)

      html =
        render_component(ChatPanel,
          id: "chat-panel",
          world: world,
          user: user,
          chat_target_user_id: other_user.id
        )

      assert html =~ ~s(data-test="chat-blocked-notice")
      assert html =~ ~s(data-test="unblock-player")
      refute html =~ ~s(data-test="chat-form")
    end

    test "an undiscovered/unblocked contact still gets the composer on a fresh mount" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()

      html =
        render_component(ChatPanel,
          id: "chat-panel",
          world: world,
          user: user,
          chat_target_user_id: other_user.id
        )

      refute html =~ ~s(data-test="chat-blocked-notice")
      assert html =~ ~s(data-test="chat-form")
    end
  end

  # QA issue a511bc8a: `Chat.unblock/3` existed but nothing in the UI
  # called it — the blocked-notice copy promised "unblock them" with no
  # reachable control. Drives a full `GameLive.Play` mount (not
  # `render_component/2`) so `:blocked_by_me` state survives across the
  # block -> unblock click sequence.
  describe "blocking and unblocking" do
    test "block-player swaps the composer for a notice; unblock-player restores it" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()

      conn =
        build_conn()
        |> BrokenOathsTest.ConnCase.log_in_user(user)

      {:ok, play_live, _html} = live(conn, "/play/#{world.id}")

      play_live
      |> element("[data-test='chat-button']")
      |> render_click()

      play_live
      |> element("[data-test='known-player-#{other_user.id}']")
      |> render_click()

      assert has_element?(play_live, "[data-test='chat-form']")
      refute has_element?(play_live, "[data-test='unblock-player']")

      play_live
      |> element("[data-test='block-player']")
      |> render_click()

      assert has_element?(play_live, "[data-test='chat-blocked-notice']")
      assert has_element?(play_live, "[data-test='unblock-player']")
      refute has_element?(play_live, "[data-test='chat-form']")
      assert Chat.blocked?(world, user, other_user)

      play_live
      |> element("[data-test='unblock-player']")
      |> render_click()

      refute has_element?(play_live, "[data-test='chat-blocked-notice']")
      refute has_element?(play_live, "[data-test='unblock-player']")
      assert has_element?(play_live, "[data-test='chat-form']")
      refute Chat.blocked?(world, user, other_user)

      assert {:ok, _message} = Chat.send_message(world, user, other_user, "we're good now")
    end
  end
end
