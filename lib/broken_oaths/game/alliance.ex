defmodule BrokenOaths.Game.Alliance do
  @moduledoc """
  An explicit alliance between two players in a world (story 901):
  proposed by one of them, accepted by the other, for coordinating
  against shared barbarian targets.

  `player_a_id`/`player_b_id` hold the unordered pair in canonical
  (lowest id first) order — `changeset/2` normalizes whatever order the
  caller supplies, so at most one alliance row ever exists per pair per
  world regardless of who proposed. `proposer_player_id` is always one
  of the two and records who initiated the proposal; the OTHER player
  is the one who must accept it (see `BrokenOaths.Game.Cooperation` for
  the propose/accept business rules built on top of this schema).

  Note: `BrokenOaths.Game.Cooperation`'s proportional bounty split on a
  shared barbarian kill/camp destruction does NOT require an accepted
  (or even proposed) alliance between the participants — cooperation is
  emergent from shared targeting, not gated behind this record. An
  alliance is a player-facing coordination signal (a future
  `AlliancePanel`/chat surface), not a precondition for splitting gold.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Game.Player
  alias BrokenOaths.Worlds.World

  @type status :: :proposed | :accepted

  @type t :: %__MODULE__{
          id: integer() | nil,
          status: status(),
          world_id: integer() | nil,
          player_a_id: integer() | nil,
          player_b_id: integer() | nil,
          proposer_player_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          player_a: Player.t() | Ecto.Association.NotLoaded.t(),
          player_b: Player.t() | Ecto.Association.NotLoaded.t(),
          proposer_player: Player.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_alliances" do
    field :status, Ecto.Enum, values: [:proposed, :accepted], default: :proposed

    belongs_to :world, World
    belongs_to :player_a, Player
    belongs_to :player_b, Player
    belongs_to :proposer_player, Player

    timestamps()
  end

  @doc false
  def changeset(alliance, attrs) do
    alliance
    |> cast(attrs, [:world_id, :player_a_id, :player_b_id, :proposer_player_id, :status])
    |> validate_required([:world_id, :player_a_id, :player_b_id, :proposer_player_id, :status])
    |> validate_distinct_players()
    |> canonicalize_pair()
    |> validate_proposer_is_a_party()
    |> assoc_constraint(:world)
    |> assoc_constraint(:player_a)
    |> assoc_constraint(:player_b)
    |> assoc_constraint(:proposer_player)
    |> unique_constraint([:world_id, :player_a_id, :player_b_id],
      name: :game_alliances_world_player_a_player_b_index
    )
  end

  defp validate_distinct_players(changeset) do
    player_a_id = get_field(changeset, :player_a_id)
    player_b_id = get_field(changeset, :player_b_id)

    if is_nil(player_a_id) or is_nil(player_b_id) or player_a_id != player_b_id do
      changeset
    else
      add_error(changeset, :player_b_id, "can't be the same as player_a_id")
    end
  end

  # Normalizes the unordered pair to (lowest id, highest id) so the same
  # two players always collide against the same unique index no matter
  # which order — or which of them — proposed.
  defp canonicalize_pair(changeset) do
    case {get_field(changeset, :player_a_id), get_field(changeset, :player_b_id)} do
      {a, b} when is_integer(a) and is_integer(b) and a > b ->
        changeset |> put_change(:player_a_id, b) |> put_change(:player_b_id, a)

      _other ->
        changeset
    end
  end

  defp validate_proposer_is_a_party(changeset) do
    proposer_id = get_field(changeset, :proposer_player_id)
    party_ids = [get_field(changeset, :player_a_id), get_field(changeset, :player_b_id)]

    if is_nil(proposer_id) or proposer_id in party_ids do
      changeset
    else
      add_error(changeset, :proposer_player_id, "must be one of the allied players")
    end
  end
end
