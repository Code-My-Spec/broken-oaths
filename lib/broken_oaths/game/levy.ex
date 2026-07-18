defmodule BrokenOaths.Game.Levy do
  @moduledoc """
  A call-to-arms pledge record (story 908): the lord calls a vassal to
  send a share of their standing army to a war, for the war's duration.

  There is no formal `War` entity yet — the war is identified by its
  `target_player`, the rival the lord is fighting. `pledged_share` is
  the fraction (0, 1] of the vassal's standing army committed; the
  vassal keeps command of the pledged units.

  `status` tracks the call's lifecycle: `:pending` (issued, awaiting
  the vassal's response), `:answered` (units sent), `:refused` (the
  vassal declined — or, per the war-duration binding, pulled out
  early; `BrokenOaths.Game.Tribute` is where a mid-war withdrawal gets
  reclassified to `:refused` and Oath Strain/Honor react — this schema
  only carries the resulting state).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Game.Player
  alias BrokenOaths.Worlds.World

  @type status :: :pending | :answered | :refused

  @type t :: %__MODULE__{
          id: integer() | nil,
          pledged_share: float() | nil,
          status: status(),
          world_id: integer() | nil,
          lord_player_id: integer() | nil,
          vassal_player_id: integer() | nil,
          target_player_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          lord_player: Player.t() | Ecto.Association.NotLoaded.t(),
          vassal_player: Player.t() | Ecto.Association.NotLoaded.t(),
          target_player: Player.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_levies" do
    field :pledged_share, :float
    field :status, Ecto.Enum, values: [:pending, :answered, :refused], default: :pending

    belongs_to :world, World
    belongs_to :lord_player, Player
    belongs_to :vassal_player, Player
    belongs_to :target_player, Player

    timestamps()
  end

  @doc false
  def changeset(levy, attrs) do
    levy
    |> cast(attrs, [
      :world_id,
      :lord_player_id,
      :vassal_player_id,
      :target_player_id,
      :pledged_share,
      :status
    ])
    |> validate_required([
      :world_id,
      :lord_player_id,
      :vassal_player_id,
      :target_player_id,
      :pledged_share,
      :status
    ])
    |> validate_number(:pledged_share, greater_than: 0, less_than_or_equal_to: 1)
    |> validate_lord_and_vassal_distinct()
    |> validate_target_not_vassal()
    |> validate_target_not_lord()
    |> assoc_constraint(:world)
    |> assoc_constraint(:lord_player)
    |> assoc_constraint(:vassal_player)
    |> assoc_constraint(:target_player)
  end

  # A lord cannot call themselves to arms.
  defp validate_lord_and_vassal_distinct(changeset) do
    lord_id = get_field(changeset, :lord_player_id)
    vassal_id = get_field(changeset, :vassal_player_id)

    if is_nil(lord_id) or is_nil(vassal_id) or lord_id != vassal_id do
      changeset
    else
      add_error(changeset, :vassal_player_id, "can't be the same as the lord")
    end
  end

  # The war's target is a third party — a call to arms can't pledge the
  # vassal's army against themselves.
  defp validate_target_not_vassal(changeset) do
    vassal_id = get_field(changeset, :vassal_player_id)
    target_id = get_field(changeset, :target_player_id)

    if is_nil(vassal_id) or is_nil(target_id) or vassal_id != target_id do
      changeset
    else
      add_error(changeset, :target_player_id, "can't be the same as the vassal")
    end
  end

  # Nor against the lord who's issuing the call.
  defp validate_target_not_lord(changeset) do
    lord_id = get_field(changeset, :lord_player_id)
    target_id = get_field(changeset, :target_player_id)

    if is_nil(lord_id) or is_nil(target_id) or lord_id != target_id do
      changeset
    else
      add_error(changeset, :target_player_id, "can't be the same as the lord")
    end
  end
end
