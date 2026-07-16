defmodule BrokenOaths.Repo.Migrations.AddPositionToProductionItems do
  use Ecto.Migration

  # Queue order becomes an explicit position (story 879: "queued items
  # can be reordered anytime") — previously implicit FIFO by id, which
  # made reordering impossible without breaking item identity.
  def up do
    alter table(:game_production_items) do
      add :position, :integer
    end

    execute "UPDATE game_production_items SET position = id"

    alter table(:game_production_items) do
      modify :position, :integer, null: false
    end
  end

  def down do
    alter table(:game_production_items) do
      remove :position
    end
  end
end
