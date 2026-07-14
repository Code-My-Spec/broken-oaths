defmodule BrokenOaths.Game.Unit do
  @moduledoc """
  A unit on the board — type (lord/settler), owner, tile id, hp, movement points.

  One unit per hex is a hard rule enforced by the DB via a unique
  index on `(world_id, tile_id)`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Game.Player
  alias BrokenOaths.Worlds.World

  @type unit_type :: :lord | :settler

  @type t :: %__MODULE__{
          id: integer() | nil,
          type: unit_type() | nil,
          tile_id: integer() | nil,
          hp: integer() | nil,
          max_hp: integer() | nil,
          movement: integer() | nil,
          max_movement: integer() | nil,
          world_id: integer() | nil,
          player_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          player: Player.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_units" do
    field :type, Ecto.Enum, values: [:lord, :settler]
    field :tile_id, :integer
    field :hp, :integer
    field :max_hp, :integer
    field :movement, :integer
    field :max_movement, :integer

    belongs_to :world, World
    belongs_to :player, Player

    timestamps()
  end

  @doc false
  def changeset(unit, attrs) do
    unit
    |> cast(attrs, [
      :world_id,
      :player_id,
      :type,
      :tile_id,
      :hp,
      :max_hp,
      :movement,
      :max_movement
    ])
    |> validate_required([
      :world_id,
      :player_id,
      :type,
      :tile_id,
      :hp,
      :max_hp,
      :movement,
      :max_movement
    ])
    |> validate_number(:hp, greater_than: 0)
    |> validate_number(:max_hp, greater_than: 0)
    |> validate_number(:movement, greater_than_or_equal_to: 0)
    |> validate_number(:max_movement, greater_than_or_equal_to: 0)
    |> validate_hp_within_max()
    |> validate_movement_within_max()
    |> assoc_constraint(:world)
    |> assoc_constraint(:player)
    |> unique_constraint([:world_id, :tile_id], name: :game_units_world_id_tile_id_index)
  end

  defp validate_hp_within_max(changeset) do
    validate_field_within_max(changeset, :hp, :max_hp)
  end

  defp validate_movement_within_max(changeset) do
    validate_field_within_max(changeset, :movement, :max_movement)
  end

  defp validate_field_within_max(changeset, field, max_field) do
    value = get_field(changeset, field)
    max_value = get_field(changeset, max_field)

    if is_integer(value) and is_integer(max_value) and value > max_value do
      add_error(changeset, field, "must be less than or equal to #{max_field}")
    else
      changeset
    end
  end
end
