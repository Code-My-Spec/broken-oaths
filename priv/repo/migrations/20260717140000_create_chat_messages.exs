defmodule BrokenOaths.Repo.Migrations.CreateChatMessages do
  use Ecto.Migration

  # Story 900: a single chat message within a `chat_conversations` row —
  # sender, body (capped at 500 chars by
  # `BrokenOaths.Chat.Message.changeset/2`), and insertion order.
  def change do
    create table(:chat_messages) do
      add :conversation_id, references(:chat_conversations, on_delete: :delete_all), null: false
      add :sender_player_id, references(:game_players, on_delete: :delete_all), null: false
      add :body, :string, null: false

      timestamps()
    end

    create index(:chat_messages, [:conversation_id, :inserted_at])
    create index(:chat_messages, [:sender_player_id])
  end
end
