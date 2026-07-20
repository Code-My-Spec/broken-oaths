defmodule BrokenOaths.Feudal.GoldLog do
  @moduledoc """
  A gold-transfer ledger entry both parties can see (story 908): a
  single movement of gold from one player to another on a given turn.

  This batch only writes `:tribute` entries (vassal → lord, per
  `BrokenOaths.Feudal.Tribute`), but `reason` is an `Ecto.Enum` so later
  stewardship/bank movements (909, 910) can add new reasons without a
  migration — the underlying column is a plain string.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Players.Player
  alias BrokenOaths.Worlds.World

  @type reason :: :tribute

  @type t :: %__MODULE__{
          id: integer() | nil,
          turn: integer() | nil,
          amount: integer() | nil,
          reason: reason(),
          world_id: integer() | nil,
          from_player_id: integer() | nil,
          to_player_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          from_player: Player.t() | Ecto.Association.NotLoaded.t(),
          to_player: Player.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_gold_logs" do
    field :turn, :integer
    field :amount, :integer
    field :reason, Ecto.Enum, values: [:tribute], default: :tribute

    belongs_to :world, World
    belongs_to :from_player, Player
    belongs_to :to_player, Player

    timestamps()
  end

  @doc false
  def changeset(gold_log, attrs) do
    gold_log
    |> cast(attrs, [:world_id, :from_player_id, :to_player_id, :turn, :amount, :reason])
    |> validate_required([:world_id, :from_player_id, :to_player_id, :turn, :amount, :reason])
    |> validate_number(:turn, greater_than_or_equal_to: 0)
    |> validate_number(:amount, greater_than_or_equal_to: 0)
    |> validate_distinct_players()
    |> assoc_constraint(:world)
    |> assoc_constraint(:from_player)
    |> assoc_constraint(:to_player)
  end

  # A gold movement always has two distinct parties.
  defp validate_distinct_players(changeset) do
    from_id = get_field(changeset, :from_player_id)
    to_id = get_field(changeset, :to_player_id)

    if is_nil(from_id) or is_nil(to_id) or from_id != to_id do
      changeset
    else
      add_error(changeset, :to_player_id, "can't be the same as the from player")
    end
  end
end
