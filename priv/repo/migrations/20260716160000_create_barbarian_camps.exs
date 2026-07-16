defmodule BrokenOaths.Repo.Migrations.CreateBarbarianCamps do
  use Ecto.Migration

  # Story 892: barbarian camps spawn near a player's first city and
  # periodically breed hostile warriors. Camps get their own table
  # (mirrors game_cities); their warriors are ordinary `game_units` rows
  # with a `nil` player_id (the barbarian seam `Game.Combat.hostile?/2`
  # already recognizes) tagged with `camp_id` so the spawn loop can
  # count "alive warriors per camp" and cap it at 2.
  def change do
    create table(:game_camps) do
      add :world_id, references(:worlds), null: false
      add :tile_id, :integer, null: false
      add :hp, :integer, null: false, default: 100
      add :spawn_counter, :integer, null: false, default: 0
      add :destroyed_at, :naive_datetime

      timestamps()
    end

    create index(:game_camps, [:world_id])
    create unique_index(:game_camps, [:world_id, :tile_id])

    alter table(:game_units) do
      # `modify` with a fresh `references(...)` tries to (re)create the
      # `game_units_player_id_fkey` constraint that already exists from
      # `create_game_tables` — Postgres rejects the duplicate. Only
      # nullability needs to change here; the FK itself (and its
      # `on_delete: :delete_all`) is untouched by dropping NOT NULL.
      modify :player_id, :bigint, null: true
      add :camp_id, references(:game_camps, on_delete: :nilify_all)
    end

    create index(:game_units, [:camp_id])
  end
end
