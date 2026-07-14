defmodule BrokenOaths.Repo.Migrations.AddTurnTrackingToWorlds do
  use Ecto.Migration

  def change do
    alter table(:worlds) do
      add :turn, :integer, null: false, default: 0
      add :turn_started_at, :utc_datetime
    end
  end
end
