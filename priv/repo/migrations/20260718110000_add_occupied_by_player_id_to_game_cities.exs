defmodule BrokenOaths.Repo.Migrations.AddOccupiedByPlayerIdToGameCities do
  use Ecto.Migration

  # Story 906: a city captured mid-siege stays on its original owner's
  # roster (peacetime rule — "owner runs it, lord skims") but is marked
  # `occupied_by_player_id` for the captor. `nil` means free — a city
  # this player owns that no other player occupies
  # (`BrokenOaths.Game.Siege.free?/1`). Zero free cities is the
  # last-free-city trigger story 907's `BrokenOaths.Game.Vassalization`
  # fires on.
  def change do
    alter table(:game_cities) do
      add :occupied_by_player_id, references(:game_players, on_delete: :nilify_all)
    end

    create index(:game_cities, [:occupied_by_player_id])
  end
end
