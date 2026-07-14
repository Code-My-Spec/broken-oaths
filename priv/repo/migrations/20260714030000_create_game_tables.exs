defmodule BrokenOaths.Repo.Migrations.CreateGameTables do
  use Ecto.Migration

  def change do
    create table(:game_players) do
      add :world_id, references(:worlds), null: false
      add :user_id, references(:users), null: false
      add :region_id, :integer, null: false
      add :gold, :integer, null: false, default: 50
      add :joined_turn, :integer, null: false

      timestamps()
    end

    create index(:game_players, [:world_id])
    create index(:game_players, [:user_id])
    create unique_index(:game_players, [:world_id, :user_id])
    create unique_index(:game_players, [:world_id, :region_id])

    create table(:game_units) do
      add :world_id, references(:worlds), null: false
      add :player_id, references(:game_players, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :tile_id, :integer, null: false
      add :hp, :integer, null: false
      add :max_hp, :integer, null: false
      add :movement, :integer, null: false
      add :max_movement, :integer, null: false

      timestamps()
    end

    create index(:game_units, [:world_id])
    create index(:game_units, [:player_id])
    create unique_index(:game_units, [:world_id, :tile_id])

    create table(:game_orders) do
      add :unit_id, references(:game_units, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :path, {:array, :integer}, null: false, default: []
      add :status, :string, null: false, default: "pending"

      timestamps()
    end

    create unique_index(:game_orders, [:unit_id])

    create table(:game_explorations) do
      add :world_id, references(:worlds), null: false
      add :player_id, references(:game_players, on_delete: :delete_all), null: false
      add :explored, {:array, :integer}, null: false, default: []

      timestamps()
    end

    create index(:game_explorations, [:world_id])
    create unique_index(:game_explorations, [:world_id, :player_id])
  end
end
