defmodule BrokenOaths.Cities.ProductionItem do
  @moduledoc """
  One entry in a city's production queue — what's being built, how much
  production is banked toward it, and its total cost. The lowest-id
  item for a city is the current (head) item; `BrokenOaths.Cities.Production`
  accrues into it each turn and, once `banked >= cost`, resolves it —
  into a spawned unit for `:settler`/`:worker`/`:warrior`, or (story
  902) into the city's own `has_granary` flag flipping for `:granary`,
  a BUILDING with no unit/tile to land on.

  Reordering the queue is free (story 879): items carry an explicit
  `position` (lowest = current/head), appended at max+1 and swapped by
  `WorldServer.do_reorder_production_item/4`. Item identity (and its
  banked progress) never moves — only positions swap.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Cities.City

  @type item_type ::
          :settler | :worker | :warrior | :granary | :bronze_spearman | :archer | :galley

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
    field :type, Ecto.Enum,
      values: [:settler, :worker, :warrior, :granary, :bronze_spearman, :archer, :galley]

    field :banked, :integer, default: 0
    field :position, :integer
    field :cost, :integer

    belongs_to :city, City

    timestamps()
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:city_id, :type, :banked, :cost, :position])
    |> validate_required([:city_id, :type, :banked, :cost, :position])
    |> validate_number(:banked, greater_than_or_equal_to: 0)
    |> validate_number(:cost, greater_than: 0)
    |> assoc_constraint(:city)
  end
end
