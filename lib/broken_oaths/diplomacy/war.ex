defmodule BrokenOaths.Diplomacy.War do
  @moduledoc """
  The active wartime relationship between two players in a world.

  Player pairs are stored in canonical order so a world can have at most one
  active war for a pair of players. A peace offer is recorded on the war and
  must be accepted by the other party before the relationship ends.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias BrokenOaths.Players.Player
  alias BrokenOaths.Repo
  alias BrokenOaths.Worlds.World

  @type status :: :active | :peace_offered

  @type t :: %__MODULE__{
          id: integer() | nil,
          status: status(),
          world_id: integer() | nil,
          player_a_id: integer() | nil,
          player_b_id: integer() | nil,
          declarer_player_id: integer() | nil,
          peace_offered_by_player_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          player_a: Player.t() | Ecto.Association.NotLoaded.t(),
          player_b: Player.t() | Ecto.Association.NotLoaded.t(),
          declarer_player: Player.t() | Ecto.Association.NotLoaded.t(),
          peace_offered_by_player: Player.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_wars" do
    field :status, Ecto.Enum, values: [:active, :peace_offered], default: :active

    belongs_to :world, World
    belongs_to :player_a, Player
    belongs_to :player_b, Player
    belongs_to :declarer_player, Player
    belongs_to :peace_offered_by_player, Player

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(war, attrs) do
    war
    |> cast(attrs, [
      :world_id,
      :player_a_id,
      :player_b_id,
      :declarer_player_id,
      :peace_offered_by_player_id,
      :status
    ])
    |> validate_required([:world_id, :player_a_id, :player_b_id, :declarer_player_id, :status])
    |> validate_distinct_players()
    |> canonicalize_pair()
    |> validate_party(:declarer_player_id, "must be one of the wartime players")
    |> validate_optional_party(:peace_offered_by_player_id, "must be one of the wartime players")
    |> validate_peace_offer()
    |> assoc_constraint(:world)
    |> assoc_constraint(:player_a)
    |> assoc_constraint(:player_b)
    |> assoc_constraint(:declarer_player)
    |> assoc_constraint(:peace_offered_by_player)
    |> unique_constraint([:world_id, :player_a_id, :player_b_id],
      name: :game_wars_world_player_a_player_b_index
    )
  end

  @spec declare(map(), map(), map()) :: {:ok, t()} | {:error, atom() | Ecto.Changeset.t()}
  def declare(state, user, other_user) do
    with {:ok, declarer} <- fetch_player(state, user.id),
         {:ok, opponent} <- fetch_player(state, other_user.id),
         nil <- find(state.world.id, declarer.id, opponent.id),
         {:ok, war} <-
           %__MODULE__{}
           |> changeset(%{
             world_id: state.world.id,
             player_a_id: declarer.id,
             player_b_id: opponent.id,
             declarer_player_id: declarer.id
           })
           |> Repo.insert() do
      {:ok, war}
    else
      %__MODULE__{} -> {:error, :already_at_war}
      {:error, _operation, changeset, _changes} -> {:error, changeset}
      {:error, _} = error -> error
    end
  end

  @doc "Offers peace to the other party in an active war."
  @spec offer_peace(map(), map(), map()) :: {:ok, t()} | {:error, atom() | Ecto.Changeset.t()}
  def offer_peace(state, user, other_user) do
    with {:ok, offering_player} <- fetch_player(state, user.id),
         {:ok, other_player} <- fetch_player(state, other_user.id),
         %__MODULE__{} = war <- find(state.world.id, offering_player.id, other_player.id),
         {:ok, offered_war} <-
           war
           |> changeset(%{status: :peace_offered, peace_offered_by_player_id: offering_player.id})
           |> Repo.update() do
      {:ok, offered_war}
    else
      nil -> {:error, :not_at_war}
      {:error, _operation, changeset, _changes} -> {:error, changeset}
      {:error, _} = error -> error
    end
  end

  @doc "Accepts the other party's pending peace offer and ends the war."
  @spec accept_peace(map(), map(), map()) :: :ok | {:error, atom() | Ecto.Changeset.t()}
  def accept_peace(state, user, other_user) do
    with {:ok, accepting_player} <- fetch_player(state, user.id),
         {:ok, offering_player} <- fetch_player(state, other_user.id),
         %__MODULE__{status: :peace_offered, peace_offered_by_player_id: offering_player_id} = war <-
           find(state.world.id, accepting_player.id, offering_player.id),
         true <- offering_player_id == offering_player.id,
         {:ok, _war} <- Repo.delete(war) do
      :ok
    else
      nil -> {:error, :no_pending_peace_offer}
      false -> {:error, :no_pending_peace_offer}
      %__MODULE__{} -> {:error, :no_pending_peace_offer}
      {:error, _} = error -> error
    end
  end

  @spec active?(term(), integer(), integer()) :: boolean()
  def active?(world_id, player_a_id, player_b_id) do
    match?(
      %__MODULE__{status: status} when status in [:active, :peace_offered],
      find(world_id, player_a_id, player_b_id)
    )
  end

  @doc "The active war's status and peace-offer origin, from `user`'s point of view."
  @spec status_for(map(), map(), map()) ::
          %{status: status(), peace_offered_by_user_id: integer() | nil} | nil
  def status_for(state, user, other_user) do
    with {:ok, player} <- fetch_player(state, user.id),
         {:ok, other_player} <- fetch_player(state, other_user.id),
         %__MODULE__{} = war <- find(state.world.id, player.id, other_player.id) do
      offered_by_user_id =
        state.players
        |> Map.values()
        |> Enum.find(&(&1.id == war.peace_offered_by_player_id))
        |> case do
          nil -> nil
          offering_player -> offering_player.user_id
        end

      %{status: war.status, peace_offered_by_user_id: offered_by_user_id}
    else
      _ -> nil
    end
  end

  @spec find(term(), integer(), integer()) :: t() | nil
  def find(world_id, player_a_id, player_b_id) do
    {player_a_id, player_b_id} = canonical_pair(player_a_id, player_b_id)

    Repo.get_by(__MODULE__,
      world_id: world_id,
      player_a_id: player_a_id,
      player_b_id: player_b_id
    )
  end

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
        changeset
        |> put_change(:player_a_id, b)
        |> put_change(:player_b_id, a)

      _players ->
        changeset
    end
  end

  defp validate_party(changeset, field, message) do
    case get_field(changeset, field) in player_ids(changeset) do
      true -> changeset
      false -> add_error(changeset, field, message)
    end
  end

  defp validate_optional_party(changeset, field, message) do
    case get_field(changeset, field) do
      nil -> changeset
      _player_id -> validate_party(changeset, field, message)
    end
  end

  defp validate_peace_offer(changeset) do
    case {get_field(changeset, :status), get_field(changeset, :peace_offered_by_player_id)} do
      {:peace_offered, nil} ->
        add_error(changeset, :peace_offered_by_player_id, "is required while peace is offered")

      {:active, player_id} when is_integer(player_id) ->
        add_error(
          changeset,
          :peace_offered_by_player_id,
          "can only be set while peace is offered"
        )

      _state ->
        changeset
    end
  end

  defp player_ids(changeset) do
    [get_field(changeset, :player_a_id), get_field(changeset, :player_b_id)]
  end
end
