defmodule BrokenOaths.Repo.Migrations.AddTemporaryAndRebellionIdToGameUnits do
  use Ecto.Migration

  # Story 915: the temporary rebellion army spawned the moment a vassal
  # declares independence — sized by `BrokenOaths.Game.OathStrain.
  # rebellion_army_size/1` via `BrokenOaths.Game.Rebellion.Resolution.
  # army_size/1` — needs to be flagged so the story-919 lifecycle can
  # disband exactly those units (and only those) once the war ends.
  # `temporary` (default false) marks any such unit; `rebellion_id`
  # scopes it to the ONE `Rebellion` that raised it, so disbanding never
  # touches an ordinary, permanent unit and never guesses by player
  # alone (a player could, in principle, carry more than one ENDED
  # rebellion in their own history).
  def change do
    alter table(:game_units) do
      add :temporary, :boolean, null: false, default: false
      add :rebellion_id, references(:game_rebellions, on_delete: :nilify_all)
    end

    create index(:game_units, [:rebellion_id])
  end
end
