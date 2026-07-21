defmodule BrokenOaths.Units.Order do
  @moduledoc """
  A queued order for the next turn boundary — unit, kind (move, or
  story 929's road_to), path, validation state.

  `path` holds the remaining tile ids to traverse, in order — for a
  `:move` order, that's a shrink-as-you-go queue (`Simulation.Turn.
  Movement.apply_orders/2` pops the head off as each step lands). A
  `:road_to` order (story 929) reuses this SAME column for a
  DIFFERENT, deliberately IMMUTABLE purpose: the full cheapest
  owned-territory route from the worker's tile at issue time through
  the destination (`Units.Unit.bfs_path/5`), never shrunk — see
  `BrokenOaths.Simulation.Turn.RoadBuilder`'s own moduledoc for why the
  walk-and-build state machine needs the whole route on hand every
  tick, not just what's left. Only one active order per unit is
  allowed, whichever kind; re-queueing replaces it, which the DB
  enforces with a unique index on `unit_id`.

  `hp_at_issue` (story 929) is `:road_to`-only: the worker's own HP the
  instant the order was issued, `nil` for a `:move` order. See
  `BrokenOaths.Simulation.Turn.RoadBuilder`'s own moduledoc for the
  "attacked mid-build cancels" rule it backs.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Units.Unit

  @type kind :: :move | :road_to
  @type status :: :pending | :interrupted

  @type t :: %__MODULE__{
          id: integer() | nil,
          kind: kind() | nil,
          path: [integer()],
          status: status(),
          hp_at_issue: integer() | nil,
          unit_id: integer() | nil,
          unit: Unit.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_orders" do
    field :kind, Ecto.Enum, values: [:move, :road_to]
    field :path, {:array, :integer}, default: []
    field :status, Ecto.Enum, values: [:pending, :interrupted], default: :pending
    field :hp_at_issue, :integer

    belongs_to :unit, Unit

    timestamps()
  end

  @doc false
  def changeset(order, attrs) do
    order
    |> cast(attrs, [:unit_id, :kind, :path, :status, :hp_at_issue])
    |> validate_required([:unit_id, :kind, :status])
    |> validate_path_not_empty()
    |> assoc_constraint(:unit)
    |> unique_constraint(:unit_id, name: :game_orders_unit_id_index)
  end

  # `validate_length/3` only runs against a registered change, and a
  # fresh struct's `path` already defaults to `[]` — assigning `[]`
  # again produces no change to validate. Check the resolved field
  # value directly instead so an empty path is always caught.
  defp validate_path_not_empty(changeset) do
    case get_field(changeset, :path) do
      path when is_list(path) and path != [] -> changeset
      _ -> add_error(changeset, :path, "should have at least 1 item(s)")
    end
  end
end
