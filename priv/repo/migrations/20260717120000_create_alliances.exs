defmodule BrokenOaths.Repo.Migrations.CreateAlliances do
  use Ecto.Migration

  # Story 901: an explicit alliance between two players in a world,
  # proposed by one and accepted by the other. `player_a_id`/`player_b_id`
  # are stored in canonical (lowest id first) order by
  # `BrokenOaths.Game.Alliance.changeset/2` so at most one alliance row
  # ever exists per unordered pair per world, regardless of who proposed.
  def change do
    create table(:game_alliances) do
      add :world_id, references(:worlds), null: false
      add :player_a_id, references(:game_players, on_delete: :delete_all), null: false
      add :player_b_id, references(:game_players, on_delete: :delete_all), null: false
      add :proposer_player_id, references(:game_players, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "proposed"

      timestamps()
    end

    create index(:game_alliances, [:world_id])
    create index(:game_alliances, [:player_a_id])
    create index(:game_alliances, [:player_b_id])

    create unique_index(:game_alliances, [:world_id, :player_a_id, :player_b_id],
             name: :game_alliances_world_player_a_player_b_index
           )
  end
end
