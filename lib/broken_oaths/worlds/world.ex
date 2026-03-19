defmodule BrokenOaths.Worlds.World do
  use Ecto.Schema
  import Ecto.Changeset

  schema "worlds" do
    field :name, :string
    field :seed, :integer
    field :width, :integer, default: 200
    field :height, :integer, default: 150
    field :status, :string, default: "active"

    timestamps()
  end

  def changeset(world, attrs) do
    world
    |> cast(attrs, [:name, :seed, :width, :height, :status])
    |> validate_required([:name, :seed])
    |> unique_constraint(:seed)
  end
end
