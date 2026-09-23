defmodule BrokenOaths.Feudal.ControlGrant do
  @moduledoc """
  Story 947 -- an owner's explicit, per-delegate delegated-control grant.

  `level` is one of `:none | :defensive | :full`, owner-set per delegate
  (never inferred from alliance/vassalage status alone -- that only
  determines who is *eligible* to receive a grant, via
  `BrokenOaths.Feudal.Stewardship.steward_role/4`). `mode` only matters at
  `:full`: `:offline_only` (the default) gates real activation behind the
  owner having been continuously disconnected past the story's 5-minute
  grace window; `:always_on` lets the delegate act regardless of the
  owner's presence.

  Directional and one row per (owner, delegate) pair -- the owner's grant
  to a delegate says nothing about what that delegate has granted back
  (criterion 3153).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Players.Player
  alias BrokenOaths.Worlds.World

  @type level :: :none | :defensive | :full
  @type mode :: :offline_only | :always_on

  @type t :: %__MODULE__{
          id: integer() | nil,
          level: level(),
          mode: mode(),
          world_id: integer() | nil,
          owner_player_id: integer() | nil,
          delegate_player_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          owner_player: Player.t() | Ecto.Association.NotLoaded.t(),
          delegate_player: Player.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_control_grants" do
    field :level, Ecto.Enum, values: [:none, :defensive, :full], default: :none
    field :mode, Ecto.Enum, values: [:offline_only, :always_on], default: :offline_only

    belongs_to :world, World
    belongs_to :owner_player, Player
    belongs_to :delegate_player, Player

    timestamps()
  end

  @doc false
  def changeset(grant, attrs) do
    grant
    |> cast(attrs, [:world_id, :owner_player_id, :delegate_player_id, :level, :mode])
    |> validate_required([:world_id, :owner_player_id, :delegate_player_id, :level, :mode])
    |> unique_constraint([:world_id, :owner_player_id, :delegate_player_id],
      name: :game_control_grants_owner_delegate_index
    )
  end
end
