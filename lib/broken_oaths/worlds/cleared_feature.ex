defmodule BrokenOaths.Worlds.ClearedFeature do
  @moduledoc """
  A chopped tile: `tile_id` in `world_id` has had its Woods/Rainforest
  feature permanently removed by a worker's Chop action (story 927
  "Workers chop woods and rainforest") — permanent once set, mirroring
  `BrokenOaths.Diplomacy.KnownPlayer`'s own "insert once, never removed"
  shape (there is no un-chop mechanic).

  Terrain itself is DERIVED from the world's seed (ADR
  game-state-persistence: never store derived terrain) — this table is
  the stored DELTA layered on top, the same "delta over derivation"
  shape `state.roads`/`state.improvements` already use for a Road/Farm/
  Mine built over bare terrain. `BrokenOaths.Worlds.Regions.terrain/3`
  is where the delta and the seed-derived struct get combined back into
  a single `Terrain.t()` for every state-aware reader (movement cost,
  a worker's own build-legality check, ...) to see `feature: nil`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Worlds.World

  @type t :: %__MODULE__{
          id: integer() | nil,
          world_id: integer() | nil,
          tile_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_cleared_features" do
    field :tile_id, :integer

    belongs_to :world, World

    timestamps()
  end

  @doc false
  def changeset(cleared_feature, attrs) do
    cleared_feature
    |> cast(attrs, [:world_id, :tile_id])
    |> validate_required([:world_id, :tile_id])
    |> assoc_constraint(:world)
    |> unique_constraint([:world_id, :tile_id])
  end
end
