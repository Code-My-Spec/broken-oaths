defmodule BrokenOaths.Chat.Block do
  @moduledoc """
  A world-scoped block: `blocker_player` has blocked `blocked_player`
  (story 900). Stored directionally — only one row is ever written for
  the player who clicked "block" — but a block mutes messages in BOTH
  directions: `BrokenOaths.Chat` checks for a row in either direction
  before allowing delivery, the blocked player can't reach the blocker
  either. Mirrors `BrokenOaths.Game.KnownPlayer`'s directional storage
  pattern.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Players.Player
  alias BrokenOaths.Worlds.World

  @type t :: %__MODULE__{
          id: integer() | nil,
          world_id: integer() | nil,
          blocker_player_id: integer() | nil,
          blocked_player_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          blocker_player: Player.t() | Ecto.Association.NotLoaded.t(),
          blocked_player: Player.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "chat_blocks" do
    belongs_to :world, World
    belongs_to :blocker_player, Player
    belongs_to :blocked_player, Player

    timestamps()
  end

  @doc false
  def changeset(block, attrs) do
    block
    |> cast(attrs, [:world_id, :blocker_player_id, :blocked_player_id])
    |> validate_required([:world_id, :blocker_player_id, :blocked_player_id])
    |> validate_not_self_block()
    |> assoc_constraint(:world)
    |> assoc_constraint(:blocker_player)
    |> assoc_constraint(:blocked_player)
    |> unique_constraint([:world_id, :blocker_player_id, :blocked_player_id],
      name: :chat_blocks_world_blocker_blocked_index
    )
  end

  # A player can't block themselves — there is no self-conversation to mute.
  defp validate_not_self_block(changeset) do
    blocker_id = get_field(changeset, :blocker_player_id)
    blocked_id = get_field(changeset, :blocked_player_id)

    if is_nil(blocker_id) or is_nil(blocked_id) or blocker_id != blocked_id do
      changeset
    else
      add_error(changeset, :blocked_player_id, "can't be the same as the blocker")
    end
  end
end
