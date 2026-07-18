defmodule BrokenOaths.Game.PlayerResearch do
  @moduledoc """
  A player's Stone Age research state in a world (story 902): every
  completed tech, which tech (if any) is currently being researched,
  and science banked PER TECH — switching `current_research` never
  loses progress on the tech switched away from (Civ-style; see
  `BrokenOaths.Game.Research` for the tech catalog, costs, and unlock
  effects this schema's fields feed).

  One row per (world, player) — same convention as `BrokenOaths.Game.Player`
  itself (world + user) and `BrokenOaths.Game.KnownPlayer` (world +
  viewer + discovered): `unique_constraint/3` on `[:world_id, :player_id]`
  is the changeset-level backstop for the DB's own unique index.

  `banked_science` is a bare `:map` (Postgres jsonb) keyed by tech —
  jsonb round-trips its keys as strings, so `BrokenOaths.Game.Research`
  is the one place that converts between those string keys and the
  tech atoms every other function in this codebase works with.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Game.Player
  alias BrokenOaths.Worlds.World

  @techs [:animal_husbandry, :pottery, :mining, :bronze_working]

  @type tech :: :animal_husbandry | :pottery | :mining | :bronze_working

  @type t :: %__MODULE__{
          id: integer() | nil,
          completed_techs: [tech()],
          current_research: tech() | nil,
          banked_science: %{optional(String.t()) => non_neg_integer()},
          world_id: integer() | nil,
          player_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          player: Player.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_player_research" do
    field :completed_techs, {:array, Ecto.Enum}, values: @techs, default: []
    field :current_research, Ecto.Enum, values: @techs
    field :banked_science, :map, default: %{}

    belongs_to :world, World
    belongs_to :player, Player

    timestamps()
  end

  @doc false
  def changeset(player_research, attrs) do
    player_research
    |> cast(attrs, [:world_id, :player_id, :completed_techs, :current_research, :banked_science])
    |> validate_required([:world_id, :player_id])
    |> validate_current_research_not_completed()
    |> assoc_constraint(:world)
    |> assoc_constraint(:player)
    |> unique_constraint([:world_id, :player_id],
      name: :game_player_research_world_id_player_id_index
    )
  end

  # A tech already banked as completed can never simultaneously be the
  # one currently being researched — `BrokenOaths.Game.Research.set_research/2`
  # already refuses to select one (`{:error, :already_completed}`); this
  # enforces the same rule at the persistence boundary.
  defp validate_current_research_not_completed(changeset) do
    current = get_field(changeset, :current_research)
    completed = get_field(changeset, :completed_techs) || []

    if is_nil(current) or current not in completed do
      changeset
    else
      add_error(changeset, :current_research, "can't be a tech that's already completed")
    end
  end
end
