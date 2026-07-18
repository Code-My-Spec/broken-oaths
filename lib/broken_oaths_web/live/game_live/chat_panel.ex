defmodule BrokenOathsWeb.GameLive.ChatPanel do
  @moduledoc """
  Real-time chat panel (story 900): a `chat-button` (carrying the total
  unread badge) that opens onto the known-players contact list, and —
  once a contact is selected — that conversation's thread (history,
  composer, blocking).

  Unlike `GameLive.CityPanel`/`GameLive.UnitPanel`'s pure-presentational
  pattern, this component owns real local state (which contact is
  selected, the loaded message window, the composer's error, and which
  contacts THIS viewer has blocked) and defines its own
  `handle_event/3` clauses, every one scoped with `phx-target={@myself}`
  — the standard stateful-`LiveComponent` shape.

  Mounted unconditionally by `BrokenOathsWeb.GameLive.Play` (the
  `chat-button` must always be reachable, whether or not the panel is
  open):

      <.live_component
        module={BrokenOathsWeb.GameLive.ChatPanel}
        id="chat-panel"
        world={@world}
        user={@user}
        chat_target_user_id={@chat_target_user_id}
      />

  Assigns (from `Play`):

    * `:id` - required, DOM id for this component instance
    * `:world` - the `BrokenOaths.Worlds.World` this conversation set
      belongs to (chat is per-world, story 900 criterion 7620)
    * `:user` - the viewing player's `BrokenOaths.Users.User`
    * `:chat_target_user_id` - `nil`, or another player's user id —
      set by `Play`'s `"open_chat"` handler (story 899's Known Players
      panel `chat-link`) to auto-open this panel onto that contact's
      thread. A CHANGED value (not just non-nil) is what triggers the
      auto-select, so re-picking the same contact while already open
      is a no-op and closing/reopening later doesn't repeat it.

  `:world`/`:user` are the only reads this component needs from
  `BrokenOaths.Game` (both already resolved by `Play`); every actual
  chat operation goes through `BrokenOaths.Chat`
  (`list_conversations/2`, `open_conversation/3`, `recent_messages/3`,
  `load_older_messages/4`, `send_message/4`, `unread_count/2`,
  `mark_read/3`, `block/3`), which itself is the sole authority on who
  counts as a reachable contact (`Chat.list_conversations/2` reads
  `Game.known_players/2` internally, story 899) — this component never
  calls `Game.known_players/2` directly. `BrokenOaths.Users.get_user!/1`
  resolves a contact's user id (all this component is ever given) back
  to the `User` struct `Chat`'s own functions require.

  ## Real-time delivery

  `Play` is the one subscribed to `Chat.subscribe/2` (a component has
  no mailbox of its own); on `{:chat_message, message}` it forwards the
  news in with `send_update(__MODULE__, id: "chat-panel", new_message:
  message)`, handled by this module's own `update/2` clause — a full,
  cheap re-fetch of contacts (and, if that contact's thread is the one
  currently open, the messages too — marking it read immediately since
  an open thread means the player already sees it) rather than trying
  to patch the single new message in by hand, the same "single source
  of truth, re-fetch on every signal" philosophy `Play.refresh_board/1`
  already uses for the board itself.

  ## Talking back to `Play`

  Opening/closing this panel is local state (`:open?`), but `Play`
  still needs to know when it changes so it can hide
  `GameLive.KnownPlayersPanel` while this one's own contact list is
  showing — both would otherwise render a `"known-player-ID"` row for
  the same contact at once, breaking the one-match-per-selector
  contract every `element/2` + `render_click/1` spec assertion depends
  on (the same "one side panel at a time" rule `Play`'s moduledoc
  already documents for unit/city selection). So `"toggle_chat"` also
  `send/2`s `{:chat_open_changed, open?}` to the parent LiveView
  process (components run in their parent's own process), which `Play`
  picks up in its own `handle_info/2`.

  ## Blocking

  `Chat.blocked?/3` is symmetric ("is there a block between these two,
  either direction") — exactly right for `Chat.send_message/4`'s own
  delivery gate, but wrong for deciding whose COMPOSER disappears: the
  player who did the blocking loses their own composer (replaced by
  `chat-blocked-notice`), but the player who got blocked keeps theirs
  (their form still renders — the message is just silently never
  delivered; `Chat` guarantees that, not this component). So
  `:blocked_by_me` tracks, per this component instance, which contacts
  THIS viewer has explicitly blocked through the `"block-player"`
  control here. It is seeded on mount (and only then —
  `assign_new/3` — so a later `update/2` within the same live session
  never clobbers a click the player just made) from
  `Chat.blocked_user_ids/2`, the DIRECTIONAL query ("whom did THIS
  viewer block", never the symmetric `blocked?/3`) — a page reload
  must find the block still enforced without the player having to
  re-click "block" to rediscover it.

  The `chat-blocked-notice` state also carries an `"unblock-player"`
  control (`"unblock_player"` event, `Chat.unblock/3`) that removes the
  contact from `:blocked_by_me`, restoring the composer — the notice's
  own copy already promises this is reversible.
  """

  use BrokenOathsWeb, :live_component

  alias BrokenOaths.Chat
  alias BrokenOaths.Chat.Message
  alias BrokenOaths.Users

  @impl true
  def update(%{new_message: %Message{}}, socket) do
    {:ok, refresh_after_incoming_message(socket)}
  end

  def update(%{id: id, world: world, user: user} = assigns, socket) do
    target_user_id = Map.get(assigns, :chat_target_user_id)

    socket =
      socket
      |> assign(id: id, world: world, user: user)
      |> assign_new(:open?, fn -> false end)
      |> assign_new(:selected_user_id, fn -> nil end)
      |> assign_new(:messages, fn -> [] end)
      |> assign_new(:error, fn -> nil end)
      |> assign_new(:blocked_by_me, fn -> Chat.blocked_user_ids(world, user) end)
      |> assign_new(:seen_target_user_id, fn -> nil end)
      |> refresh_contacts()

    {:ok, maybe_open_target(socket, target_user_id)}
  end

  @impl true
  def handle_event("toggle_chat", _params, socket) do
    open? = !socket.assigns.open?
    send(self(), {:chat_open_changed, open?})
    {:noreply, assign(socket, open?: open?)}
  end

  def handle_event("select_contact", %{"user_id" => user_id}, socket) do
    {:noreply, select_contact(socket, parse_id(user_id))}
  end

  def handle_event("send_message", %{"message" => %{"body" => body}}, socket) do
    %{world: world, user: user, selected_user_id: selected_user_id, messages: messages} =
      socket.assigns

    other_user = Users.get_user!(selected_user_id)

    case Chat.send_message(world, user, other_user, body) do
      {:ok, message} ->
        {:noreply, assign(socket, messages: messages ++ [message], error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error: chat_error_message(reason))}
    end
  end

  def handle_event("load_older", _params, socket) do
    {:noreply, load_older(socket)}
  end

  def handle_event("block_player", _params, socket) do
    %{world: world, user: user, selected_user_id: selected_user_id, blocked_by_me: blocked_by_me} =
      socket.assigns

    other_user = Users.get_user!(selected_user_id)

    case Chat.block(world, user, other_user) do
      {:ok, _block} ->
        {:noreply, assign(socket, blocked_by_me: MapSet.put(blocked_by_me, selected_user_id))}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("unblock_player", _params, socket) do
    %{world: world, user: user, selected_user_id: selected_user_id, blocked_by_me: blocked_by_me} =
      socket.assigns

    other_user = Users.get_user!(selected_user_id)
    :ok = Chat.unblock(world, user, other_user)

    {:noreply, assign(socket, blocked_by_me: MapSet.delete(blocked_by_me, selected_user_id))}
  end

  # -------------------------------------------------------------------
  # State transitions
  # -------------------------------------------------------------------

  defp maybe_open_target(socket, nil), do: socket

  defp maybe_open_target(socket, target_user_id) do
    if target_user_id == socket.assigns.seen_target_user_id do
      socket
    else
      socket
      |> assign(seen_target_user_id: target_user_id, open?: true)
      |> select_contact(target_user_id)
    end
  end

  defp select_contact(socket, user_id) do
    %{world: world, user: user} = socket.assigns
    other_user = Users.get_user!(user_id)

    case Chat.open_conversation(world, user, other_user) do
      {:ok, _conversation} ->
        Chat.mark_read(world, user, other_user)
        messages = Chat.recent_messages(world, user, other_user)

        socket
        |> assign(selected_user_id: user_id, messages: messages, error: nil)
        |> refresh_contacts()

      {:error, _reason} ->
        socket
    end
  end

  defp load_older(%{assigns: %{messages: []}} = socket), do: socket

  defp load_older(socket) do
    %{world: world, user: user, selected_user_id: selected_user_id, messages: [oldest | _]} =
      socket.assigns

    other_user = Users.get_user!(selected_user_id)
    older = Chat.load_older_messages(world, user, other_user, oldest)
    assign(socket, messages: older ++ socket.assigns.messages)
  end

  # A newly-arrived message always refreshes the contact list (unread
  # counts move); if it landed in the thread already open, that thread
  # is re-read too and marked read immediately — the player is looking
  # right at it.
  defp refresh_after_incoming_message(socket) do
    %{world: world, user: user, selected_user_id: selected_user_id} = socket.assigns
    socket = refresh_contacts(socket)

    case selected_user_id do
      nil ->
        socket

      user_id ->
        other_user = Users.get_user!(user_id)
        Chat.mark_read(world, user, other_user)
        messages = Chat.recent_messages(world, user, other_user)
        socket |> assign(messages: messages) |> refresh_contacts()
    end
  end

  defp refresh_contacts(socket) do
    %{world: world, user: user} = socket.assigns
    contacts = Chat.list_conversations(world, user)
    assign(socket, contacts: contacts, total_unread: Chat.unread_count(world, user))
  end

  defp chat_error_message(:not_discovered), do: "You haven't discovered this player yet."
  defp chat_error_message(:blocked), do: "You can't message this player."
  defp chat_error_message(%Ecto.Changeset{}), do: "Message must be 1–500 characters."

  defp parse_id(id) when is_integer(id), do: id
  defp parse_id(id) when is_binary(id), do: String.to_integer(id)

  # A message is "mine" if its sender's `user_id` matches the viewer's
  # own — `Chat.recent_messages/3`, `Chat.load_older_messages/4`, and
  # `Chat.send_message/4` all preload `sender_player`/`sender_player.
  # user` (or attach it directly for a just-sent message), so this
  # never triggers an extra query.
  defp own_message?(message, user), do: message.sender_player.user.id == user.id

  defp sender_label(message, user) do
    if own_message?(message, user), do: "You", else: message.sender_player.user.email
  end

  defp format_timestamp(naive_datetime), do: Calendar.strftime(naive_datetime, "%b %d, %H:%M")

  # -------------------------------------------------------------------
  # Render
  # -------------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :blocked?, MapSet.member?(assigns.blocked_by_me, assigns.selected_user_id))

    ~H"""
    <div id={@id} class="relative">
      <button
        type="button"
        data-test="chat-button"
        phx-click="toggle_chat"
        phx-target={@myself}
        class="btn btn-sm btn-ghost gap-1"
      >
        <.icon name="hero-chat-bubble-left-right" class="w-4 h-4" />
        <span :if={@total_unread > 0} data-test="chat-badge" class="badge badge-error badge-sm">
          {@total_unread}
        </span>
      </button>

      <div
        :if={@open?}
        data-test="chat-panel"
        class="card bg-base-200 shadow-xl w-80 absolute top-full right-0 mt-1 z-10 select-text [-webkit-touch-callout:default]"
      >
        <div class="card-body p-3 gap-2">
          <h3 class="card-title text-sm">Chat</h3>

          <div data-test="known-players-list" class="flex flex-col gap-1 max-h-40 overflow-y-auto">
            <p :if={@contacts == []} class="text-xs opacity-60">
              No discovered players yet.
            </p>

            <.contact_row
              :for={contact <- @contacts}
              contact={contact}
              selected?={contact.user_id == @selected_user_id}
              myself={@myself}
            />
          </div>

          <.thread
            :if={@selected_user_id}
            messages={@messages}
            error={@error}
            blocked?={@blocked?}
            user={@user}
            myself={@myself}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :contact, :map, required: true
  attr :selected?, :boolean, required: true
  attr :myself, :any, required: true

  defp contact_row(assigns) do
    ~H"""
    <button
      type="button"
      data-test={"known-player-#{@contact.user_id}"}
      phx-click="select_contact"
      phx-value-user_id={@contact.user_id}
      phx-target={@myself}
      class={[
        "flex items-center justify-between gap-2 text-sm rounded px-2 py-1 text-left",
        @selected? && "bg-base-300"
      ]}
    >
      <span class="truncate">{@contact.email}</span>
      <span
        :if={@contact.unread_count > 0}
        data-test={"unread-count-#{@contact.user_id}"}
        class="badge badge-error badge-sm"
      >
        {@contact.unread_count}
      </span>
    </button>
    """
  end

  attr :messages, :list, required: true
  attr :error, :string, default: nil
  attr :blocked?, :boolean, required: true
  attr :user, :any, required: true
  attr :myself, :any, required: true

  defp thread(assigns) do
    ~H"""
    <div data-test="chat-thread" class="flex flex-col gap-2 border-t border-base-300 pt-2">
      <button
        :if={@messages != []}
        type="button"
        data-test="chat-load-older"
        phx-click="load_older"
        phx-target={@myself}
        class="btn btn-ghost btn-xs w-full"
      >
        Load older messages
      </button>

      <div data-test="chat-messages" class="flex flex-col gap-1 max-h-48 overflow-y-auto text-sm">
        <div
          :for={message <- @messages}
          data-test="chat-message"
          class={["flex flex-col gap-0.5", own_message?(message, @user) && "items-end text-right"]}
        >
          <span class="text-[10px] opacity-60">
            {sender_label(message, @user)} · {format_timestamp(message.inserted_at)}
          </span>
          <p>{message.body}</p>
        </div>
      </div>

      <div :if={@error} data-test="chat-error" class="alert alert-error p-2 text-xs">
        {@error}
      </div>

      <p :if={@blocked?} data-test="chat-blocked-notice" class="text-xs opacity-60">
        You've blocked this player — unblock them to send messages again.
      </p>

      <button
        :if={@blocked?}
        type="button"
        data-test="unblock-player"
        phx-click="unblock_player"
        phx-target={@myself}
        class="btn btn-ghost btn-xs self-start"
      >
        Unblock
      </button>

      <form
        :if={!@blocked?}
        data-test="chat-form"
        phx-submit="send_message"
        phx-target={@myself}
        class="flex gap-1"
      >
        <input
          type="text"
          name="message[body]"
          data-test="chat-input"
          placeholder="Type a message…"
          autocomplete="off"
          class="input input-xs input-bordered flex-1"
        />
        <button type="submit" class="btn btn-xs">Send</button>
      </form>

      <button
        :if={!@blocked?}
        type="button"
        data-test="block-player"
        phx-click="block_player"
        phx-target={@myself}
        class="btn btn-ghost btn-xs text-error self-start"
      >
        Block
      </button>
    </div>
    """
  end
end
