defmodule BrokenOaths.Repo.Migrations.AddDefenseFieldsToCities do
  use Ecto.Migration

  # Story 895: a city's own HP (max 100, mirrors `game_camps.hp`) and
  # the turn a pillaged city's frozen production resumes at (nil until
  # the city is ever pillaged — see `BrokenOaths.Game.CityDefense`
  # for the combat math both fields back).
  def change do
    alter table(:game_cities) do
      add :hp, :integer, null: false, default: 100
      add :production_halted_until, :integer
    end
  end
end
