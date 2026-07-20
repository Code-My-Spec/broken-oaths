defmodule BrokenOaths.Game.RebellionPactMember do
  @moduledoc """
  A single conspirator's secret standing inside a
  `BrokenOaths.Game.RebellionPact` (story 916, "Pact of Broken Oaths"):
  pact-chat MEMBERSHIP of a row IS the conspiracy roster — every fellow
  vassal a pact's opener invites gets a row here the moment they're
  invited, `commit_status` starting `:invited` ("outstanding" to every
  other reader, including the lord).

  `commit_status` is the invitee's own SECRET answer — `:committed`
  (will strike) or `:declined` (backed out) — never surfaced to the
  targeted lord or to fellow members before the pact's strike turn
  fires; that visibility rule is enforced by a future read layer this
  schema only carries the state for (see `RebellionPact`'s own
  moduledoc).

  `informer` flags a member who has secretly betrayed the plot to the
  lord for a personal reward (story 916's own "informer's dilemma") —
  their identity stays hidden from every OTHER member, including from
  the lord's own knowledge of who among the roster it is; only this row
  (and the lord's own private notification, built elsewhere) ever
  carries the fact.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Players.Player
  alias BrokenOaths.Game.RebellionPact

  @type commit_status :: :invited | :committed | :declined

  @type t :: %__MODULE__{
          id: integer() | nil,
          commit_status: commit_status(),
          informer: boolean(),
          rebellion_pact_id: integer() | nil,
          player_id: integer() | nil,
          rebellion_pact: RebellionPact.t() | Ecto.Association.NotLoaded.t(),
          player: Player.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_rebellion_pact_members" do
    field :commit_status, Ecto.Enum, values: [:invited, :committed, :declined], default: :invited
    field :informer, :boolean, default: false

    belongs_to :rebellion_pact, RebellionPact
    belongs_to :player, Player

    timestamps()
  end

  @doc false
  def changeset(rebellion_pact_member, attrs) do
    rebellion_pact_member
    |> cast(attrs, [:rebellion_pact_id, :player_id, :commit_status, :informer])
    |> validate_required([:rebellion_pact_id, :player_id, :commit_status])
    |> assoc_constraint(:rebellion_pact)
    |> assoc_constraint(:player)
    |> unique_constraint([:rebellion_pact_id, :player_id],
      name: :game_rebellion_pact_members_pact_id_player_id_index
    )
  end

  @doc "True once the member has secretly committed to strike."
  @spec committed?(t()) :: boolean()
  def committed?(%__MODULE__{commit_status: :committed}), do: true
  def committed?(%__MODULE__{}), do: false

  @doc "True once the member has secretly declined to strike."
  @spec declined?(t()) :: boolean()
  def declined?(%__MODULE__{commit_status: :declined}), do: true
  def declined?(%__MODULE__{}), do: false

  @doc "True while the member's invite is still outstanding — the secret-until-strike default."
  @spec outstanding?(t()) :: boolean()
  def outstanding?(%__MODULE__{commit_status: :invited}), do: true
  def outstanding?(%__MODULE__{}), do: false

  @doc "True for the member who has secretly betrayed the plot to the lord."
  @spec informer?(t()) :: boolean()
  def informer?(%__MODULE__{informer: informer}), do: informer
end
