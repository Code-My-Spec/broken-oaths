defmodule BrokenOaths.Repo.Migrations.AddDurationToGameImprovements do
  use Ecto.Migration

  # Story 902, criterion 7628 — see `BrokenOaths.Game.Improvement`'s own
  # moduledoc ("Mining's 3-turn unlock") for why this is per-instance
  # rather than derived purely from `kind`: a Mine's actual target turns
  # depends on the building worker's OWNER's research at build-start,
  # resolved once and persisted here. Nullable — existing rows (and any
  # kind other than a research-gated one) simply fall back to
  # `Improvement.duration/1`'s hardcoded kind default.
  def change do
    alter table(:game_improvements) do
      add :duration, :integer
    end
  end
end
