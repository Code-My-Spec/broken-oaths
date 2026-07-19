defmodule BrokenOaths.Repo.Migrations.RoadCoexistsWithImprovements do
  use Ecto.Migration

  # QA issue 5656770d "Roads conflict with improvements" — a Road is a
  # movement/connectivity improvement, orthogonal to a tile's yield
  # improvement (Farm/Mine/Pasture), same as Civ 6's own "road sits
  # UNDER an improvement" convention. The old unique index on
  # `(world_id, tile_id)` allowed only ONE improvement of ANY kind per
  # tile, which is what blocked a Road from ever coexisting with a
  # Farm/Mine on the same tile. Scoping the uniqueness to
  # `(world_id, tile_id, kind)` instead allows at most one improvement
  # of EACH kind per tile — `BrokenOaths.Game.WorldServer`'s own
  # `validate_improvement_slot/3` still keeps Farm/Mine/Pasture mutually
  # exclusive with EACH OTHER (a tile still has only one YIELD
  # improvement slot); only a Road's own slot is independent of that.
  def change do
    drop unique_index(:game_improvements, [:world_id, :tile_id],
           name: :game_improvements_world_id_tile_id_index
         )

    create unique_index(:game_improvements, [:world_id, :tile_id, :kind])
  end
end
