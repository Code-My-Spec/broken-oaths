defmodule BrokenOaths.Repo.Migrations.CreateChatBlocks do
  use Ecto.Migration

  # Story 900: `blocker_player_id` has blocked `blocked_player_id` in a
  # world. Stored directionally (one row per block, see
  # `BrokenOaths.Chat.Block`), but `BrokenOaths.Chat` checks for a row
  # in EITHER direction before allowing delivery — a block mutes both
  # sides of the conversation.
  def change do
    create table(:chat_blocks) do
      add :world_id, references(:worlds), null: false
      add :blocker_player_id, references(:game_players, on_delete: :delete_all), null: false
      add :blocked_player_id, references(:game_players, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:chat_blocks, [:world_id])
    create index(:chat_blocks, [:blocked_player_id])

    create unique_index(:chat_blocks, [:world_id, :blocker_player_id, :blocked_player_id],
             name: :chat_blocks_world_blocker_blocked_index
           )
  end
end
