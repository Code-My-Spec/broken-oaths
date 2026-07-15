defmodule BrokenOaths.Repo.Migrations.CreateCityLoopTables do
  use Ecto.Migration

  def change do
    create table(:game_cities) do
      add :world_id, references(:worlds), null: false
      add :player_id, references(:game_players, on_delete: :delete_all), null: false
      add :tile_id, :integer, null: false
      add :name, :string, null: false
      add :size, :integer, null: false, default: 1
      add :food, :integer, null: false, default: 0
      add :territory, {:array, :integer}, null: false, default: []
      add :worked_tiles, {:array, :integer}, null: false, default: []

      timestamps()
    end

    create index(:game_cities, [:world_id])
    create index(:game_cities, [:player_id])
    create unique_index(:game_cities, [:world_id, :tile_id])

    create table(:game_production_items) do
      add :city_id, references(:game_cities, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :banked, :integer, null: false, default: 0
      add :cost, :integer, null: false

      timestamps()
    end

    create index(:game_production_items, [:city_id])

    create table(:game_improvements) do
      add :world_id, references(:worlds), null: false
      add :tile_id, :integer, null: false
      add :kind, :string, null: false
      add :progress, :integer, null: false, default: 0
      add :status, :string, null: false, default: "building"
      add :builder_unit_id, references(:game_units, on_delete: :nilify_all)

      timestamps()
    end

    create index(:game_improvements, [:world_id])
    create unique_index(:game_improvements, [:world_id, :tile_id])
  end
end
