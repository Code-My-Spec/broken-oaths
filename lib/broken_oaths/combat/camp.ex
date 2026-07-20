defmodule BrokenOaths.Combat.Camp do
  @moduledoc """
  A barbarian camp on the board: which tile it sits on, its HP (capped
  at 100), a spawn counter counting turns toward its next warrior (see
  `BrokenOaths.Combat.Camps` for the cadence rules), and when it was
  destroyed (`nil` while it still stands). Persisted like units/cities —
  the `WorldServer` holds the canonical in-memory copy (see
  `BrokenOaths.Simulation.Turn`'s moduledoc for the tick-state contract) and
  diffs it against this table on each tick.

  A camp has no owning player: it's wilderness state, seeded once at a
  player's first founding (story 892) and never reassigned.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Worlds.World

  @max_hp 100

  @type t :: %__MODULE__{
          id: integer() | nil,
          tile_id: integer() | nil,
          hp: integer() | nil,
          spawn_counter: integer() | nil,
          destroyed_at: NaiveDateTime.t() | nil,
          world_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_camps" do
    field :tile_id, :integer
    field :hp, :integer, default: @max_hp
    field :spawn_counter, :integer, default: 0
    field :destroyed_at, :naive_datetime

    belongs_to :world, World

    timestamps()
  end

  @doc "A camp's max HP — every camp is founded at this value."
  @spec max_hp() :: pos_integer()
  def max_hp, do: @max_hp

  @doc false
  def changeset(camp, attrs) do
    camp
    |> cast(attrs, [:world_id, :tile_id, :hp, :spawn_counter, :destroyed_at])
    |> validate_required([:world_id, :tile_id, :hp, :spawn_counter])
    |> validate_number(:hp, greater_than_or_equal_to: 0, less_than_or_equal_to: @max_hp)
    |> validate_number(:spawn_counter, greater_than_or_equal_to: 0)
    |> assoc_constraint(:world)
    |> unique_constraint([:world_id, :tile_id], name: :game_camps_world_id_tile_id_index)
  end
end
