defmodule BrokenOaths.Chat.Message do
  @moduledoc """
  A single chat message within a `BrokenOaths.Chat.Conversation`
  (story 900): the sending player, the body text (capped at 500
  characters — "Text only, max 500 characters per message"), and
  `inserted_at`/`id`, which is the ordering key for a thread's history
  (see `id`'s doc below for why `id`, not `inserted_at`, is the actual
  pagination key `BrokenOaths.Chat` sorts on).

  `read_at` is a nullable read marker — `nil` until
  `BrokenOaths.Chat.mark_read/3` clears it for the recipient, set
  directly via `Repo.update_all` (not through this module's
  `changeset/2`, which only ever governs message creation) the same
  way `BrokenOaths.Game.WorldServer` bulk-updates `Exploration` rows.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Chat.Conversation
  alias BrokenOaths.Players.Player

  @body_max_length 500

  @type t :: %__MODULE__{
          id: integer() | nil,
          body: String.t() | nil,
          read_at: NaiveDateTime.t() | nil,
          conversation_id: integer() | nil,
          sender_player_id: integer() | nil,
          conversation: Conversation.t() | Ecto.Association.NotLoaded.t(),
          sender_player: Player.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "chat_messages" do
    field :body, :string
    field :read_at, :naive_datetime

    belongs_to :conversation, Conversation
    belongs_to :sender_player, Player

    timestamps()
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:conversation_id, :sender_player_id, :body])
    |> validate_required([:conversation_id, :sender_player_id, :body])
    |> validate_length(:body, min: 1, max: @body_max_length)
    |> assoc_constraint(:conversation)
    |> assoc_constraint(:sender_player)
  end
end
