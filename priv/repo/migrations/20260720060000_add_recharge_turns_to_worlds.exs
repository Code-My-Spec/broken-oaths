defmodule BrokenOaths.Repo.Migrations.AddRechargeTurnsToWorlds do
  use Ecto.Migration

  # Split the tick (story 924): unit movement recharges every `recharge_turns`
  # economy ticks instead of every one. Default 2 -> movement refills every 2
  # minutes on the 60s economy tick, so the game stops feeling frantic while
  # cities/resources/build keep their pace. A per-world balance lever, like
  # turn_seconds. Existing worlds pick up the default on migrate.
  def change do
    alter table(:worlds) do
      add :recharge_turns, :integer, null: false, default: 2
    end
  end
end
