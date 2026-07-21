defmodule BrokenOaths.ChatTest do
  # async: false — exercises real `WorldServer` processes (via
  # `Game.join_world/2` and `Game.restart_world_server/1`), the same
  # reason `BrokenOaths.Game.WorldServerTest` opts out of async.
  use BrokenOathsTest.DataCase, async: false

  alias BrokenOaths.Chat
  alias BrokenOaths.Chat.Message
  alias BrokenOaths.Game
  alias BrokenOaths.Diplomacy.KnownPlayer
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures

  # Joins two players and directly seeds a mutual `KnownPlayer` pair
  # (bypassing the actual scouting sequence story 899's discovery
  # trigger requires — that's exercised end-to-end by story 900's own
  # spex under `test/spex/900_player-to-player_chat/`), then restarts
  # the `WorldServer` so it reloads `known_players` from the rows just
  # written — mirrors `BrokenOaths.Diplomacy.KnownPlayerTest`'s direct
  # schema-level setup.
  defp discovered_pair_fixture(world_attrs \\ %{seed: 424_242, frequency: 8}) do
    world = WorldsFixtures.world_fixture(world_attrs)
    user = UsersFixtures.user_fixture()
    other_user = UsersFixtures.user_fixture()

    {:ok, player} = Game.join_world(world, user)
    {:ok, other_player} = Game.join_world(world, other_user)

    Repo.insert!(
      KnownPlayer.changeset(%KnownPlayer{}, %{
        world_id: world.id,
        viewer_player_id: player.id,
        discovered_player_id: other_player.id
      })
    )

    Repo.insert!(
      KnownPlayer.changeset(%KnownPlayer{}, %{
        world_id: world.id,
        viewer_player_id: other_player.id,
        discovered_player_id: player.id
      })
    )

    Game.restart_world_server(world)

    %{world: world, user: user, other_user: other_user}
  end

  defp stranger_fixture(world) do
    stranger = UsersFixtures.user_fixture()
    {:ok, _player} = Game.join_world(world, stranger)
    stranger
  end

  describe "list_conversations/2" do
    test "lists a mutually-discovered player as a contact with no conversation yet" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()

      assert [contact] = Chat.list_conversations(world, user)
      assert contact.user_id == other_user.id
      # Playtest issue 2a9df843: a contact carries the display-name handle,
      # never the raw email. The fixture user set no name, so it falls back.
      assert contact.display_name == "Player ##{other_user.id}"
      refute Map.has_key?(contact, :email)
      assert contact.conversation_id == nil
      assert contact.unread_count == 0
      assert contact.blocked == false
    end

    test "a contact shows the chosen display name once the player sets one" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()
      {:ok, _} = BrokenOaths.Users.update_user_display_name(other_user, %{display_name: "Rowan"})

      assert [contact] = Chat.list_conversations(world, user)
      assert contact.display_name == "Rowan"
    end

    test "does not list a player who hasn't been discovered" do
      %{world: world, user: user} = discovered_pair_fixture(%{seed: 1, frequency: 9})
      stranger = stranger_fixture(world)

      contacts = Chat.list_conversations(world, user)
      refute Enum.any?(contacts, &(&1.user_id == stranger.id))
    end

    test "discovery is mutual — the other side lists this player back" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()

      assert [contact] = Chat.list_conversations(world, other_user)
      assert contact.user_id == user.id
    end
  end

  describe "open_conversation/3" do
    test "creates a conversation between mutually-discovered players" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()

      assert {:ok, conversation} = Chat.open_conversation(world, user, other_user)
      assert conversation.world_id == world.id
    end

    test "is idempotent — opening it from either side returns the same row" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()

      assert {:ok, one} = Chat.open_conversation(world, user, other_user)
      assert {:ok, two} = Chat.open_conversation(world, other_user, user)
      assert one.id == two.id
    end

    test "refuses to open a conversation with an undiscovered player" do
      %{world: world, user: user} = discovered_pair_fixture(%{seed: 1, frequency: 9})
      stranger = stranger_fixture(world)

      assert {:error, :not_discovered} = Chat.open_conversation(world, user, stranger)
    end
  end

  describe "send_message/4" do
    test "delivers a message and it appears in the recipient's recent messages" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()

      assert {:ok, %Message{} = message} =
               Chat.send_message(world, user, other_user, "Shall we clear that camp together?")

      assert message.body == "Shall we clear that camp together?"

      assert [received] = Chat.recent_messages(world, other_user, user)
      assert received.id == message.id
      assert received.body == "Shall we clear that camp together?"
    end

    test "runs the message through Moderation before persisting" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()

      assert {:ok, message} =
               Chat.send_message(world, user, other_user, "you are a fucking coward")

      refute message.body =~ "fucking"
      assert message.body =~ "coward"
    end

    test "rejects a message over 500 characters" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()
      too_long = String.duplicate("a", 501)

      assert {:error, changeset} = Chat.send_message(world, user, other_user, too_long)
      assert %{body: ["should be at most 500 character(s)"]} = errors_on(changeset)
      assert Chat.recent_messages(world, other_user, user) == []
    end

    # QA issue eaeb3807: `chat_messages.body` was created as a bare
    # `:string` (varchar(255)) while this changeset allows up to 500
    # characters — a body in the 256-500 range passed the changeset
    # and then crashed the DB insert with `StringDataRightTruncation`.
    # A message at exactly the 500-char boundary must both pass the
    # changeset AND actually persist.
    test "a message at exactly the 500-character boundary persists" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()
      max_length = String.duplicate("a", 500)

      assert {:ok, message} = Chat.send_message(world, user, other_user, max_length)
      assert message.body == max_length

      assert [received] = Chat.recent_messages(world, other_user, user)
      assert received.id == message.id
      assert String.length(received.body) == 500
    end

    test "refuses to deliver between undiscovered players" do
      %{world: world, user: user} = discovered_pair_fixture(%{seed: 1, frequency: 9})
      stranger = stranger_fixture(world)

      assert {:error, :not_discovered} = Chat.send_message(world, user, stranger, "hello")
    end

    test "refuses to deliver once the recipient has blocked the sender" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()

      assert {:ok, _block} = Chat.block(world, other_user, user)
      assert {:error, :blocked} = Chat.send_message(world, user, other_user, "let me back in")
    end

    test "refuses to deliver once the sender has blocked the recipient (mutes both directions)" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()

      assert {:ok, _block} = Chat.block(world, user, other_user)

      assert {:error, :blocked} =
               Chat.send_message(world, other_user, user, "come on, unblock me")
    end

    test "broadcasts the message to both participants' subscribed inboxes" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()

      :ok = Chat.subscribe(world, user)
      :ok = Chat.subscribe(world, other_user)

      assert {:ok, message} =
               Chat.send_message(world, user, other_user, "Barbarians massing east")

      assert_receive {:chat_message, %Message{id: id}}, 1000
      assert id == message.id
      assert_receive {:chat_message, %Message{id: id}}, 1000
      assert id == message.id
    end
  end

  describe "recent_messages/3 and load_older_messages/4" do
    test "an unopened conversation has no messages" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()
      assert Chat.recent_messages(world, user, other_user) == []
    end

    test "recent_messages returns only the last 50, oldest first; load_older reveals the rest" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()

      for n <- 1..55 do
        label = n |> Integer.to_string() |> String.pad_leading(2, "0")

        assert {:ok, _message} =
                 Chat.send_message(world, user, other_user, "Message number #{label}")
      end

      recent = Chat.recent_messages(world, other_user, user)
      assert length(recent) == 50
      assert List.first(recent).body == "Message number 06"
      assert List.last(recent).body == "Message number 55"

      older = Chat.load_older_messages(world, other_user, user, List.first(recent))
      assert length(older) == 5
      assert List.first(older).body == "Message number 01"
      assert List.last(older).body == "Message number 05"
    end
  end

  describe "unread_count/2, unread_counts/2, and mark_read/3" do
    test "an incoming message raises the recipient's total and per-contact unread count" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()

      assert {:ok, _message} = Chat.send_message(world, other_user, user, "Are you still there?")

      assert Chat.unread_count(world, user) == 1
      assert Chat.unread_counts(world, user) == %{other_user.id => 1}
    end

    test "sending a message doesn't mark it unread for the sender" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()

      assert {:ok, _message} = Chat.send_message(world, user, other_user, "hello")

      assert Chat.unread_count(world, user) == 0
    end

    test "mark_read clears the unread count for that conversation" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()

      assert {:ok, _message} = Chat.send_message(world, other_user, user, "Are you still there?")
      assert Chat.unread_count(world, user) == 1

      :ok = Chat.mark_read(world, user, other_user)

      assert Chat.unread_count(world, user) == 0
      assert Chat.unread_counts(world, user) == %{other_user.id => 0}
    end
  end

  describe "block/3, unblock/3, and blocked?/3" do
    test "blocking is reflected in blocked?/3 from either side" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()

      refute Chat.blocked?(world, user, other_user)

      assert {:ok, _block} = Chat.block(world, user, other_user)

      assert Chat.blocked?(world, user, other_user)
      assert Chat.blocked?(world, other_user, user)
    end

    test "blocking twice is idempotent" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()

      assert {:ok, _block} = Chat.block(world, user, other_user)
      assert {:ok, _block_again} = Chat.block(world, user, other_user)
    end

    test "unblock lifts the block" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()

      assert {:ok, _block} = Chat.block(world, user, other_user)
      assert :ok = Chat.unblock(world, user, other_user)

      refute Chat.blocked?(world, user, other_user)
      assert {:ok, _message} = Chat.send_message(world, user, other_user, "we're good now")
    end

    test "list_conversations reports the block for the blocking side" do
      %{world: world, user: user, other_user: other_user} = discovered_pair_fixture()

      assert {:ok, _block} = Chat.block(world, user, other_user)

      assert [contact] = Chat.list_conversations(world, user)
      assert contact.blocked == true
    end
  end
end
