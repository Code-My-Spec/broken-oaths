defmodule BrokenOaths.Repo.Migrations.RescaleUnitHpTo100PointScale do
  @moduledoc """
  Story 881 rescales every unit's HP onto a common 100-point scale
  (Lord 150 / Settler 50 / Warrior 100 / Worker 10) so a completed
  Warrior's 100 HP is meaningful next to existing units. Lords and
  Settlers previously spawned at 20 and 10 max HP (see `Spawner`
  callers predating this migration) — rescale any such row
  proportionally onto its new max, leaving already-migrated or
  hand-seeded rows alone.
  """

  use Ecto.Migration

  def up do
    execute("""
    UPDATE game_units
    SET hp = GREATEST(1, ROUND(hp::numeric / max_hp::numeric * 150)),
        max_hp = 150
    WHERE type = 'lord' AND max_hp = 20
    """)

    execute("""
    UPDATE game_units
    SET hp = GREATEST(1, ROUND(hp::numeric / max_hp::numeric * 50)),
        max_hp = 50
    WHERE type = 'settler' AND max_hp = 10
    """)
  end

  def down do
    execute("""
    UPDATE game_units
    SET hp = GREATEST(1, ROUND(hp::numeric / max_hp::numeric * 20)),
        max_hp = 20
    WHERE type = 'lord' AND max_hp = 150
    """)

    execute("""
    UPDATE game_units
    SET hp = GREATEST(1, ROUND(hp::numeric / max_hp::numeric * 10)),
        max_hp = 10
    WHERE type = 'settler' AND max_hp = 50
    """)
  end
end
