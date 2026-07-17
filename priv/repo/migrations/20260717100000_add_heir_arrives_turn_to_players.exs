defmodule BrokenOaths.Repo.Migrations.AddHeirArrivesTurnToPlayers do
  use Ecto.Migration

  # Story 896 / QA issue 0b7e82cd: the pending-heir schedule lived only
  # in WorldServer memory, so a restart during the 10-turn wait lost
  # the heir forever. The arrival turn now rides the player row.
  def change do
    alter table(:game_players) do
      add :heir_arrives_turn, :integer
    end
  end
end
