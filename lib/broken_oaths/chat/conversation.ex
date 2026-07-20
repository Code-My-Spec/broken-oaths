defmodule BrokenOaths.Chat.Conversation do
  @moduledoc """
  A world-scoped 1:1 conversation between two players who have
  discovered each other (story 900).

  `player_a_id`/`player_b_id` hold the unordered pair in canonical
  (lowest id first) order — `changeset/2` normalizes whatever order the
  caller supplies, so at most one conversation row ever exists per
  {world, pair} regardless of who opened it first. Mirrors
  `BrokenOaths.Game.Alliance`'s canonicalization pattern.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Players.Player
  alias BrokenOaths.Worlds.World

  @type t :: %__MODULE__{
          id: integer() | nil,
          world_id: integer() | nil,
          player_a_id: integer() | nil,
          player_b_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          player_a: Player.t() | Ecto.Association.NotLoaded.t(),
          player_b: Player.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "chat_conversations" do
    belongs_to :world, World
    belongs_to :player_a, Player
    belongs_to :player_b, Player

    timestamps()
  end

  @doc false
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:world_id, :player_a_id, :player_b_id])
    |> validate_required([:world_id, :player_a_id, :player_b_id])
    |> validate_distinct_players()
    |> canonicalize_pair()
    |> assoc_constraint(:world)
    |> assoc_constraint(:player_a)
    |> assoc_constraint(:player_b)
    |> unique_constraint([:world_id, :player_a_id, :player_b_id],
      name: :chat_conversations_world_player_a_player_b_index
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
  # which order — or which of them — opened the conversation.
  defp canonicalize_pair(changeset) do
    case {get_field(changeset, :player_a_id), get_field(changeset, :player_b_id)} do
      {a, b} when is_integer(a) and is_integer(b) and a > b ->
        changeset |> put_change(:player_a_id, b) |> put_change(:player_b_id, a)

      _other ->
        changeset
    end
  end
end
