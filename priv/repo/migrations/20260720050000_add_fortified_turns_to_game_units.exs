defmodule BrokenOaths.Repo.Migrations.AddFortifiedTurnsToGameUnits do
  use Ecto.Migration

  # Story 920 rework — Civ 6-style Fortify ramp: the boolean `fortified`
  # column above (an instant, flat +50%-of-base defensive bonus) becomes
  # a TURNS-HELD counter so the bonus ramps like Civ 6's own
  # +3-after-1-turn/+6-after-2-turns shape — `Units.Unit.fortify/3` sets
  # it to 1 (partial bonus) the instant it fires, `Simulation.Turn.
  # Movement.advance_fortify/1` bumps it to 2 (full bonus, capped there)
  # the first time the unit survives a whole turn boundary without
  # moving or attacking. Replaces the boolean column outright rather
  # than growing a second one alongside it — it shipped same-day,
  # nothing in production depends on it yet.
  def change do
    alter table(:game_units) do
      add :fortified_turns, :integer, null: false, default: 0
      remove :fortified, :boolean, default: false
    end
  end
end
