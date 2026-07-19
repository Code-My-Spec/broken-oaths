defmodule BrokenOaths.Repo.Migrations.CreateRebellionPacts do
  use Ecto.Migration

  # Story 916: the Pact of Broken Oaths record — a conspiracy binding
  # fellow vassals of ONE targeted lord to a shared strike turn. Roster
  # membership and secret per-member commitments live in the sibling
  # `game_rebellion_pact_members` table (next migration); this table
  # just carries the pact's own identity (world, targeted lord, opener,
  # strike turn, lifecycle status).
  def change do
    create table(:game_rebellion_pacts) do
      add :world_id, references(:worlds), null: false
      add :lord_player_id, references(:game_players, on_delete: :delete_all), null: false
      add :opener_player_id, references(:game_players, on_delete: :delete_all), null: false
      add :strike_turn, :integer, null: false
      add :status, :string, null: false, default: "forming"

      timestamps()
    end

    create index(:game_rebellion_pacts, [:world_id])

    # The lord needs to sense conspiracy "heat" aggregated across every
    # pact targeting them (criterion 7742) without ever reading a pact's
    # own roster/content.
    create index(:game_rebellion_pacts, [:lord_player_id])
  end
end
