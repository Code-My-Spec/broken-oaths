defmodule BrokenOaths.Repo.Migrations.CreateRebellionPactMembers do
  use Ecto.Migration

  # Story 916: per-conspirator rows for a `game_rebellion_pacts` row.
  # Membership of a pact IS the conspiracy roster; `commit_status` is
  # each member's own SECRET answer (never surfaced to the lord or to
  # fellow members before the strike turn — a read-layer rule, not a
  # storage one) and `informer` flags a member who has betrayed the
  # plot to the lord for a reward, an identity kept equally hidden from
  # every other member.
  def change do
    create table(:game_rebellion_pact_members) do
      add :rebellion_pact_id, references(:game_rebellion_pacts, on_delete: :delete_all),
        null: false

      add :player_id, references(:game_players, on_delete: :delete_all), null: false
      add :commit_status, :string, null: false, default: "invited"
      add :informer, :boolean, null: false, default: false

      timestamps()
    end

    # A vassal is assumed to belong to at most one ACTIVE pact at a
    # time (see `RebellionPact`'s own moduledoc) — this index is how a
    # future read finds "this player's active pact" without a table
    # scan, joining back to `game_rebellion_pacts.status`.
    create index(:game_rebellion_pact_members, [:player_id])

    # At most one row per (pact, player) — a member is invited into a
    # given pact exactly once.
    create unique_index(:game_rebellion_pact_members, [:rebellion_pact_id, :player_id],
             name: :game_rebellion_pact_members_pact_id_player_id_index
           )
  end
end
