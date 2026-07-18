defmodule BrokenOaths.Repo.Migrations.CreateGoldLogs do
  use Ecto.Migration

  # Story 908: a gold-transfer ledger entry both parties can see. This
  # batch only ever writes "tribute" rows (vassal -> lord), but `reason`
  # is a plain string column so later stewardship/bank movements (909,
  # 910) can add new `Ecto.Enum` values without a migration.
  def change do
    create table(:game_gold_logs) do
      add :world_id, references(:worlds), null: false
      add :from_player_id, references(:game_players, on_delete: :delete_all), null: false
      add :to_player_id, references(:game_players, on_delete: :delete_all), null: false
      add :turn, :integer, null: false
      add :amount, :integer, null: false
      add :reason, :string, null: false, default: "tribute"

      timestamps()
    end

    create index(:game_gold_logs, [:world_id])
    create index(:game_gold_logs, [:from_player_id])
    create index(:game_gold_logs, [:to_player_id])
  end
end
