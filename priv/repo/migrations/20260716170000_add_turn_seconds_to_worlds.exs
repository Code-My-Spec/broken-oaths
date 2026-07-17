defmodule BrokenOaths.Repo.Migrations.AddTurnSecondsToWorlds do
  use Ecto.Migration

  # Story 897: each world picks its own turn-boundary cadence at
  # creation (a QA-fast world ticks every 5s; the default pace is the
  # existing 60s) instead of sharing one hardcoded length across every
  # world the process serves. Immutable after creation — see
  # `BrokenOaths.Worlds.World.creation_changeset/2`.
  def change do
    alter table(:worlds) do
      add :turn_seconds, :integer, null: false, default: 60
    end
  end
end
