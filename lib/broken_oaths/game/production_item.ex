defmodule BrokenOaths.Game.ProductionItem do
  @moduledoc """
  One entry in a city's production queue — what's being built, how much
  production is banked toward it, and its total cost. The lowest-id
  item for a city is the current (head) item; `BrokenOaths.Game.Production`
  accrues into it each turn and, once `banked >= cost`, resolves it into
  a spawned unit.

  Reordering the queue is free (story 879); this schema has no explicit
  position column because items are only ever appended at the tail or
  removed by id — the auto-increment id already gives a stable FIFO
  order without one.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Game.City

  @type item_type :: :settler | :worker | :warrior

  @type t :: %__MODULE__{
          id: integer() | nil,
          type: item_type() | nil,
          banked: non_neg_integer(),
          cost: pos_integer() | nil,
          city_id: integer() | nil,
          city: City.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_production_items" do
    field :type, Ecto.Enum, values: [:settler, :worker, :warrior]
    field :banked, :integer, default: 0
    field :cost, :integer

    belongs_to :city, City

    timestamps()
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:city_id, :type, :banked, :cost])
    |> validate_required([:city_id, :type, :banked, :cost])
    |> validate_number(:banked, greater_than_or_equal_to: 0)
    |> validate_number(:cost, greater_than: 0)
    |> assoc_constraint(:city)
  end
end
