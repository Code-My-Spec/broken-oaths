defmodule BrokenOaths.Repo.Migrations.GlobeWorlds do
  use Ecto.Migration

  def change do
    alter table(:worlds) do
      # Goldberg polyhedron GP(f,0) subdivision frequency: 10f²+2 tiles.
      add :frequency, :integer, null: false, default: 54
      remove :width, :integer, default: 200
      remove :height, :integer, default: 150
    end
  end
end
