defmodule BrokenOaths.Feudal.Vassalage do
  @moduledoc """
  The player-to-player feudal relationship record (story 907): created
  automatically the moment a capture leaves the defeated player with
  zero free cities (see `BrokenOaths.Combat.Siege.no_free_cities?/2` and
  `BrokenOaths.Feudal.Vassalization`, the module that actually creates
  rows of this schema).

  Carries every forward-looking field the design doc calls for from day
  one, so the rebellion batch (`.code_my_spec/knowledge/
  feudal_vassalage_design.md` §8) never has to rebuild this table:

    * `tribute_rate` — a LORD-SET, per-vassal, adjustable lever (story
      908's own `set_tribute_rate`), defaulting to 25% and applied to
      the vassal's gross per-turn gold income.
    * `oath_strain` — liberty pressure, 0-100, rising from imbalance/
      neglect (a refused call to arms, story 908) and falling from
      investment — the rebellion batch's own gate, carried here now.
    * `hidden_agenda` — the vassal's secret personal ambition, chosen at
      the Oath screen the moment they're subjugated (`nil` until then).
    * `contract_terms` — a jsonb bag for the reciprocal duties the LORD
      owes the vassal (protection, a share of spoils, autonomy) — no
      story in this batch reads or writes concrete keys yet; it exists
      so those duties don't need a schema change to land later.
    * `status` — `:active` while the oath holds; `:broken` once a
      rebellion (a later batch) actually severs it.

  Honor itself has no ledger of its own yet anywhere in this codebase
  (no story surfaces a number for it in this batch) — the "Honor ledger
  hooks" the design doc calls for are the call sites this schema's own
  callers (`BrokenOaths.Combat.Siege`'s garrison-fate choice,
  `BrokenOaths.Feudal.Tribute`'s levy refusal) already document as future
  Honor deltas, not a column on this table.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Players.Player
  alias BrokenOaths.Worlds.World

  @type hidden_agenda :: :restore | :usurp | :kingmaker | :merchant_prince
  @type status :: :active | :broken

  @type t :: %__MODULE__{
          id: integer() | nil,
          tribute_rate: float(),
          oath_strain: integer(),
          hidden_agenda: hidden_agenda() | nil,
          contract_terms: map(),
          status: status(),
          world_id: integer() | nil,
          lord_player_id: integer() | nil,
          vassal_player_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          lord_player: Player.t() | Ecto.Association.NotLoaded.t(),
          vassal_player: Player.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_vassalages" do
    field :tribute_rate, :float, default: 0.25
    field :oath_strain, :integer, default: 0
    field :hidden_agenda, Ecto.Enum, values: [:restore, :usurp, :kingmaker, :merchant_prince]
    field :contract_terms, :map, default: %{}
    field :status, Ecto.Enum, values: [:active, :broken], default: :active

    belongs_to :world, World
    belongs_to :lord_player, Player
    belongs_to :vassal_player, Player

    timestamps()
  end

  @doc false
  def changeset(vassalage, attrs) do
    vassalage
    |> cast(attrs, [
      :world_id,
      :lord_player_id,
      :vassal_player_id,
      :tribute_rate,
      :oath_strain,
      :hidden_agenda,
      :contract_terms,
      :status
    ])
    |> validate_required([
      :world_id,
      :lord_player_id,
      :vassal_player_id,
      :tribute_rate,
      :oath_strain,
      :status
    ])
    |> validate_number(:tribute_rate, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_number(:oath_strain, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_lord_and_vassal_distinct()
    |> assoc_constraint(:world)
    |> assoc_constraint(:lord_player)
    |> assoc_constraint(:vassal_player)
    |> unique_constraint([:world_id, :vassal_player_id],
      name: :game_vassalages_world_id_vassal_player_id_index
    )
  end

  # A player can never swear fealty to themselves.
  defp validate_lord_and_vassal_distinct(changeset) do
    lord_id = get_field(changeset, :lord_player_id)
    vassal_id = get_field(changeset, :vassal_player_id)

    if is_nil(lord_id) or is_nil(vassal_id) or lord_id != vassal_id do
      changeset
    else
      add_error(changeset, :vassal_player_id, "can't be the same as the lord")
    end
  end
end
