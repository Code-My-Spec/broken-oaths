defmodule BrokenOaths.Repo.Migrations.DropUnitTileUniquenessForCityGarrisons do
  use Ecto.Migration

  # Story 895: a city's own tile is now the game's one stacking
  # exception — up to 3 friendly military units, plus any number of
  # civilians, may share it (`BrokenOaths.Game.CityDefense.garrison_room?/2`).
  # The blanket `(world_id, tile_id)` uniqueness on `game_units`
  # (`Game.Unit`'s original moduledoc) can no longer hold globally, and
  # Postgres has no built-in "unique, except on these specific tiles"
  # constraint (the set of city tiles changes every time a city is
  # founded). Rather than a constantly-rewritten partial index, "one
  # unit per hex" moves entirely to the application layer, which
  # already re-derives and enforces it on every write path that can
  # move a unit:
  #
  #   * `WorldServer.occupied_by_own?/4` — queue-time: refuses a
  #     player's own second unit onto any tile, city garrisons excepted
  #   * `Turn.attempt_step/2`'s tick-time collision check — the SAME
  #     exception, applied to actual movement resolution (both the
  #     immediate `move_now/2` path and every later tick)
  #   * every OTHER player's unit was never allowed to share a tile in
  #     the first place (Turn's dynamic collision halts a mover before
  #     it steps onto ANY currently-occupied tile, city or not)
  #
  # `game_units_world_id_tile_id_index` is dropped outright; nothing
  # replaces it at the DB layer.
  def change do
    drop unique_index(:game_units, [:world_id, :tile_id], name: :game_units_world_id_tile_id_index)
  end
end
