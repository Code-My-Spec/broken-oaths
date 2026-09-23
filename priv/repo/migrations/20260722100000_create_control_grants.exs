defmodule BrokenOaths.Repo.Migrations.CreateControlGrants do
  use Ecto.Migration

  # Story 947: an owner's explicit, per-delegate delegated-control grant
  # (None/Defensive-only/Full, and for Full whether it's offline-only or
  # always-on). Directional -- the owner's grant to a delegate says nothing
  # about what that delegate has granted back (criterion 3153).
  def change do
    create table(:game_control_grants) do
      add :world_id, references(:worlds), null: false
      add :owner_player_id, references(:game_players, on_delete: :delete_all), null: false
      add :delegate_player_id, references(:game_players, on_delete: :delete_all), null: false
      add :level, :string, null: false, default: "none"
      add :mode, :string, null: false, default: "offline_only"

      timestamps()
    end

    create unique_index(:game_control_grants, [:world_id, :owner_player_id, :delegate_player_id],
             name: :game_control_grants_owner_delegate_index
           )
  end
end
