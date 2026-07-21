defmodule BrokenOaths.Repo.Migrations.AddBuildingsToGameCities do
  use Ecto.Migration

  # Story 930 — four new buildings (Library/Writing, Ancient Walls/Masonry,
  # Barracks/Bronze Working, Water Mill/The Wheel) land at once, so this
  # skips straight to the `buildings` list the Granary's own
  # `building_convention.md` already earmarks as the eventual home for
  # per-building booleans ("a future story can migrate the per-building
  # booleans to a `buildings` list without changing the catalog
  # contract") — four more `has_*` columns (plus their four parallel
  # `Ecto.Enum` clauses, `city_map/1` entries, `format_city/2` entries,
  # ...) would have been the exact scattered-boolean growth that doc
  # warns about. `has_granary` itself is untouched: every existing
  # Granary call site keeps working unchanged, this is purely additive.
  def change do
    alter table(:game_cities) do
      add :buildings, {:array, :string}, null: false, default: []
    end
  end
end
