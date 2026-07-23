defmodule BrokenOaths.Repo.Migrations.AddAllowStewardProductionToPlayers do
  use Ecto.Migration

  # Playtest issue 340c1ad4 — the owner-controlled, EMPIRE-WIDE grant
  # gating whether ANY eligible steward may set THEIR production while
  # they're offline (`Feudal.Stewardship.queue_production/5`'s own new
  # gate, ahead of the existing constructive-only whitelist check).
  # Opt-in (defaults `false`): before this column existed, an eligible
  # steward could always set an offline owner's production with no
  # owner-side switch at all — this flips that to a GRANT the owner
  # must explicitly turn on, same "small, mutable Player field" status
  # `honor`/`bank_cap` already have (see `20260718130000`). Never
  # scoped to a single city — one flag covers the owner's ENTIRE
  # empire, mirroring `honor`'s own world-visible-figure-per-player
  # (not per-city) shape.
  def change do
    alter table(:game_players) do
      add :allow_steward_production, :boolean, null: false, default: false
    end
  end
end
