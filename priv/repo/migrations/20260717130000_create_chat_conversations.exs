defmodule BrokenOaths.Repo.Migrations.CreateChatConversations do
  use Ecto.Migration

  # Story 900: a world-scoped 1:1 conversation between two players who
  # have discovered each other. `player_a_id`/`player_b_id` are stored
  # in canonical (lowest id first) order by
  # `BrokenOaths.Chat.Conversation.changeset/2` so at most one
  # conversation row ever exists per unordered pair per world.
  def change do
    create table(:chat_conversations) do
      add :world_id, references(:worlds), null: false
      add :player_a_id, references(:game_players, on_delete: :delete_all), null: false
      add :player_b_id, references(:game_players, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:chat_conversations, [:world_id])
    create index(:chat_conversations, [:player_a_id])
    create index(:chat_conversations, [:player_b_id])

    create unique_index(:chat_conversations, [:world_id, :player_a_id, :player_b_id],
             name: :chat_conversations_world_player_a_player_b_index
           )
  end
end
