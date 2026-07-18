defmodule BrokenOaths.Repo.Migrations.AddHasGranaryToGameCities do
  use Ecto.Migration

  # Story 902, criterion 7629 — Pottery's Granary unlock: a one-time
  # buildable (see `BrokenOaths.Game.Production`'s `:granary` catalog
  # entry) that grants +2 food storage once completed
  # (`BrokenOaths.Game.Yields.accrue_food/3`). A flag rather than a
  # `has_many` — there is exactly one Granary per city, ever (see
  # `Production.can_queue?/3`'s `:already_built` guard).
  def change do
    alter table(:game_cities) do
      add :has_granary, :boolean, null: false, default: false
    end
  end
end
