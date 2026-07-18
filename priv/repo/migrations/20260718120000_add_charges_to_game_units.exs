defmodule BrokenOaths.Repo.Migrations.AddChargesToGameUnits do
  use Ecto.Migration

  # Story 882 playtest update (issue 1caa87e9 — worker charges): a
  # worker (Civ 6 "Builder") is created with 3 build charges and spends
  # one per completed Farm/Mine, expending itself (removed from the
  # map) on its last charge; Roads are charge-exempt. Every unit type
  # gets the column (mirroring `hp`/`movement`, which are likewise
  # generic on `Game.Unit` even though only some types use them) but
  # only `:worker` ever decrements it — everything else simply carries
  # the default and is never read. Existing rows (any unit created
  # before this migration) default to 3, same as a freshly spawned one.
  def change do
    alter table(:game_units) do
      add :charges, :integer, null: false, default: 3
    end
  end
end
