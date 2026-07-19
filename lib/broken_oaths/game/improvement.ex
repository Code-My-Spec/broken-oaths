defmodule BrokenOaths.Game.Improvement do
  @moduledoc """
  A tile improvement — farm, mine, road, or pasture — built by a
  worker over several turns. Progress sticks to the TILE, not the worker (story
  882): `builder_unit_id` names whichever unit is currently advancing
  it, or `nil` while paused. `BrokenOaths.Game.Turn` clears
  `builder_unit_id` whenever that unit is no longer standing on
  `tile_id` at a turn boundary, and only advances `progress` for
  improvements that still have a builder present — so walking away
  freezes the dig exactly where it stood, and any worker (any player's
  — improvements aren't owned) that later starts the same kind on that
  tile resumes it.

  One improvement PER KIND per tile, enforced by the unique index on
  `(world_id, tile_id, kind)`: once a given kind's `status` is
  `:complete`, no second improvement of THAT kind can ever be started
  on the same tile. A Road, though, is a movement/connectivity
  improvement, orthogonal to a tile's yield improvement — Farm, Mine,
  or Pasture — the same "road sits UNDER an improvement" convention
  Civ 6 itself uses (QA issue 5656770d "Roads conflict with
  improvements"): `BrokenOaths.Game.WorldServer`'s
  `validate_improvement_slot/3` checks a `:road` request only against
  any EXISTING road on the tile, and a Farm/Mine/Pasture request only
  against any existing YIELD improvement, so a worker can freely build
  a Road across a tile that already carries (or is still building) a
  Farm or a Mine, and vice versa — the two live as independent rows,
  keyed by `(world_id, tile_id, kind)`, and `BrokenOaths.Game.WorldServer`
  holds them in two separate in-memory maps (`state.improvements` for
  the yield slot, `state.roads` for the road slot) for exactly this
  reason. Farm, Mine, and Pasture remain mutually exclusive with EACH
  OTHER on a given tile — that yield slot is still only one improvement
  wide (see `BrokenOaths.Game.Production` for the terrain-eligibility
  and duration rules — `allowed?/2` and `duration/1` below — and
  `BrokenOaths.Game.Yields` for the yield bonus a finished improvement
  contributes; a Road's own yield bonus is `%{food: 0, production: 0}`
  — see `Yields.improvement_bonus/1` — its movement effect is still
  deferred, as before this fix).

  A barbarian entering a `:complete` improvement's tile pillages it
  (`pillage/1`, story 893): `status` flips to `:pillaged` — the same
  "not `:complete`" gate `Yields.completed_kind/2` already uses, so a
  pillaged improvement's bonus silently stops counting with no separate
  check — and its `kind` is kept so a worker resuming the SAME kind
  repairs it in exactly one turn rather than paying a fresh build's
  full `duration/1`. A Road on the same tile pillages independently —
  each kind is its own row, so a barbarian entering a tile that carries
  both a complete Farm and a complete Road pillages BOTH.

  ## Pasture (story 905)

  Unlike Farm/Mine/Road, which gate purely on TERRAIN
  (`allowed?/2`), Pasture gates on the tile's bonus RESOURCE
  (`BrokenOaths.Worlds.Resources.at/2` returning `:cattle` or
  `:sheep` — the two animal resources) as well as the building
  worker's OWNER having completed Animal Husbandry
  (`BrokenOaths.Game.Research.pasture_enabled?/1`). Neither of those
  is terrain, so `resource_allowed?/1` — not `allowed?/2` — is the
  gate callers use for this one kind; `WorldServer` combines it with
  the research check before ever calling `persist_start_improvement!/3`.

  ## Mining's 3-turn unlock (story 902)

  `duration/1` is the KIND's base — a hardcoded constant, same as
  always. `:duration` on the schema/struct is the INSTANCE's actual
  target, resolved once, at creation (`BrokenOaths.Game.WorldServer`'s
  `persist_start_improvement!/3`, not this module — a pure schema has
  no access to a player's research state), from the building worker's
  OWNER's research (`BrokenOaths.Game.Research.mine_duration/1` for a
  Mine, `duration(kind)` for Farm/Road) — improvements themselves stay
  ownerless (see above: any player's worker may resume one), so it is
  specifically "whoever's worker broke ground here first" that decided
  the pace, not whoever eventually finishes it. `BrokenOaths.Game.Turn`
  reads this field back (falling to `duration/1` when absent, e.g. a
  hand-built tick-state map in a unit test) instead of recomputing
  `duration(kind)` itself.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Game.Unit
  alias BrokenOaths.Worlds.Terrain
  alias BrokenOaths.Worlds.World

  @type kind :: :farm | :mine | :road | :pasture
  @type status :: :building | :complete | :pillaged

  @type t :: %__MODULE__{
          id: integer() | nil,
          tile_id: integer() | nil,
          kind: kind() | nil,
          progress: non_neg_integer(),
          status: status(),
          duration: pos_integer() | nil,
          world_id: integer() | nil,
          builder_unit_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          builder: Unit.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_improvements" do
    field :tile_id, :integer
    field :kind, Ecto.Enum, values: [:farm, :mine, :road, :pasture]
    field :progress, :integer, default: 0
    field :status, Ecto.Enum, values: [:building, :complete, :pillaged], default: :building
    # Story 902 — see the moduledoc's "Mining's 3-turn unlock" section.
    # Nullable: a row written before this field existed (or a hand-built
    # `BrokenOaths.Game.Turn` tick-state map in a unit test) simply has
    # none, and every reader falls back to `duration/1`.
    field :duration, :integer

    belongs_to :world, World
    belongs_to :builder, Unit, foreign_key: :builder_unit_id

    timestamps()
  end

  @doc false
  def changeset(improvement, attrs) do
    improvement
    |> cast(attrs, [:world_id, :tile_id, :kind, :progress, :status, :duration, :builder_unit_id])
    |> validate_required([:world_id, :tile_id, :kind, :progress, :status])
    |> validate_number(:progress, greater_than_or_equal_to: 0)
    |> validate_number(:duration, greater_than: 0)
    |> assoc_constraint(:world)
    |> assoc_constraint(:builder)
    |> unique_constraint([:world_id, :tile_id, :kind],
      name: :game_improvements_world_id_tile_id_kind_index
    )
  end

  @doc "Turns to complete each improvement kind (story 882's yield table; story 905's Pasture)."
  @spec duration(kind()) :: pos_integer()
  def duration(:farm), do: 3
  def duration(:mine), do: 5
  def duration(:road), do: 2
  def duration(:pasture), do: 4

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
  Whether a Mine can be built on a tile, widened for strategic resources
  (QA issue 5a30ad3f): the normal Hills-relief gate (`allowed?/2`), OR
  any tile carrying a mineable strategic resource — Copper, which
  `BrokenOaths.Worlds.Resources.ensure_reachable_copper/3` can guarantee
  onto a non-Hills tile near spawn, leaving the player staring at a
  Copper deposit with no way to mine it. Callers still owe the `:land`
  `tile_class` check (mountains/water) exactly as `allowed?/2` documents.
  """
  @spec mine_allowed?(Terrain.t(), atom() | nil) :: boolean()
  def mine_allowed?(terrain, resource), do: allowed?(:mine, terrain) or resource == :copper

  @doc """
  Whether a Pasture can be built on a tile carrying `resource` (story
  905): only the two animal resources, Cattle and Sheep — the terrain
  those two are eligible on (`BrokenOaths.Worlds.Resources`) already
  implies passable land, so no separate terrain check is needed here.
  Callers still owe the research gate
  (`BrokenOaths.Game.Research.pasture_enabled?/1`) separately — this
  function only ever answers "is this tile the right KIND of tile."
  """
  @spec resource_allowed?(:cattle | :sheep | :wheat | :stone | nil) :: boolean()
  def resource_allowed?(resource), do: resource in [:cattle, :sheep]

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
