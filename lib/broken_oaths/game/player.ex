defmodule BrokenOaths.Game.Player do
  @moduledoc """
  A user's presence in a world — claimed region, gold, joined-at turn.

  One row per (world, user); a player may join multiple worlds, but
  never the same world twice. `region_id` identifies a seed-derived
  region (see `BrokenOaths.Worlds.Regions`), not a database row.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Users.User
  alias BrokenOaths.Worlds.World

  @type t :: %__MODULE__{
          id: integer() | nil,
          region_id: integer() | nil,
          gold: integer(),
          joined_turn: integer() | nil,
          world_id: integer() | nil,
          user_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          user: User.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_players" do
    field :region_id, :integer
    field :gold, :integer, default: 50
    field :joined_turn, :integer
    # Story 896: the turn the fallen lord's heir arrives at the capital
    # — persisted so a WorldServer restart mid-wait can't lose the
    # lineage (QA issue 0b7e82cd). Nil when no heir is pending.
    field :heir_arrives_turn, :integer

    belongs_to :world, World
    belongs_to :user, User

    timestamps()
  end

  @doc false
  def changeset(player, attrs) do
    player
    |> cast(attrs, [:world_id, :user_id, :region_id, :gold, :joined_turn])
    |> validate_required([:world_id, :user_id, :region_id, :gold, :joined_turn])
    |> validate_number(:gold, greater_than_or_equal_to: 0)
    |> validate_number(:joined_turn, greater_than_or_equal_to: 0)
    |> assoc_constraint(:world)
    |> assoc_constraint(:user)
    |> unique_constraint([:world_id, :user_id], name: :game_players_world_id_user_id_index)
    |> unique_constraint([:world_id, :region_id], name: :game_players_world_id_region_id_index)
  end
end
