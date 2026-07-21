defmodule BrokenOaths.Chat do
  @moduledoc """
  Player-to-player messaging (story 900): world-scoped 1:1 conversations
  between players who have discovered each other, message history with
  paging, profanity moderation, blocking, and unread tracking. Real-time
  delivery over `Phoenix.PubSub`, mirroring how `BrokenOaths.Game`
  broadcasts turn/world events — each player subscribes to their own
  per-world inbox topic and receives a `{:chat_message, message}` push
  the instant a message lands in any conversation they're part of.

  Every function below takes a `world` and the `user`(s) involved, the
  same calling convention `BrokenOaths.Game` uses — never a raw
  conversation id — so callers never have to reason about `id`s that
  cross world boundaries. Internally, each `user` is resolved to their
  `BrokenOaths.Players.Player` row for that `world` (via `Repo`, not
  `WorldServer` — the FK resolution below doesn't touch a world's live
  tick-state).

  A conversation only exists between mutually-discovered players:
  `BrokenOaths.Game.known_players/2` (backed by
  `BrokenOaths.Diplomacy.KnownPlayer`, story 899) is the single source of
  truth for who a player may reach here.
  """

  import Ecto.Query

  alias BrokenOaths.Chat.Block
  alias BrokenOaths.Chat.Conversation
  alias BrokenOaths.Chat.Message
  alias BrokenOaths.Chat.Moderation
  alias BrokenOaths.Game
  alias BrokenOaths.Players.Player
  alias BrokenOaths.Repo
  alias BrokenOaths.Users.User
  alias BrokenOaths.Worlds.World

  @page_size 50

  @type contact_summary :: %{
          user_id: integer(),
          display_name: String.t(),
          conversation_id: integer() | nil,
          unread_count: non_neg_integer(),
          blocked: boolean()
        }

  @doc """
  PubSub topic for `player_id`'s own chat inbox in `world_id` —
  subscribe to receive `{:chat_message, BrokenOaths.Chat.Message.t()}`
  for any conversation that player is part of.
  """
  @spec topic(integer(), integer()) :: String.t()
  def topic(world_id, player_id), do: "chat:world:#{world_id}:player:#{player_id}"

  @doc "Subscribe the caller to `user`'s own chat inbox in `world`."
  @spec subscribe(World.t(), User.t()) :: :ok | {:error, term()}
  def subscribe(world, user) do
    player = fetch_player!(world, user)
    Phoenix.PubSub.subscribe(BrokenOaths.PubSub, topic(world.id, player.id))
  end

  @doc """
  Every player `user` has discovered in `world` (via
  `BrokenOaths.Game.known_players/2`), each with their existing
  conversation (if any), that conversation's unread count, and whether
  `user` has blocked them.
  """
  @spec list_conversations(World.t(), User.t()) :: [contact_summary()]
  def list_conversations(world, user) do
    player = fetch_player!(world, user)

    world
    |> Game.known_players(user)
    |> Enum.map(&contact_summary(world, player, &1))
  end

  @doc """
  Opens (creating on first contact) the conversation between `user` and
  `other_user` in `world`. Refuses unless they've mutually discovered
  each other.
  """
  @spec open_conversation(World.t(), User.t(), User.t()) ::
          {:ok, Conversation.t()} | {:error, :not_discovered}
  def open_conversation(world, user, other_user) do
    with :ok <- ensure_discovered(world, user, other_user) do
      player = fetch_player!(world, user)
      other_player = fetch_player!(world, other_user)
      find_or_create_conversation(world, player, other_player)
    end
  end

  @doc """
  The most recent #{@page_size} messages between `user` and
  `other_user`, oldest first. `[]` if they've never exchanged a
  message (no conversation yet exists). Each message's `sender_player`
  (and that player's `user`) is preloaded, so callers can label a
  message with its sender without an extra round trip.
  """
  @spec recent_messages(World.t(), User.t(), User.t()) :: [Message.t()]
  def recent_messages(world, user, other_user) do
    case existing_conversation(world, user, other_user) do
      nil ->
        []

      conversation ->
        conversation.id |> messages_query() |> page_query() |> Repo.all() |> Enum.reverse()
    end
  end

  @doc """
  Up to #{@page_size} messages older than `before_message`, oldest
  first — the explicit "load older" page past the initial recent
  window. Preloads `sender_player`/`sender_player.user` the same way
  `recent_messages/3` does.
  """
  @spec load_older_messages(World.t(), User.t(), User.t(), Message.t()) :: [Message.t()]
  def load_older_messages(world, user, other_user, %Message{} = before_message) do
    case existing_conversation(world, user, other_user) do
      nil ->
        []

      conversation ->
        conversation.id
        |> messages_query()
        |> where([m], m.id < ^before_message.id)
        |> page_query()
        |> Repo.all()
        |> Enum.reverse()
    end
  end

  @doc """
  Sends `body` from `sender` to `recipient` in `world`: rejects a body
  over 500 characters, refuses if either side has blocked the other or
  they haven't mutually discovered each other, runs
  `BrokenOaths.Chat.Moderation.filter/1` over the body before
  persisting, then broadcasts the persisted message to both
  participants' inboxes. The returned (and broadcast) message's
  `sender_player`/`sender_player.user` are populated from `sender_user`
  directly (no extra query) — a freshly-sent message is always
  attributable without waiting on a re-fetch.
  """
  @spec send_message(World.t(), User.t(), User.t(), String.t()) ::
          {:ok, Message.t()} | {:error, :not_discovered | :blocked | Ecto.Changeset.t()}
  def send_message(world, sender_user, recipient_user, body) do
    sender = fetch_player!(world, sender_user)
    recipient = fetch_player!(world, recipient_user)

    with :ok <- ensure_discovered(world, sender_user, recipient_user),
         :ok <- ensure_not_blocked(world, sender, recipient),
         {:ok, conversation} <- find_or_create_conversation(world, sender, recipient),
         {:ok, message} <- insert_message(conversation, sender, body) do
      message = %{message | sender_player: %{sender | user: sender_user}}
      broadcast_message(world, sender, recipient, message)
      {:ok, message}
    end
  end

  @doc "Total unread message count across every one of `user`'s conversations in `world`."
  @spec unread_count(World.t(), User.t()) :: non_neg_integer()
  def unread_count(world, user) do
    world |> list_conversations(user) |> Enum.map(& &1.unread_count) |> Enum.sum()
  end

  @doc "Unread message count per contact, keyed by the other player's `user_id`."
  @spec unread_counts(World.t(), User.t()) :: %{integer() => non_neg_integer()}
  def unread_counts(world, user) do
    world |> list_conversations(user) |> Map.new(&{&1.user_id, &1.unread_count})
  end

  @doc """
  Marks every unread message `other_user` sent `user` in `world` as
  read. A no-op if they've never exchanged a message.
  """
  @spec mark_read(World.t(), User.t(), User.t()) :: :ok
  def mark_read(world, user, other_user) do
    player = fetch_player!(world, user)

    case existing_conversation(world, user, other_user) do
      nil -> :ok
      conversation -> mark_conversation_read(conversation, player)
    end
  end

  @doc "`user` blocks `other_user` in `world`, muting messages in both directions. Idempotent."
  @spec block(World.t(), User.t(), User.t()) :: {:ok, Block.t()} | {:error, Ecto.Changeset.t()}
  def block(world, user, other_user) do
    player = fetch_player!(world, user)
    other_player = fetch_player!(world, other_user)

    attrs = %{
      world_id: world.id,
      blocker_player_id: player.id,
      blocked_player_id: other_player.id
    }

    %Block{}
    |> Block.changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:world_id, :blocker_player_id, :blocked_player_id]
    )
  end

  @doc "`user` unblocks `other_user` in `world`. A no-op if no block exists."
  @spec unblock(World.t(), User.t(), User.t()) :: :ok
  def unblock(world, user, other_user) do
    player = fetch_player!(world, user)
    other_player = fetch_player!(world, other_user)

    Block
    |> where(
      [b],
      b.world_id == ^world.id and b.blocker_player_id == ^player.id and
        b.blocked_player_id == ^other_player.id
    )
    |> Repo.delete_all()

    :ok
  end

  @doc "Is there a block between `user` and `other_user` in `world`, in either direction?"
  @spec blocked?(World.t(), User.t(), User.t()) :: boolean()
  def blocked?(world, user, other_user) do
    player = fetch_player!(world, user)
    other_player = fetch_player!(world, other_user)
    blocked_players?(world, player, other_player)
  end

  @doc """
  The `user_id`s `user` has personally blocked in `world` — DIRECTIONAL
  (`user` is the blocker), unlike `blocked?/3`'s symmetric "is there a
  block either way" check. This is what a client seeds its own
  "did I block them" UI state from (e.g. `GameLive.ChatPanel`'s
  `:blocked_by_me`) on mount/reload, since the blocked party should
  never see the blocker's own notice.
  """
  @spec blocked_user_ids(World.t(), User.t()) :: MapSet.t(integer())
  def blocked_user_ids(world, user) do
    player = fetch_player!(world, user)

    Block
    |> where([b], b.world_id == ^world.id and b.blocker_player_id == ^player.id)
    |> join(:inner, [b], p in Player, on: p.id == b.blocked_player_id)
    |> select([_b, p], p.user_id)
    |> Repo.all()
    |> MapSet.new()
  end

  # -- Conversations -----------------------------------------------------

  defp contact_summary(world, player, %{user_id: other_user_id, display_name: display_name}) do
    other_player = fetch_player_by_user_id!(world, other_user_id)
    conversation = find_conversation(world, player, other_player)

    %{
      user_id: other_user_id,
      display_name: display_name,
      conversation_id: conversation && conversation.id,
      unread_count: conversation_unread_count(conversation, player),
      blocked: blocked_players?(world, player, other_player)
    }
  end

  defp existing_conversation(world, user, other_user) do
    player = fetch_player!(world, user)
    other_player = fetch_player!(world, other_user)
    find_conversation(world, player, other_player)
  end

  defp find_conversation(world, player, other_player) do
    {lo, hi} = canonical_pair(player.id, other_player.id)
    Repo.get_by(Conversation, world_id: world.id, player_a_id: lo, player_b_id: hi)
  end

  defp find_or_create_conversation(world, player, other_player) do
    case find_conversation(world, player, other_player) do
      nil -> insert_conversation(world, player, other_player)
      conversation -> {:ok, conversation}
    end
  end

  defp insert_conversation(world, player, other_player) do
    {lo, hi} = canonical_pair(player.id, other_player.id)
    attrs = %{world_id: world.id, player_a_id: lo, player_b_id: hi}

    case %Conversation{} |> Conversation.changeset(attrs) |> Repo.insert() do
      {:ok, conversation} -> {:ok, conversation}
      {:error, _changeset} -> {:ok, find_conversation(world, player, other_player)}
    end
  end

  defp canonical_pair(a_id, b_id) when a_id <= b_id, do: {a_id, b_id}
  defp canonical_pair(a_id, b_id), do: {b_id, a_id}

  # -- Messages ------------------------------------------------------------

  defp messages_query(conversation_id) do
    from(m in Message,
      where: m.conversation_id == ^conversation_id,
      preload: [sender_player: :user]
    )
  end

  defp page_query(query), do: query |> order_by(desc: :id) |> limit(^@page_size)

  defp insert_message(conversation, sender, body) do
    attrs = %{
      conversation_id: conversation.id,
      sender_player_id: sender.id,
      body: Moderation.filter(body)
    }

    %Message{} |> Message.changeset(attrs) |> Repo.insert()
  end

  defp broadcast_message(world, sender, recipient, message) do
    for player <- [sender, recipient] do
      Phoenix.PubSub.broadcast(
        BrokenOaths.PubSub,
        topic(world.id, player.id),
        {:chat_message, message}
      )
    end

    :ok
  end

  # -- Unread ----------------------------------------------------------------

  defp conversation_unread_count(nil, _player), do: 0

  defp conversation_unread_count(conversation, player) do
    Message
    |> unread_query(conversation, player)
    |> Repo.aggregate(:count)
  end

  defp mark_conversation_read(conversation, player) do
    Message
    |> unread_query(conversation, player)
    |> Repo.update_all(set: [read_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)])

    :ok
  end

  defp unread_query(query, conversation, player) do
    where(
      query,
      [m],
      m.conversation_id == ^conversation.id and is_nil(m.read_at) and
        m.sender_player_id != ^player.id
    )
  end

  # -- Blocking ----------------------------------------------------------------

  defp blocked_players?(world, player_a, player_b) do
    Block
    |> where([b], b.world_id == ^world.id)
    |> where(
      [b],
      (b.blocker_player_id == ^player_a.id and b.blocked_player_id == ^player_b.id) or
        (b.blocker_player_id == ^player_b.id and b.blocked_player_id == ^player_a.id)
    )
    |> Repo.exists?()
  end

  # -- Discovery guard -----------------------------------------------------

  defp ensure_discovered(world, user, other_user) do
    if mutually_discovered?(world, user, other_user), do: :ok, else: {:error, :not_discovered}
  end

  defp ensure_not_blocked(world, player, other_player) do
    if blocked_players?(world, player, other_player), do: {:error, :blocked}, else: :ok
  end

  defp mutually_discovered?(world, user, other_user) do
    world |> Game.known_players(user) |> Enum.any?(&(&1.user_id == other_user.id))
  end

  # -- Player resolution -----------------------------------------------------

  defp fetch_player!(world, user), do: Repo.get_by!(Player, world_id: world.id, user_id: user.id)

  defp fetch_player_by_user_id!(world, user_id),
    do: Repo.get_by!(Player, world_id: world.id, user_id: user_id)
end
