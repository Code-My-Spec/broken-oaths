defmodule BrokenOaths.Worlds.World do
  use Ecto.Schema
  import Ecto.Changeset

  schema "worlds" do
    field :name, :string
    field :seed, :integer
    field :frequency, :integer, default: 54
    field :status, :string, default: "active"
    field :turn, :integer, default: 0
    field :turn_started_at, :utc_datetime

    timestamps()
  end

  def changeset(world, attrs) do
    world
    |> cast(attrs, [:name, :seed, :frequency, :status, :turn, :turn_started_at])
    |> validate_required([:name, :seed])
    |> validate_number(:frequency, greater_than: 0, less_than_or_equal_to: 80)
    |> validate_number(:turn, greater_than_or_equal_to: 0)
    |> unique_constraint(:seed)
  end
end
