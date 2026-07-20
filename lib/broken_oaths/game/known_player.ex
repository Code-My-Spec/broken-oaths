defmodule BrokenOaths.Game.KnownPlayer do
  @moduledoc """
  A discovery record: `viewer_player` has discovered `discovered_player`
  in a world — permanent once set (story 899).

  Discovery is mutual but stored directionally: first contact between
  two players writes ONE row per direction (see
  `BrokenOaths.Game.Discovery`), so a player's own "Known Players" list
  is a plain `where viewer_player_id == ^my_player.id` query, with no
  need to reason about which side of the pair is "me" at read time.
  Once a row exists it is never removed — losing sight of the other
  civilization (fog of war, story 876) never un-discovers them.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Players.Player
  alias BrokenOaths.Worlds.World

  @type t :: %__MODULE__{
          id: integer() | nil,
          world_id: integer() | nil,
          viewer_player_id: integer() | nil,
          discovered_player_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          viewer_player: Player.t() | Ecto.Association.NotLoaded.t(),
          discovered_player: Player.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_known_players" do
    belongs_to :world, World
    belongs_to :viewer_player, Player
    belongs_to :discovered_player, Player

    timestamps()
  end

  @doc false
  def changeset(known_player, attrs) do
    known_player
    |> cast(attrs, [:world_id, :viewer_player_id, :discovered_player_id])
    |> validate_required([:world_id, :viewer_player_id, :discovered_player_id])
    |> validate_not_self_discovery()
    |> assoc_constraint(:world)
    |> assoc_constraint(:viewer_player)
    |> assoc_constraint(:discovered_player)
    |> unique_constraint([:world_id, :viewer_player_id, :discovered_player_id],
      name: :game_known_players_world_viewer_discovered_index
    )
  end

  # A player always already knows themselves — a discovery record only
  # ever links two DISTINCT civilizations.
  defp validate_not_self_discovery(changeset) do
    viewer_id = get_field(changeset, :viewer_player_id)
    discovered_id = get_field(changeset, :discovered_player_id)

    if is_nil(viewer_id) or is_nil(discovered_id) or viewer_id != discovered_id do
      changeset
    else
      add_error(changeset, :discovered_player_id, "can't be the same as the viewer")
    end
  end
end
