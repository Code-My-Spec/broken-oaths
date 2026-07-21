defmodule BrokenOaths.Repo.Migrations.CreateGameClearedFeatures do
  use Ecto.Migration

  # Story 927 "Workers chop woods and rainforest" — terrain is DERIVED
  # from the world's seed (ADR game-state-persistence: never store
  # derived terrain), so a chopped tile's own "the feature is gone" fact
  # needs a STORED DELTA over that seed, the exact same shape
  # `game_known_players` already established for a permanent, insert-
  # only fact scoped to a world (see `BrokenOaths.Worlds.ClearedFeature`'s
  # own moduledoc): one row per chopped tile, world-scoped, never
  # removed or updated — there's no "un-chop" mechanic.
  def change do
    create table(:game_cleared_features) do
      add :world_id, references(:worlds, on_delete: :delete_all), null: false
      add :tile_id, :integer, null: false

      timestamps()
    end

    create unique_index(:game_cleared_features, [:world_id, :tile_id])
  end
end
