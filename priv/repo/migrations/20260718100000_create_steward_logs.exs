defmodule BrokenOaths.Repo.Migrations.CreateStewardLogs do
  use Ecto.Migration

  # Story 910: the steward-action audit ledger an offline owner reviews
  # on return — every bank collect, production set, or emergency
  # defense a steward takes on their behalf, plus a `sabotage` flag the
  # Honor consequence hangs off (`BrokenOaths.Game.Player.honor` this
  # batch does not add — provable sabotage is only ever recorded here
  # in THIS foundation batch; docking Honor over it is a later wire-up).
  def change do
    create table(:game_steward_logs) do
      add :world_id, references(:worlds), null: false
      add :steward_player_id, references(:game_players, on_delete: :delete_all), null: false
      add :owner_player_id, references(:game_players, on_delete: :delete_all), null: false
      add :action, :string, null: false
      add :details, :map, null: false, default: %{}
      add :turn, :integer, null: false
      add :sabotage, :boolean, null: false, default: false

      timestamps()
    end

    create index(:game_steward_logs, [:world_id])
    create index(:game_steward_logs, [:owner_player_id])
    create index(:game_steward_logs, [:steward_player_id])
  end
end
