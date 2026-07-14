defmodule BrokenOaths.Game.Exploration do
  @moduledoc """
  Per-player explored-tile mask for a world, persisted as part of the delta.

  `explored` holds explored tile ids as a flat list (batch-1
  representation; a bitmap is a future optimization). One row per
  (world, player).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Game.Player
  alias BrokenOaths.Worlds.World

  @type t :: %__MODULE__{
          id: integer() | nil,
          explored: [integer()],
          world_id: integer() | nil,
          player_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          player: Player.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_explorations" do
    field :explored, {:array, :integer}, default: []

    belongs_to :world, World
    belongs_to :player, Player

    timestamps()
  end

  @doc false
  def changeset(exploration, attrs) do
    exploration
    |> cast(attrs, [:world_id, :player_id, :explored])
    |> validate_required([:world_id, :player_id, :explored])
    |> assoc_constraint(:world)
    |> assoc_constraint(:player)
    |> unique_constraint([:world_id, :player_id],
      name: :game_explorations_world_id_player_id_index
    )
  end
end
