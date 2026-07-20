defmodule BrokenOaths.Feudal.RebellionPact do
  @moduledoc """
  The Pact of Broken Oaths record (story 916): a conspiracy binding
  fellow vassals of ONE targeted lord to a shared strike turn, opened by
  one of those vassals inviting the others into what the design calls a
  "pact chat" — chat membership IS the conspiracy roster, modeled here
  by `BrokenOaths.Feudal.RebellionPactMember` rows.

  Every member's own commit/decline answer (and any informer betrayal)
  is SECRET — hidden from the targeted lord and from every other member
  alike until the strike turn reveals all of it at once (criterion
  7738, `.code_my_spec/knowledge/feudal_vassalage_design.md` "Round 2 —
  first-class Rebellion, Pact-in-chat"). This schema only carries that
  state; the actual reveal/broadcast, the WorldServer tick-delta
  persistence, and the pact-chat LiveView surface are a later,
  separately coordinated integration step — this module stays a plain
  data + changeset schema with no engine logic and no process of its
  own.

    * `status` — `:forming` while invites are still outstanding and
      commitments can still change, `:struck` once the strike turn has
      fired and reveal/independence has processed, `:dissolved` if the
      pact ends without ever striking (e.g. every member declines).
    * `strike_turn` — the world-turn the revolt fires; always a turn
      still ahead of the pact's own opening (`> 0`).
    * `opener_player_id` — the vassal who opened the pact and issued the
      original invites; always a fellow vassal of `lord_player_id`,
      never the lord themself.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Players.Player
  alias BrokenOaths.Feudal.RebellionPactMember
  alias BrokenOaths.Worlds.World

  @type status :: :forming | :struck | :dissolved

  @type t :: %__MODULE__{
          id: integer() | nil,
          strike_turn: integer() | nil,
          status: status(),
          world_id: integer() | nil,
          lord_player_id: integer() | nil,
          opener_player_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          lord_player: Player.t() | Ecto.Association.NotLoaded.t(),
          opener_player: Player.t() | Ecto.Association.NotLoaded.t(),
          members: [RebellionPactMember.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_rebellion_pacts" do
    field :strike_turn, :integer
    field :status, Ecto.Enum, values: [:forming, :struck, :dissolved], default: :forming

    belongs_to :world, World
    belongs_to :lord_player, Player
    belongs_to :opener_player, Player
    has_many :members, RebellionPactMember

    timestamps()
  end

  @doc false
  def changeset(rebellion_pact, attrs) do
    rebellion_pact
    |> cast(attrs, [:world_id, :lord_player_id, :opener_player_id, :strike_turn, :status])
    |> validate_required([
      :world_id,
      :lord_player_id,
      :opener_player_id,
      :strike_turn,
      :status
    ])
    |> validate_number(:strike_turn, greater_than: 0)
    |> validate_opener_is_not_the_lord()
    |> assoc_constraint(:world)
    |> assoc_constraint(:lord_player)
    |> assoc_constraint(:opener_player)
  end

  @doc """
  The full conspiracy roster of a pact — every member ever invited,
  regardless of their secret answer. Requires `:members` to be
  preloaded.
  """
  @spec roster(t()) :: [integer()]
  def roster(%__MODULE__{members: members}) when is_list(members) do
    Enum.map(members, & &1.player_id)
  end

  @doc """
  The members who have secretly committed to strike. Requires
  `:members` to be preloaded.
  """
  @spec committed_members(t()) :: [RebellionPactMember.t()]
  def committed_members(%__MODULE__{members: members}) when is_list(members) do
    Enum.filter(members, &RebellionPactMember.committed?/1)
  end

  @doc """
  The informer among a pact's members, if any has betrayed the plot to
  the lord. Requires `:members` to be preloaded.
  """
  @spec informer(t()) :: RebellionPactMember.t() | nil
  def informer(%__MODULE__{members: members}) when is_list(members) do
    Enum.find(members, &RebellionPactMember.informer?/1)
  end

  # The opener is one of the conspirators, never the lord they're
  # conspiring against.
  defp validate_opener_is_not_the_lord(changeset) do
    lord_id = get_field(changeset, :lord_player_id)
    opener_id = get_field(changeset, :opener_player_id)

    if is_nil(lord_id) or is_nil(opener_id) or lord_id != opener_id do
      changeset
    else
      add_error(changeset, :opener_player_id, "can't be the same as the lord")
    end
  end
end
