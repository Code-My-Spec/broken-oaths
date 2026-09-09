defmodule BrokenOaths.Repo.Migrations.CreateOpenBorders do
  use Ecto.Migration

  def change do
    create table(:game_open_borders) do
      add :world_id, references(:worlds), null: false
      add :player_a_id, references(:game_players, on_delete: :delete_all), null: false
      add :player_b_id, references(:game_players, on_delete: :delete_all), null: false
      add :proposer_player_id, references(:game_players, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "proposed"

      timestamps()
    end

    create unique_index(:game_open_borders, [:world_id, :player_a_id, :player_b_id],
             name: :game_open_borders_world_player_a_player_b_index
           )
  end
end
