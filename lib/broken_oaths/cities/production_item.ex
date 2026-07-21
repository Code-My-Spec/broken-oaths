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

  ## The `:type` Ecto.Enum — every buildable, kept in sync by hand

  This field's own `values:` list must name every atom
  `BrokenOaths.Cities.Production.buildable()` can produce, or
  `queue_production/4`'s own `Repo.insert()` rejects the changeset the
  instant a new buildable ships (story 930's Library/Ancient
  Walls/Barracks/Water Mill were missing from this list entirely until
  story 933 caught it while wiring in the Pyramids/Hanging Gardens
  wonders — no existing test exercised the real `queue_production/4`
  round trip for any of the four, only the pure, in-memory
  `Production.can_queue?/3`/`available_items/1` calls, so the gap went
  undetected). There is no automatic derivation from `Production`'s
  own catalog — this list is maintained by hand, the same way
  `BrokenOaths.Cities.City`'s own `buildings` Ecto.Enum is.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Cities.City

  @type item_type ::
          :settler
          | :worker
          | :warrior
          | :granary
          | :bronze_spearman
          | :archer
          | :galley
          | :library
          | :ancient_walls
          | :barracks
          | :water_mill
          | :pyramids
          | :hanging_gardens

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
      values: [
        :settler,
        :worker,
        :warrior,
        :granary,
        :bronze_spearman,
        :archer,
        :galley,
        :library,
        :ancient_walls,
        :barracks,
        :water_mill,
        :pyramids,
        :hanging_gardens
      ]

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
