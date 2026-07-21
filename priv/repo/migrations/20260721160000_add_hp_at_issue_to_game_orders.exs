defmodule BrokenOaths.Repo.Migrations.AddHpAtIssueToGameOrders do
  use Ecto.Migration

  # Story 929 "Build road to a destination" — `:road_to` is a new
  # `Order.kind` (no DB-level check constraint on that column; it's a
  # plain string, so widening `BrokenOaths.Units.Order`'s own
  # `Ecto.Enum` values list needs no migration of its own). This column
  # is the one genuinely NEW piece of state a `:road_to` order carries
  # that a `:move` order never needed: the worker's own HP the instant
  # the order was issued, read back every tick by
  # `BrokenOaths.Simulation.Turn.RoadBuilder` to detect "attacked
  # mid-build" (any drop from this baseline cancels the order — see
  # that module's own moduledoc). Nullable: a `:move` order never sets
  # it.
  def change do
    alter table(:game_orders) do
      add :hp_at_issue, :integer
    end
  end
end
