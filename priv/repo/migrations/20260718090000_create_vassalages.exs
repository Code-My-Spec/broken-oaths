defmodule BrokenOaths.Repo.Migrations.CreateVassalages do
  use Ecto.Migration

  # Story 907: the player-to-player feudal relationship record, created
  # automatically the moment a capture leaves the defeated player with
  # zero free cities. Carries every forward-looking field the design
  # doc calls for from day one (tribute rate, Oath Strain, the secret
  # Hidden Agenda, and a jsonb bag for the reciprocal contract terms)
  # so the rebellion batch (§8) never needs to rebuild this table.
  def change do
    create table(:game_vassalages) do
      add :world_id, references(:worlds), null: false
      add :lord_player_id, references(:game_players, on_delete: :delete_all), null: false
      add :vassal_player_id, references(:game_players, on_delete: :delete_all), null: false
      add :tribute_rate, :float, null: false, default: 0.25
      add :oath_strain, :integer, null: false, default: 0
      add :hidden_agenda, :string
      add :contract_terms, :map, null: false, default: %{}
      add :status, :string, null: false, default: "active"

      timestamps()
    end

    create index(:game_vassalages, [:world_id])
    create index(:game_vassalages, [:lord_player_id])

    # A vassal serves exactly one lord at a time — at most one row per
    # (world, vassal) regardless of how many lords they've ever sworn to
    # across the world's history (a broken/superseded row would need a
    # different status, not a second active one for the same vassal).
    create unique_index(:game_vassalages, [:world_id, :vassal_player_id],
             name: :game_vassalages_world_id_vassal_player_id_index
           )
  end
end
