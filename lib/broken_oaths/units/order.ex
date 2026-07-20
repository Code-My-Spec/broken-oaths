defmodule BrokenOaths.Units.Order do
  @moduledoc """
  A queued order for the next turn boundary — unit, kind (move), path,
  validation state.

  `path` holds the remaining tile ids to traverse, in order. Only one
  active order per unit is allowed; re-queueing replaces it, which the
  DB enforces with a unique index on `unit_id`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Units.Unit

  @type kind :: :move
  @type status :: :pending | :interrupted

  @type t :: %__MODULE__{
          id: integer() | nil,
          kind: kind() | nil,
          path: [integer()],
          status: status(),
          unit_id: integer() | nil,
          unit: Unit.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_orders" do
    field :kind, Ecto.Enum, values: [:move]
    field :path, {:array, :integer}, default: []
    field :status, Ecto.Enum, values: [:pending, :interrupted], default: :pending

    belongs_to :unit, Unit

    timestamps()
  end

  @doc false
  def changeset(order, attrs) do
    order
    |> cast(attrs, [:unit_id, :kind, :path, :status])
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
