defmodule BrokenOaths.Repo.Migrations.CreateKnownPlayers do
  use Ecto.Migration

  # Story 899: a permanent, per-world discovery record — `viewer_player_id`
  # has discovered `discovered_player_id`'s civilization. Discovery is
  # mutual but stored directionally (one row per direction, see
  # `BrokenOaths.Game.Discovery`), so each player's own "Known Players"
  # list is a plain `where viewer_player_id = ^my_player.id` query.
  def change do
    create table(:game_known_players) do
      add :world_id, references(:worlds), null: false
      add :viewer_player_id, references(:game_players, on_delete: :delete_all), null: false
      add :discovered_player_id, references(:game_players, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:game_known_players, [:world_id])
    create index(:game_known_players, [:viewer_player_id])

    create unique_index(:game_known_players, [:world_id, :viewer_player_id, :discovered_player_id],
             name: :game_known_players_world_viewer_discovered_index
           )
  end
end
