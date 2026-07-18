defmodule BrokenOaths.Repo.Migrations.CreatePlayerResearch do
  use Ecto.Migration

  # Story 902: one research row per (world, player) — see
  # `BrokenOaths.Game.PlayerResearch`'s own moduledoc for why
  # `banked_science` is a bare jsonb map rather than a normalized table
  # (four Stone Age techs is the entire MVP scope; `BrokenOaths.Game.Research`
  # owns the string<->atom key boundary at the jsonb round trip).
  def change do
    create table(:game_player_research) do
      add :world_id, references(:worlds), null: false
      add :player_id, references(:game_players, on_delete: :delete_all), null: false
      add :completed_techs, {:array, :string}, null: false, default: []
      add :current_research, :string
      add :banked_science, :map, null: false, default: %{}

      timestamps()
    end

    create index(:game_player_research, [:world_id])

    create unique_index(:game_player_research, [:world_id, :player_id],
             name: :game_player_research_world_id_player_id_index
           )
  end
end
