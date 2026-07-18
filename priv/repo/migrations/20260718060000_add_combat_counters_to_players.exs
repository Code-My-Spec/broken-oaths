defmodule BrokenOaths.Repo.Migrations.AddCombatCountersToPlayers do
  use Ecto.Migration

  # Story 904 — the progress panel's career totals ("Total barbarian
  # camps destroyed", "Total barbarians killed") need a running total
  # that survives a WorldServer restart, the same "small, rarely
  # changing, rides the player row" status `heir_arrives_turn` already
  # has. "Cities founded" needs no column of its own — no city is ever
  # deleted in this codebase, so a player's live city count already IS
  # their lifetime total (`length(Game.player_cities/2)`).
  def change do
    alter table(:game_players) do
      add :barbarians_killed, :integer, null: false, default: 0
      add :camps_destroyed, :integer, null: false, default: 0
    end
  end
end
