defmodule BrokenOaths.Repo.Migrations.CreateRebellions do
  use Ecto.Migration

  # Stories 915/917/919: the first-class Rebellion record — "declared →
  # active → ended" (`.code_my_spec/knowledge/feudal_vassalage_design.md`,
  # "Round 2 — first-class Rebellion"). Created active the moment a
  # vassal declares independence (915, or via the story-917 "seize the
  # moment" prompt after their lord's death); carries which of the
  # rebel's occupied cities rose vs stayed loyal at that moment, the
  # size of the spawned temporary army, and settles exactly once into
  # `independence_won`, `crushed`, or `peace` (919).
  def change do
    create table(:game_rebellions) do
      add :world_id, references(:worlds), null: false
      add :rebel_player_id, references(:game_players, on_delete: :delete_all), null: false

      add :former_lord_player_id, references(:game_players, on_delete: :delete_all),
        null: false

      add :status, :string, null: false, default: "active"
      add :started_turn, :integer, null: false
      add :risen_city_ids, {:array, :integer}, null: false, default: []
      add :loyal_city_ids, {:array, :integer}, null: false, default: []
      add :army_size, :integer, null: false, default: 0

      # Only ever set once `status` becomes "peace" — see
      # `BrokenOaths.Game.Rebellion.Resolution.resolve_peace/3`: a peace
      # is a BINARY outcome (the rebel is restored as a vassal, or
      # granted full independence), never a third option.
      add :peace_outcome, :string
      add :reparations_gold, :integer

      timestamps()
    end

    # A rebel is assumed to carry at most one ACTIVE rebellion at a
    # time (an engine-level invariant the WorldServer enforces before
    # insert, not a DB constraint here — a rebel's own history may
    # still carry several ENDED rows over a world's lifetime). This
    # index is how a future read finds "this player's active rebellion"
    # without a table scan.
    create index(:game_rebellions, [:world_id, :rebel_player_id])

    # The former lord's own Vassals/rebellion panel looks up every
    # rebellion raised against their realm (active or historical).
    create index(:game_rebellions, [:world_id, :former_lord_player_id])
  end
end
