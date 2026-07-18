defmodule BrokenOaths.Repo.Migrations.AddBankAndHonorFieldsToPlayers do
  use Ecto.Migration

  # Story 909 (Gold Bank) — `banked_gold` (current holdings) and
  # `bank_cap` (current capacity, raised by `Game.Bank.upgrade/1`) ride
  # the player row exactly like `gold` itself, same "small, mutable,
  # never cast through `Player.changeset/2`" status `barbarians_killed`/
  # `camps_destroyed` already have (see `20260718060000`). `bank_cap`
  # defaults to `Game.Bank.starting_cap/0`'s own literal (100) — kept a
  # plain migration literal rather than calling the function at
  # migration time, same "no compile-time coupling" discipline every
  # other default here already follows.
  #
  # Story 910 (Feudal Stewardship) — `honor`, the world-visible
  # reputation ledger the design doc calls for
  # (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Honor brake"):
  # this batch's only writer is `Game.Stewardship`'s provable-sabotage
  # penalty, but the column lives on `Player` (not scoped to
  # stewardship alone) since Honor is a general reputation figure future
  # batches (rebellion, garrison mercy/execution) will also read and
  # write. Starts at 100 — a neutral, positive reputation with headroom
  # to fall; no story in this batch reads any specific starting value,
  # only that it moves down on sabotage.
  def change do
    alter table(:game_players) do
      add :banked_gold, :integer, null: false, default: 0
      add :bank_cap, :integer, null: false, default: 100
      add :honor, :integer, null: false, default: 100
    end
  end
end
