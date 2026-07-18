defmodule BrokenOaths.Game.Unit do
  @moduledoc """
  A unit on the board — type (lord/settler/warrior/worker/barbarian
  warrior/bronze spearman, story 903), owner, tile id, hp, movement
  points.

  `player_id` is nullable: a barbarian warrior (`type: :barbarian_warrior`,
  spawned by `BrokenOaths.Game.Camps`, story 892) has no owning player —
  the seam `BrokenOaths.Game.Combat.hostile?/2` recognizes — and instead
  carries `camp_id`, the camp that spawned it (used to cap "alive
  warriors per camp" at 2). An ordinary player-owned unit always sets
  `player_id` and leaves `camp_id` nil; the two are never both set.

  One unit per hex is a hard rule, with two exceptions: a city's own
  tile (story 895's garrison exception — see
  `BrokenOaths.Game.CityDefense.garrison_room?/2`), and, out in the open
  field, exactly one non-combat unit stacking with exactly one combat
  unit of the SAME owner (v0.2.1 playtest issue 5df5de88 — a worker or
  settler may walk with a warrior/lord/bronze-spearman escort — see
  `BrokenOaths.Game.WorldServer.field_stack_room?/2` and
  `BrokenOaths.Game.Turn.entering_field_stack_with_room?/2`). It's
  enforced at the application layer
  (`BrokenOaths.Game.WorldServer.occupied_by_own?/4` at queue time,
  `BrokenOaths.Game.Turn`'s movement collision check at tick time)
  rather than a blanket DB unique index — see migration
  `20260716190000` for why a DB-level constraint can no longer express
  this rule.

  Per-type stats (starting hp/movement) live in
  `BrokenOaths.Game.Production.unit_stats/1` alongside the rest of the
  buildable catalog, not here — this schema only shapes and validates
  whatever stats it's given.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Game.Camp
  alias BrokenOaths.Game.Player
  alias BrokenOaths.Worlds.World

  @type unit_type :: :lord | :settler | :warrior | :worker | :barbarian_warrior | :bronze_spearman

  @type t :: %__MODULE__{
          id: integer() | nil,
          type: unit_type() | nil,
          tile_id: integer() | nil,
          hp: integer() | nil,
          max_hp: integer() | nil,
          movement: integer() | nil,
          max_movement: integer() | nil,
          world_id: integer() | nil,
          player_id: integer() | nil,
          camp_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          player: Player.t() | Ecto.Association.NotLoaded.t() | nil,
          camp: Camp.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_units" do
    field :type, Ecto.Enum,
      values: [:lord, :settler, :warrior, :worker, :barbarian_warrior, :bronze_spearman]
    field :tile_id, :integer
    field :hp, :integer
    field :max_hp, :integer
    field :movement, :integer
    field :max_movement, :integer

    belongs_to :world, World
    belongs_to :player, Player
    belongs_to :camp, Camp

    timestamps()
  end

  @doc false
  def changeset(unit, attrs) do
    unit
    |> cast(attrs, [
      :world_id,
      :player_id,
      :camp_id,
      :type,
      :tile_id,
      :hp,
      :max_hp,
      :movement,
      :max_movement
    ])
    |> validate_required([
      :world_id,
      :type,
      :tile_id,
      :hp,
      :max_hp,
      :movement,
      :max_movement
    ])
    |> validate_number(:hp, greater_than: 0)
    |> validate_number(:max_hp, greater_than: 0)
    |> validate_number(:movement, greater_than_or_equal_to: 0)
    |> validate_number(:max_movement, greater_than_or_equal_to: 0)
    |> validate_hp_within_max()
    |> validate_movement_within_max()
    |> assoc_constraint(:world)
    |> assoc_constraint(:player)
    |> assoc_constraint(:camp)
  end

  defp validate_hp_within_max(changeset) do
    validate_field_within_max(changeset, :hp, :max_hp)
  end

  defp validate_movement_within_max(changeset) do
    validate_field_within_max(changeset, :movement, :max_movement)
  end

  defp validate_field_within_max(changeset, field, max_field) do
    value = get_field(changeset, field)
    max_value = get_field(changeset, max_field)

    if is_integer(value) and is_integer(max_value) and value > max_value do
      add_error(changeset, field, "must be less than or equal to #{max_field}")
    else
      changeset
    end
  end
end
