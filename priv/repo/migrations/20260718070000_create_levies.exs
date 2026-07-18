defmodule BrokenOaths.Repo.Migrations.CreateLevies do
  use Ecto.Migration

  # Story 908: a call-to-arms pledge — the lord calls a vassal to send a
  # share of their standing army to a war against `target_player_id`.
  # There is no formal `War` entity yet, so the war is identified by its
  # target (the rival being fought); the vassal keeps command of the
  # pledged units and the war-duration binding (early pullout = refusal)
  # is enforced by `BrokenOaths.Game.Tribute`, not this table.
  def change do
    create table(:game_levies) do
      add :world_id, references(:worlds), null: false
      add :lord_player_id, references(:game_players, on_delete: :delete_all), null: false
      add :vassal_player_id, references(:game_players, on_delete: :delete_all), null: false
      add :target_player_id, references(:game_players, on_delete: :delete_all), null: false
      add :pledged_share, :float, null: false
      add :status, :string, null: false, default: "pending"

      timestamps()
    end

    create index(:game_levies, [:world_id])
    create index(:game_levies, [:lord_player_id])
    create index(:game_levies, [:vassal_player_id])
    create index(:game_levies, [:target_player_id])
  end
end
