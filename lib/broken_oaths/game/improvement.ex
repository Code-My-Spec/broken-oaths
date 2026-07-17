defmodule BrokenOaths.Game.Improvement do
  @moduledoc """
  A tile improvement — farm, mine, or road — built by a worker over
  several turns. Progress sticks to the TILE, not the worker (story
  882): `builder_unit_id` names whichever unit is currently advancing
  it, or `nil` while paused. `BrokenOaths.Game.Turn` clears
  `builder_unit_id` whenever that unit is no longer standing on
  `tile_id` at a turn boundary, and only advances `progress` for
  improvements that still have a builder present — so walking away
  freezes the dig exactly where it stood, and any worker (any player's
  — improvements aren't owned) that later starts the same kind on that
  tile resumes it.

  One improvement per tile, enforced by the unique index on
  `(world_id, tile_id)`: once `status` is `:complete`, no second
  improvement can ever be started there (see
  `BrokenOaths.Game.Production` for the terrain-eligibility and
  duration rules — `allowed?/2` and `duration/1` below — and
  `BrokenOaths.Game.Yields` for the yield bonus a finished improvement
  contributes).

  A barbarian entering a `:complete` improvement's tile pillages it
  (`pillage/1`, story 893): `status` flips to `:pillaged` — the same
  "not `:complete`" gate `Yields.completed_kind/2` already uses, so a
  pillaged improvement's bonus silently stops counting with no separate
  check — and its `kind` is kept so a worker resuming the SAME kind
  repairs it in exactly one turn rather than paying a fresh build's
  full `duration/1`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Game.Unit
  alias BrokenOaths.Worlds.Terrain
  alias BrokenOaths.Worlds.World

  @type kind :: :farm | :mine | :road
  @type status :: :building | :complete | :pillaged

  @type t :: %__MODULE__{
          id: integer() | nil,
          tile_id: integer() | nil,
          kind: kind() | nil,
          progress: non_neg_integer(),
          status: status(),
          world_id: integer() | nil,
          builder_unit_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          builder: Unit.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_improvements" do
    field :tile_id, :integer
    field :kind, Ecto.Enum, values: [:farm, :mine, :road]
    field :progress, :integer, default: 0
    field :status, Ecto.Enum, values: [:building, :complete, :pillaged], default: :building

    belongs_to :world, World
    belongs_to :builder, Unit, foreign_key: :builder_unit_id

    timestamps()
  end

  @doc false
  def changeset(improvement, attrs) do
    improvement
    |> cast(attrs, [:world_id, :tile_id, :kind, :progress, :status, :builder_unit_id])
    |> validate_required([:world_id, :tile_id, :kind, :progress, :status])
    |> validate_number(:progress, greater_than_or_equal_to: 0)
    |> assoc_constraint(:world)
    |> assoc_constraint(:builder)
    |> unique_constraint([:world_id, :tile_id], name: :game_improvements_world_id_tile_id_index)
  end

  @doc "Turns to complete each improvement kind (story 882's yield table)."
  @spec duration(kind()) :: pos_integer()
  def duration(:farm), do: 3
  def duration(:mine), do: 5
  def duration(:road), do: 2

  @doc """
  Whether `kind` can be started on `terrain`: Farm needs flat,
  featureless grassland or plains; Mine needs hills (any base or
  feature); Road works on any passable land tile — callers are
  expected to have already excluded non-`:land` tiles (mountains,
  water) via `BrokenOaths.Worlds.Regions.tile_class/2`.
  """
  @spec allowed?(kind(), Terrain.t()) :: boolean()
  def allowed?(:farm, %Terrain{relief: :flat, feature: nil, base: base}),
    do: base in [:grassland, :plains]

  def allowed?(:farm, %Terrain{}), do: false
  def allowed?(:mine, %Terrain{relief: :hills}), do: true
  def allowed?(:mine, %Terrain{}), do: false
  def allowed?(:road, %Terrain{}), do: true

  @doc """
  Pillage a `:complete` improvement (story 893, criterion 7556):
  `status` flips to `:pillaged` and `builder_unit_id` clears (nothing
  is mid-build); `progress` is pre-loaded to `duration(kind) - 1` so
  resuming the SAME kind needs only one more tick to finish, instead of
  a fresh build's full duration. A no-op on anything not `:complete` —
  a barbarian only burns a FINISHED improvement, never one mid-build.
  """
  @spec pillage(map()) :: map()
  def pillage(%{status: :complete, kind: kind} = improvement) do
    %{improvement | status: :pillaged, progress: max(duration(kind) - 1, 0), builder_unit_id: nil}
  end

  def pillage(improvement), do: improvement
end
