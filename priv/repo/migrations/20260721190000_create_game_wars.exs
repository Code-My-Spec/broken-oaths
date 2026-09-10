defmodule BrokenOaths.Repo.Migrations.CreateGameWars do
  use Ecto.Migration

  def change do
    create table(:game_wars) do
      add :world_id, references(:worlds), null: false
      add :player_a_id, references(:game_players, on_delete: :delete_all), null: false
      add :player_b_id, references(:game_players, on_delete: :delete_all), null: false
      add :declarer_player_id, references(:game_players, on_delete: :delete_all), null: false
      add :peace_offered_by_player_id, references(:game_players, on_delete: :nilify_all)
      add :status, :string, null: false, default: "active"

      timestamps()
    end

    create unique_index(:game_wars, [:world_id, :player_a_id, :player_b_id],
             name: :game_wars_world_player_a_player_b_index
           )
  end
end
