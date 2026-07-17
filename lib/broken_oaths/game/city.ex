defmodule BrokenOaths.Game.City do
  @moduledoc """
  A founded city — world/player/tile, a renameable name, accumulated
  food and size, claimed territory, and which territory tiles are
  currently worked. Persisted like units/orders: the `WorldServer`
  holds the canonical in-memory copy (see `BrokenOaths.Game.Turn`'s
  moduledoc for the tick-state contract) and diffs it against this
  table on each command/tick.

  `territory` is every tile this city has ever claimed — permanent,
  monotonically growing (founding ring, then one tile per growth; see
  `BrokenOaths.Game.Yields`). `worked_tiles` is the subset of
  `territory`, excluding the always-free `tile_id` center, that
  currently has a citizen assigned; it can be shorter than `size` when
  a citizen has been manually unassigned or lost its post (a settler's
  population cost un-works a tile without un-claiming it — story 883).

  The production queue lives in a separate table
  (`BrokenOaths.Game.ProductionItem`) rather than an embedded list:
  each item needs a stable, independently-addressable id for
  `cancel_production_item/4`, and insertion order (lowest id = head =
  current) is a natural fit for a `has_many`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Game.Player
  alias BrokenOaths.Game.ProductionItem
  alias BrokenOaths.Worlds.World

  @max_hp 100

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          tile_id: integer() | nil,
          size: pos_integer(),
          food: non_neg_integer(),
          territory: [integer()],
          worked_tiles: [integer()],
          hp: non_neg_integer(),
          production_halted_until: integer() | nil,
          world_id: integer() | nil,
          player_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          player: Player.t() | Ecto.Association.NotLoaded.t(),
          production_items: [ProductionItem.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_cities" do
    field :name, :string
    field :tile_id, :integer
    field :size, :integer, default: 1
    field :food, :integer, default: 0
    field :territory, {:array, :integer}, default: []
    field :worked_tiles, {:array, :integer}, default: []
    # Story 895 — see `BrokenOaths.Game.CityDefense` for the combat math
    # both fields back: `hp` (capped at 100, mirrors `game_camps.hp`)
    # and `production_halted_until` (nil until the city is ever
    # pillaged; the turn number its frozen production resumes at).
    field :hp, :integer, default: @max_hp
    field :production_halted_until, :integer

    belongs_to :world, World
    belongs_to :player, Player
    has_many :production_items, ProductionItem

    timestamps()
  end

  @doc false
  def changeset(city, attrs) do
    city
    |> cast(attrs, [
      :world_id,
      :player_id,
      :tile_id,
      :name,
      :size,
      :food,
      :territory,
      :worked_tiles,
      :hp,
      :production_halted_until
    ])
    |> validate_required([:world_id, :player_id, :tile_id, :name, :size, :food])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_number(:size, greater_than_or_equal_to: 1, less_than_or_equal_to: 4)
    |> validate_number(:food, greater_than_or_equal_to: 0)
    |> validate_number(:hp, greater_than_or_equal_to: 0, less_than_or_equal_to: @max_hp)
    |> validate_worked_tiles_within_size()
    |> assoc_constraint(:world)
    |> assoc_constraint(:player)
    |> unique_constraint([:world_id, :tile_id], name: :game_cities_world_id_tile_id_index)
  end

  # A citizen can be manually unassigned (worked_tiles shorter than
  # size) but never doubled up beyond one worked tile per pop.
  defp validate_worked_tiles_within_size(changeset) do
    size = get_field(changeset, :size)
    worked = get_field(changeset, :worked_tiles) || []

    if is_integer(size) and length(worked) > size do
      add_error(changeset, :worked_tiles, "cannot exceed size")
    else
      changeset
    end
  end
end
