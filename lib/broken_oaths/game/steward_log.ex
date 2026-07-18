defmodule BrokenOaths.Game.StewardLog do
  @moduledoc """
  A steward-action audit ledger entry (story 910): a single action a
  steward (the offline owner's lord, a fellow vassal of the same lord,
  or an allied peer) took on an offline owner's behalf — bank collect,
  production set, or emergency defense — the record the owner reviews
  on their own return.

  `sabotage` is the anti-grief consequence hook: `false` for an
  ordinary, constructive action; `true` once a review determines the
  action was actually harmful (e.g. a "constructive" build queued to
  waste the owner's production) — the fact `BrokenOaths.Game.
  Stewardship`'s own Honor-docking logic (a later wire-up; no story in
  this batch surfaces a Player Honor number yet) reads to decide whose
  reputation takes the hit.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Game.Player
  alias BrokenOaths.Worlds.World

  @type action :: :bank_collect | :production_set | :emergency_defense

  @type t :: %__MODULE__{
          id: integer() | nil,
          action: action(),
          details: map(),
          turn: integer() | nil,
          sabotage: boolean(),
          world_id: integer() | nil,
          steward_player_id: integer() | nil,
          owner_player_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          steward_player: Player.t() | Ecto.Association.NotLoaded.t(),
          owner_player: Player.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_steward_logs" do
    field :action, Ecto.Enum, values: [:bank_collect, :production_set, :emergency_defense]
    field :details, :map, default: %{}
    field :turn, :integer
    field :sabotage, :boolean, default: false

    belongs_to :world, World
    belongs_to :steward_player, Player
    belongs_to :owner_player, Player

    timestamps()
  end

  @doc false
  def changeset(steward_log, attrs) do
    steward_log
    |> cast(attrs, [
      :world_id,
      :steward_player_id,
      :owner_player_id,
      :action,
      :details,
      :turn,
      :sabotage
    ])
    |> validate_required([
      :world_id,
      :steward_player_id,
      :owner_player_id,
      :action,
      :turn
    ])
    |> validate_number(:turn, greater_than_or_equal_to: 0)
    |> validate_steward_and_owner_distinct()
    |> assoc_constraint(:world)
    |> assoc_constraint(:steward_player)
    |> assoc_constraint(:owner_player)
  end

  # A lord/fellow-vassal/ally never stewards their own household — the
  # steward and the owner being stewarded are always two distinct
  # players.
  defp validate_steward_and_owner_distinct(changeset) do
    steward_id = get_field(changeset, :steward_player_id)
    owner_id = get_field(changeset, :owner_player_id)

    if is_nil(steward_id) or is_nil(owner_id) or steward_id != owner_id do
      changeset
    else
      add_error(changeset, :owner_player_id, "can't be the same as the steward")
    end
  end
end
