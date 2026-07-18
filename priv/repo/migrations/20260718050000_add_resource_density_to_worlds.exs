defmodule BrokenOaths.Repo.Migrations.AddResourceDensityToWorlds do
  use Ecto.Migration

  # Story 905 — per-world tile-resource density (sparse | standard |
  # dense), read by `BrokenOaths.Worlds.Resources.at/2` alongside
  # `world.seed` to place bonus resources deterministically at
  # generation time. Defaults to `standard`, the ~1-resource-per-12-
  # land-tiles mid setting (`.code_my_spec/knowledge/civ6_resources.md`
  # §3) — existing worlds created before this field existed simply get
  # the mid density rather than a null/undefined one.
  def change do
    alter table(:worlds) do
      add :resource_density, :string, null: false, default: "standard"
    end
  end
end
