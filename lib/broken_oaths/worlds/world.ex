defmodule BrokenOaths.Worlds.World do
  use Ecto.Schema
  import Ecto.Changeset

  schema "worlds" do
    field :name, :string
    field :seed, :integer
    field :frequency, :integer, default: 54
    field :status, :string, default: "active"

    timestamps()
  end

  def changeset(world, attrs) do
    world
    |> cast(attrs, [:name, :seed, :frequency, :status])
    |> validate_required([:name, :seed])
    |> validate_number(:frequency, greater_than: 0, less_than_or_equal_to: 80)
    |> unique_constraint(:seed)
  end
end
