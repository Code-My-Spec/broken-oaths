defmodule BrokenOaths.Repo.Migrations.CreateWorlds do
  use Ecto.Migration

  def change do
    create table(:worlds) do
      add :name, :string, null: false
      add :seed, :bigint, null: false
      add :width, :integer, default: 200
      add :height, :integer, default: 150
      add :status, :string, default: "active"

      timestamps()
    end

    create unique_index(:worlds, [:seed])
  end
end
