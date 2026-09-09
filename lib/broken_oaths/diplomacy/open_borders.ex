defmodule BrokenOaths.Diplomacy.OpenBorders do
  @moduledoc """
  An explicit Open Borders agreement between two players in a world.

  Player pairs are canonicalized so only one agreement can exist for a pair.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Players.Player
  alias BrokenOaths.Repo
  alias BrokenOaths.Worlds.World

  @type status :: :proposed | :accepted
  @type player_id :: integer()

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

  schema "game_open_borders" do
    field :status, Ecto.Enum, values: [:proposed, :accepted], default: :proposed

    belongs_to :world, World
    belongs_to :player_a, Player
    belongs_to :player_b, Player
    belongs_to :proposer_player, Player

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(open_borders, attrs) do
    open_borders
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
      name: :game_open_borders_world_player_a_player_b_index
    )
  end

  @spec propose(map(), map(), map()) :: {:ok, t()} | {:error, atom() | Ecto.Changeset.t()}
  def propose(state, user, other_user) do
    with {:ok, proposer} <- fetch_player(state, user.id),
         {:ok, recipient} <- fetch_player(state, other_user.id),
         nil <- find(state.world.id, proposer.id, recipient.id),
         {:ok, agreement} <-
           %__MODULE__{}
           |> changeset(%{
             world_id: state.world.id,
             player_a_id: proposer.id,
             player_b_id: recipient.id,
             proposer_player_id: proposer.id
           })
           |> Repo.insert() do
      {:ok, agreement}
    else
      %__MODULE__{status: :proposed} -> {:error, :already_proposed}
      %__MODULE__{status: :accepted} -> {:error, :already_accepted}
      {:error, _operation, changeset, _changes} -> {:error, changeset}
      {:error, _} = error -> error
    end
  end

  @spec accept(map(), map(), map()) :: {:ok, t()} | {:error, atom() | Ecto.Changeset.t()}
  def accept(state, user, other_user) do
    with {:ok, accepting_player} <- fetch_player(state, user.id),
         {:ok, other_player} <- fetch_player(state, other_user.id),
         %__MODULE__{} = agreement <- find(state.world.id, accepting_player.id, other_player.id),
         :ok <- acceptor(agreement, accepting_player.id),
         {:ok, accepted} <- agreement |> changeset(%{status: :accepted}) |> Repo.update() do
      {:ok, accepted}
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  @spec revoke(map(), map(), map()) :: {:ok, t()} | {:error, atom()}
  def revoke(state, user, other_user) do
    with {:ok, revoking_player} <- fetch_player(state, user.id),
         {:ok, other_player} <- fetch_player(state, other_user.id),
         %__MODULE__{} = agreement <- find(state.world.id, revoking_player.id, other_player.id),
         :ok <- party(agreement, revoking_player.id),
         {:ok, deleted} <- Repo.delete(agreement) do
      {:ok, deleted}
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  @spec active?(term(), player_id(), player_id()) :: boolean()
  def active?(world_id, player_a_id, player_b_id) do
    case find(world_id, player_a_id, player_b_id) do
      %__MODULE__{status: :accepted} -> true
      _agreement -> false
    end
  end

  @spec find(term(), player_id(), player_id()) :: t() | nil
  def find(world_id, player_a_id, player_b_id) do
    {player_a_id, player_b_id} = canonical_pair(player_a_id, player_b_id)

    Repo.get_by(__MODULE__,
      world_id: world_id,
      player_a_id: player_a_id,
      player_b_id: player_b_id
    )
  end

  defp acceptor(%__MODULE__{status: :accepted}, _player_id), do: {:error, :already_accepted}

  defp acceptor(%__MODULE__{proposer_player_id: player_id}, player_id),
    do: {:error, :self_accept}

  defp acceptor(agreement, player_id), do: party(agreement, player_id)

  defp party(%__MODULE__{player_a_id: a, player_b_id: b}, player_id) when player_id in [a, b],
    do: :ok

  defp party(_agreement, _player_id), do: {:error, :not_a_party}

  defp fetch_player(state, user_id) do
    case Enum.find(Map.values(state.players), &(&1.user_id == user_id)) do
      nil -> {:error, :not_a_player}
      player -> {:ok, player}
    end
  end

  defp canonical_pair(a, b) when a <= b, do: {a, b}
  defp canonical_pair(a, b), do: {b, a}

  defp validate_distinct_players(changeset) do
    case {get_field(changeset, :player_a_id), get_field(changeset, :player_b_id)} do
      {player_id, player_id} when is_integer(player_id) ->
        add_error(changeset, :player_b_id, "can't be the same as player_a_id")

      _players ->
        changeset
    end
  end

  defp canonicalize_pair(changeset) do
    case {get_field(changeset, :player_a_id), get_field(changeset, :player_b_id)} do
      {a, b} when is_integer(a) and is_integer(b) and a > b ->
        changeset |> put_change(:player_a_id, b) |> put_change(:player_b_id, a)

      _players ->
        changeset
    end
  end

  defp validate_proposer_is_a_party(changeset) do
    proposer_player_id = get_field(changeset, :proposer_player_id)
    player_ids = [get_field(changeset, :player_a_id), get_field(changeset, :player_b_id)]

    case proposer_player_id in player_ids do
      true -> changeset
      false -> add_error(changeset, :proposer_player_id, "must be one of the agreement players")
    end
  end
end
