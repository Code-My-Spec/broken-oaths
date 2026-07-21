defmodule BrokenOaths.Repo.Migrations.AddEconomyTurnsToWorlds do
  use Ecto.Migration

  # Timer inversion (prod-critical tick change): movement now recharges
  # EVERY tick (the fast 1-minute action layer) instead of being gated
  # behind `recharge_turns` (which the previous migration added and this
  # one leaves untouched, now unused). The ECONOMY — improvement progress,
  # production, research, food/growth, and the gold income/upkeep sweep —
  # slows down instead, running only every `economy_turns` ticks. Default
  # 10 -> economy resolves every 10 minutes on the 60s tick. Existing
  # worlds pick up the default on migrate, same backfill-via-default
  # pattern `recharge_turns` itself used.
  def change do
    alter table(:worlds) do
      add :economy_turns, :integer, null: false, default: 10
    end
  end
end
