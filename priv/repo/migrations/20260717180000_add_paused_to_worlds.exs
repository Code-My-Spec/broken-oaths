defmodule BrokenOaths.Repo.Migrations.AddPausedToWorlds do
  use Ecto.Migration

  # Dev-only QA control surface: a paused world's turn clock never
  # advances on its own (`WorldServer`'s `:tick` handler no-ops, and
  # boot-time dormancy catch-up never replays missed turns) while
  # `:advance_turn` (the manual step) still works — see
  # `BrokenOaths.Game.WorldServer`'s ticking doc. Persisted so a paused
  # QA world stays frozen across a server restart.
  def change do
    alter table(:worlds) do
      add :paused, :boolean, null: false, default: false
    end
  end
end
