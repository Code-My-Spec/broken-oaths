defmodule BrokenOaths.Cities.Improvement do
  @moduledoc """
  A tile improvement — farm, mine, road, or pasture — built by a
  worker over several turns. Progress sticks to the TILE, not the worker (story
  882): `builder_unit_id` names whichever unit is currently advancing
  it, or `nil` while paused. `advance/1` clears `builder_unit_id`
  whenever that unit is no longer standing on `tile_id` at a turn
  boundary, and only advances `progress` for improvements that still
  have a builder present — so walking away freezes the dig exactly
  where it stood, and any worker (any player's — improvements aren't
  owned) that later starts the same kind on that tile resumes it.

  One improvement PER KIND per tile, enforced by the unique index on
  `(world_id, tile_id, kind)`: once a given kind's `status` is
  `:complete`, no second improvement of THAT kind can ever be started
  on the same tile. A Road, though, is a movement/connectivity
  improvement, orthogonal to a tile's yield improvement — Farm, Mine,
  or Pasture — the same "road sits UNDER an improvement" convention
  Civ 6 itself uses (QA issue 5656770d "Roads conflict with
  improvements"): this module's own `validate_improvement_slot/3`
  checks a `:road` request only against any EXISTING road on the tile,
  and a Farm/Mine/Pasture request only against any existing YIELD
  improvement, so a worker can freely build a Road across a tile that
  already carries (or is still building) a Farm or a Mine, and vice
  versa — the two live as independent rows, keyed by `(world_id,
  tile_id, kind)`, and `BrokenOaths.Simulation.WorldServer` holds them in two
  separate in-memory maps (`state.improvements` for the yield slot,
  `state.roads` for the road slot) for exactly this reason. Farm, Mine,
  and Pasture remain mutually exclusive with EACH OTHER on a given tile
  — that yield slot is still only one improvement wide (see
  `BrokenOaths.Cities.Production` for the terrain-eligibility and
  duration rules — `allowed?/2` and `duration/1` below — and
  `BrokenOaths.Cities.Yields` for the yield bonus a finished improvement
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

  ## Start / cancel (pragdave decomposition, slice 3)

  `start_improvement/4` and `cancel_improvement/3` are the pure,
  process-unaware "domain model" home for the command logic
  `BrokenOaths.Simulation.WorldServer` used to bury inline as private `do_*`
  functions (see `.code_my_spec/knowledge/genserver_decomposition.md`).
  Each takes the WorldServer's own tick-`state` plus plain args and
  returns `{:ok, new_state} | {:error, reason}` (or, for the two read
  helpers `tile_improvement_at/2`/`visible_improvements/2`, the read
  value directly) — `WorldServer`'s own `handle_call` clauses are thin
  one-line delegations into this module.

  ## Advance / orphaned-builder cleanup (tick-decomposition pass)

  `advance/1` and `clear_orphaned_builders/1` are the pure "tick phase"
  home for the improvement-progress logic `BrokenOaths.Simulation.Turn`
  used to bury inline as private functions (see
  `.code_my_spec/knowledge/genserver_decomposition.md`'s "Turn (1,318)
  -> a pure pipeline that SEQUENCES each domain's own tick phase" —
  improvement advancement is squarely this module's own concept, so it
  moved home). `BrokenOaths.Simulation.Turn.tick/1` calls both, at the same
  two points in the pipeline the inline code used to run at, over the
  SAME canonical tick-`state` every other functional-core module reads.

  ## Pasture (story 905)

  Unlike Farm/Mine/Road, which gate purely on TERRAIN
  (`allowed?/2`), Pasture gates on the tile's bonus RESOURCE
  (`BrokenOaths.Worlds.Resources.at/2` returning `:cattle` or
  `:sheep` — the two animal resources) as well as the building
  worker's OWNER having completed Animal Husbandry
  (`BrokenOaths.Technology.Research.pasture_enabled?/1`). Neither of those
  is terrain, so `resource_allowed?/1` — not `allowed?/2` — is the
  gate `validate_improvement_terrain/4` uses for this one kind, folded
  into the research check before ever calling `persist_start_improvement!/3`.

  ## Mining's 3-turn unlock (story 902)

  `duration/1` is the KIND's base — a hardcoded constant, same as
  always. `:duration` on the schema/struct is the INSTANCE's actual
  target, resolved once, at creation (this module's own
  `persist_start_improvement!/3`, moved home from `WorldServer` in the
  pragdave decomposition, slice 3) from the building worker's OWNER's
  research (`BrokenOaths.Technology.Research.mine_duration/1` for a Mine,
  `duration(kind)` for Farm/Road) — improvements themselves stay
  ownerless (see above: any player's worker may resume one), so it is
  specifically "whoever's worker broke ground here first" that decided
  the pace, not whoever eventually finishes it. `advance/1` reads this
  field back (falling to `duration/1` when absent, e.g. a hand-built
  tick-state map in a unit test) instead of recomputing `duration(kind)`
  itself.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Technology.Research
  alias BrokenOaths.Units.Unit
  alias BrokenOaths.Repo
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.Resources
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
    # `BrokenOaths.Simulation.Turn` tick-state map in a unit test) simply has
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
  (`BrokenOaths.Technology.Research.pasture_enabled?/1`) separately — this
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

  # -------------------------------------------------------------------
  # Advance / orphaned-builder cleanup (moved from `BrokenOaths.Game.
  # Turn`'s own private `advance_improvements/1`/`clear_orphaned_builders/1`,
  # the tick-decomposition pass — see this module's own moduledoc and
  # `.code_my_spec/knowledge/genserver_decomposition.md`)
  # -------------------------------------------------------------------

  # `state` throughout this section is the canonical tick-state
  # described in `BrokenOaths.Simulation.Turn`.

  @doc """
  Advance every improvement (both `state.improvements`, the yield slot,
  and `state.roads`, the road slot — QA issue 5656770d) one tick: ticks
  `duration/1` forward for any improvement whose declared builder is
  still standing on its tile. A completion of a Farm or Mine spends the
  builder's build charge (story 882 playtest update, issue 1caa87e9); a
  worker that spends its last charge is expended and removed from
  `state.units` in this same phase. Roads (and Pasture) are
  charge-exempt.
  """
  @spec advance(map()) :: map()
  def advance(state) do
    {improvements, units} = advance_map(state.improvements, state.units)
    {roads, units} = advance_map(Map.get(state, :roads, %{}), units)

    %{state | improvements: improvements, units: units} |> Map.put(:roads, roads)
  end

  # Only an improvement whose declared builder is STILL standing on its
  # tile advances — "one unit per hex" means at most one candidate
  # builder can ever be present, so there's no concurrent-builder case
  # to arbitrate. Anyone else (owner or not — improvements aren't
  # owned) who later starts the same kind on this tile reattaches and
  # resumes from whatever `progress` was frozen at.
  #
  # QA issue 5656770d — the SAME advance logic, applied independently to
  # `state.improvements` (the yield slot) and `state.roads` (the Road
  # slot); this function is agnostic to which collection it's handed.
  defp advance_map(improvements, units) do
    {new_improvements, new_units} =
      Enum.map_reduce(improvements, units, fn {tile_id, improvement}, units ->
        {new_improvement, new_units} = advance_one(improvement, units)
        {{tile_id, new_improvement}, new_units}
      end)

    {Map.new(new_improvements), new_units}
  end

  defp advance_one(%{status: :complete} = improvement, units), do: {improvement, units}
  defp advance_one(%{builder_unit_id: nil} = improvement, units), do: {improvement, units}

  defp advance_one(improvement, units) do
    case Map.get(units, improvement.builder_unit_id) do
      %{tile_id: tile_id} when tile_id == improvement.tile_id ->
        finish_or_progress(improvement, units)

      _still_present ->
        {%{improvement | builder_unit_id: nil}, units}
    end
  end

  # Story 902, criterion 7628 — `improvement.duration` (set once, at
  # build-start, by `persist_start_improvement!/3` below) overrides the
  # kind's hardcoded base when present; a hand-built tick-state map
  # with no `:duration` key at all (most `BrokenOaths.Simulation.Turn` unit
  # tests, and any improvement kind that never gets a research-gated
  # override) falls back to `duration/1` exactly as before this story.
  defp finish_or_progress(improvement, units) do
    progress = improvement.progress + 1
    duration = Map.get(improvement, :duration) || duration(improvement.kind)

    if progress >= duration do
      completed = %{improvement | progress: duration, status: :complete, builder_unit_id: nil}
      {completed, spend_charge(units, improvement.builder_unit_id, improvement.kind)}
    else
      {%{improvement | progress: progress}, units}
    end
  end

  # Story 882 playtest update (issue 1caa87e9 — worker build charges,
  # Civ 6 Builder convention): a worker spends exactly one build charge
  # per COMPLETED Farm or Mine (charges are only ever consumed on
  # COMPLETION, never on starting or abandoning a build — an abandoned
  # dig never reaches `finish_or_progress/2`'s completion branch at
  # all, so it costs nothing by construction). Roads are charge-exempt
  # (matching Civ 6, where Builders never spend a charge on a road) and
  # so is Pasture here — story 905 postdates this charges shaping and
  # names only Farm/Mine in its rule text, so Pasture is left
  # charge-exempt pending an explicit PM call. A worker with no charges
  # left after this decrement is expended: removed from `state.units`
  # outright, in the SAME tick its last charge is spent — the same
  # removal path `BrokenOaths.Simulation.WorldServer.persist_unit_changes/2`
  # already sweeps a combat death through (diffs `state.units`, deletes
  # whatever's missing).
  defp spend_charge(units, unit_id, kind) when kind in [:farm, :mine] do
    case Map.get(units, unit_id) do
      nil ->
        units

      unit ->
        case Map.get(unit, :charges, 3) - 1 do
          remaining when remaining <= 0 -> Map.delete(units, unit_id)
          remaining -> Map.put(units, unit_id, Map.put(unit, :charges, remaining))
        end
    end
  end

  defp spend_charge(units, _unit_id, _kind), do: units

  # `advance/1` (above) already clears a builder that's gone or walked
  # away — but only as of the START of this tick. Combat
  # (`BrokenOaths.Simulation.Turn.BarbarianPhase`'s barbarian AI loop, or a
  # player's own "attack") can kill a unit LATER in this SAME tick,
  # after `advance/1` already ran; if that unit was mid-build, its
  # improvement still carries a `builder_unit_id` pointing at a row
  # `persist_unit_changes` is about to delete, and the FIRST subsequent
  # write to that improvement (progress banked this same tick, say)
  # would violate the `game_improvements` table's own foreign key. A
  # final sweep right before persistence — cheap, only ever a no-op
  # unless combat just happened — keeps this consistent regardless of
  # which combat path did the killing.
  @doc """
  Clear any `builder_unit_id` whose unit no longer exists in
  `state.units` (combat may have killed a mid-build unit later in this
  SAME tick, after `advance/1` already ran) — a final sweep right
  before persistence.
  """
  @spec clear_orphaned_builders(map()) :: map()
  def clear_orphaned_builders(state) do
    %{state | improvements: clear_orphaned_builders_map(state.improvements, state.units)}
    |> Map.put(:roads, clear_orphaned_builders_map(Map.get(state, :roads, %{}), state.units))
  end

  defp clear_orphaned_builders_map(improvements, units) do
    Map.new(improvements, fn
      {tile_id, %{builder_unit_id: id} = improvement} when not is_nil(id) ->
        if Map.has_key?(units, id) do
          {tile_id, improvement}
        else
          {tile_id, %{improvement | builder_unit_id: nil}}
        end

      {tile_id, improvement} ->
        {tile_id, improvement}
    end)
  end

  # -------------------------------------------------------------------
  # Start / cancel (moved from WorldServer's `do_start_improvement/4`/
  # `do_cancel_improvement/3`, stories 882/893, QA issue 8aa2c571)
  # -------------------------------------------------------------------

  @doc "Start (or resume) building `kind` on the worker `unit_id`'s own tile."
  @spec start_improvement(map(), map(), integer(), kind() | String.t()) ::
          {:ok, map()} | {:error, atom()}
  def start_improvement(state, user, unit_id, kind) do
    with {:ok, unit} <- owned_worker(state, user, unit_id),
         {:ok, kind} <- parse_kind(kind),
         :ok <- validate_improvement_terrain(state, unit.tile_id, kind, unit.player_id),
         :ok <- validate_improvement_slot(state, unit.tile_id, kind) do
      improvement = persist_start_improvement!(state, unit, kind)
      {:ok, put_improvement(state, kind, unit.tile_id, improvement)}
    end
  end

  # QA issue 5656770d — a Road (`state.roads`) and the tile's yield
  # improvement (Farm/Mine/Pasture, `state.improvements`) are
  # independent slots; see this module's own moduledoc.
  @doc "Store `improvement` in the right in-memory slot for `kind` — `state.roads` for `:road`, `state.improvements` otherwise."
  @spec put_improvement(map(), kind(), integer(), map()) :: map()
  def put_improvement(state, :road, tile_id, improvement),
    do: %{state | roads: Map.put(state.roads, tile_id, improvement)}

  def put_improvement(state, _kind, tile_id, improvement),
    do: %{state | improvements: Map.put(state.improvements, tile_id, improvement)}

  # QA issue 8aa2c571 — see `BrokenOaths.Game.cancel_improvement/3`'s doc.
  # Deletes the DB row outright (rather than merely clearing
  # `builder_unit_id`, the way a worker simply walking away already
  # does at a turn boundary — see `advance_one/2` above) so that SLOT
  # comes back completely empty, free for any kind that shares it. QA
  # issue 5656770d — a tile can now carry an active build in BOTH slots
  # at once (a Road building alongside a Farm, say); this cancels
  # whichever one `active_building/2` finds, preferring the yield slot
  # (`state.improvements`) over the road slot (`state.roads`) when —
  # the rare case — both are mid-build on the same tile, the same
  # tie-break `visible_improvements/2`'s list order and the UI's own
  # `worker_current_dig/2` (`Enum.find`, first match) already use.
  @doc "Cancel whichever improvement `unit_id` (a worker) is actively building on its own tile."
  @spec cancel_improvement(map(), map(), integer()) :: {:ok, map()} | {:error, atom()}
  def cancel_improvement(state, user, unit_id) do
    with {:ok, unit} <- owned_worker(state, user, unit_id),
         {:ok, collection} <- active_building(state, unit.tile_id) do
      kind = state |> Map.fetch!(collection) |> Map.fetch!(unit.tile_id) |> Map.fetch!(:kind)
      persist_cancel_improvement!(state, unit.tile_id, kind)
      new_collection = state |> Map.fetch!(collection) |> Map.delete(unit.tile_id)
      {:ok, Map.put(state, collection, new_collection)}
    end
  end

  # Only a `:building` improvement is cancelable — the same status
  # `BrokenOathsWeb.GameLive.Play`'s `worker_current_dig/2` gates the
  # dig-progress badge (and the Cancel button beside it) on, so the
  # button never offers to cancel something that isn't there to cancel
  # (a `:complete` improvement, or a `:pillaged` one nobody has resumed
  # repairing yet). Returns which COLLECTION (`:improvements` or
  # `:roads`) the active build lives in, since a tile can now have one
  # building in each independently (QA issue 5656770d).
  defp active_building(state, tile_id) do
    cond do
      match?(%{status: :building}, Map.get(state.improvements, tile_id)) -> {:ok, :improvements}
      match?(%{status: :building}, Map.get(state.roads, tile_id)) -> {:ok, :roads}
      true -> {:error, :no_active_build}
    end
  end

  defp persist_cancel_improvement!(state, tile_id, kind) do
    case Repo.get_by(__MODULE__, world_id: state.world.id, tile_id: tile_id, kind: kind) do
      nil -> :ok
      improvement -> do_delete_improvement(improvement)
    end
  end

  defp do_delete_improvement(improvement) do
    {:ok, _deleted} = Repo.delete(improvement)
    :ok
  end

  defp owned_worker(state, user, unit_id) do
    player = find_player(state, user.id)
    unit = Map.get(state.units, unit_id)

    cond do
      is_nil(player) or is_nil(unit) or unit.player_id != player.id -> {:error, :not_owner}
      unit.type != :worker -> {:error, :not_worker}
      true -> {:ok, unit}
    end
  end

  defp parse_kind(kind) when kind in [:farm, :mine, :road, :pasture], do: {:ok, kind}
  defp parse_kind("farm"), do: {:ok, :farm}
  defp parse_kind("mine"), do: {:ok, :mine}
  defp parse_kind("road"), do: {:ok, :road}
  defp parse_kind("pasture"), do: {:ok, :pasture}
  defp parse_kind(_other), do: {:error, :invalid_improvement}

  # Pasture (story 905) gates on the tile's RESOURCE
  # (`resource_allowed?/1` — Cattle/Sheep only) and the building
  # worker's OWNER having researched Animal Husbandry
  # (`Research.pasture_enabled?/1`), never on `allowed?/2`'s terrain
  # table — that table is Farm/Mine/Road's own gate only.
  defp validate_improvement_terrain(state, tile_id, :pasture, player_id) do
    cond do
      Regions.tile_class(state.world, tile_id) != :land ->
        {:error, :invalid_terrain}

      not resource_allowed?(Resources.at(state.world, tile_id)) ->
        {:error, :invalid_terrain}

      not Research.pasture_enabled?(player_research_for(state, player_id)) ->
        {:error, :invalid_terrain}

      true ->
        :ok
    end
  end

  # Mine (QA issue 5a30ad3f) gates on the resource-aware
  # `mine_allowed?/2` — Hills relief OR a Copper deposit that
  # `Resources.ensure_reachable_copper/3` may have guaranteed onto a
  # non-Hills tile — rather than the terrain-only `allowed?/2` below.
  defp validate_improvement_terrain(state, tile_id, :mine, _player_id) do
    cond do
      Regions.tile_class(state.world, tile_id) != :land ->
        {:error, :invalid_terrain}

      not mine_allowed?(
        Regions.terrain(state.world, tile_id),
        Resources.at(state.world, tile_id)
      ) ->
        {:error, :invalid_terrain}

      true ->
        :ok
    end
  end

  defp validate_improvement_terrain(state, tile_id, kind, _player_id) do
    cond do
      Regions.tile_class(state.world, tile_id) != :land ->
        {:error, :invalid_terrain}

      not allowed?(kind, Regions.terrain(state.world, tile_id)) ->
        {:error, :invalid_terrain}

      true ->
        :ok
    end
  end

  # QA issue 5656770d — Road and the tile's yield improvement
  # (Farm/Mine/Pasture) occupy INDEPENDENT slots (see this module's own
  # moduledoc): a `:road` request only ever checks `state.roads` for
  # this tile, and every other kind only ever checks
  # `state.improvements` — neither slot's occupant blocks the other, so
  # a worker can build a Road across a tile that already carries (or is
  # still building) a Farm/Mine/Pasture, and vice versa.
  #
  # Within a single slot, a completed improvement refuses any second
  # dig. An in-progress one of the SAME kind just reattaches (any
  # worker may resume a frozen dig — improvements aren't owned); a
  # DIFFERENT kind already mid-build in the SAME slot is refused rather
  # than silently switched (this can only ever happen for the yield
  # slot, since `state.roads` only ever holds `:road`). A pillaged one
  # (story 893) is the same "resume the same kind" story, just entered
  # from `:pillaged` instead of `:building`.
  defp validate_improvement_slot(state, tile_id, :road),
    do: slot_status(Map.get(state.roads, tile_id), :road)

  defp validate_improvement_slot(state, tile_id, kind),
    do: slot_status(Map.get(state.improvements, tile_id), kind)

  defp slot_status(nil, _kind), do: :ok
  defp slot_status(%{status: :complete}, _kind), do: {:error, :occupied_improvement}
  defp slot_status(%{status: :building, kind: kind}, kind), do: :ok
  defp slot_status(%{status: :building}, _kind), do: {:error, :invalid_improvement}
  defp slot_status(%{status: :pillaged, kind: kind}, kind), do: :ok
  defp slot_status(%{status: :pillaged}, _kind), do: {:error, :invalid_improvement}

  # A truly NEW improvement (no row yet on this tile) resolves its
  # `duration` once, here, from the BUILDING WORKER'S OWNER's research
  # (story 902, criterion 7628 — see this module's own moduledoc,
  # "Mining's 3-turn unlock") — a worker resuming an EXISTING row
  # (interrupted, or pillaged-and-repairing) never re-resolves it, so a
  # dig's target pace is fixed at build-start regardless of who later
  # finishes it.
  defp persist_start_improvement!(state, unit, kind) do
    case Repo.get_by(__MODULE__, world_id: state.world.id, tile_id: unit.tile_id, kind: kind) do
      nil ->
        {:ok, improvement} =
          %__MODULE__{}
          |> changeset(%{
            world_id: state.world.id,
            tile_id: unit.tile_id,
            kind: kind,
            progress: 0,
            status: :building,
            duration: improvement_duration(state, unit, kind),
            builder_unit_id: unit.id
          })
          |> Repo.insert()

        improvement_map(improvement)

      existing ->
        {:ok, improvement} =
          existing |> changeset(%{builder_unit_id: unit.id}) |> Repo.update()

        improvement_map(improvement)
    end
  end

  defp improvement_duration(state, unit, :mine),
    do: Research.mine_duration(player_research_for(state, unit.player_id))

  defp improvement_duration(_state, _unit, kind), do: duration(kind)

  # -------------------------------------------------------------------
  # Reads (moved from WorldServer's `tile_improvement_at/2`/
  # `road_improvement_at/2`/`visible_improvements/2`/`format_improvement/2`)
  # -------------------------------------------------------------------

  @doc "The `:complete` yield-slot kind on `tile_id` (falling back to a `:complete` road), or `nil`."
  @spec tile_improvement_at(map(), integer()) :: kind() | nil
  def tile_improvement_at(state, tile_id) do
    case Map.get(state.improvements, tile_id) do
      %{status: :complete, kind: kind} -> kind
      _other -> road_improvement_at(state, tile_id)
    end
  end

  @doc "The `:complete` road kind on `tile_id`, or `nil`."
  @spec road_improvement_at(map(), integer()) :: kind() | nil
  def road_improvement_at(state, tile_id) do
    case Map.get(state.roads, tile_id) do
      %{status: :complete, kind: kind} -> kind
      _other -> nil
    end
  end

  # Improvements follow the same fog rule as camps: a player sees a
  # tile's improvement only in their home region or once the tile is
  # explored — hidden tiles never leak their contents over the wire.
  # QA issue 5656770d — a tile's yield improvement (`state.improvements`)
  # and its Road (`state.roads`) are now independent, so both are
  # emitted here when present; the board's own improvement billboard
  # loop (`assets/js/globe_render.js`) draws every entry it's handed,
  # offsetting a `:road` sprite so it never fully overlaps a
  # Farm/Mine/Pasture sprite on the same tile.
  @doc "Every improvement (yield-slot and road) visible to `user` — fog-gated the same way camps are."
  @spec visible_improvements(map(), map()) :: [map()]
  def visible_improvements(state, user) do
    case find_player(state, user.id) do
      nil ->
        []

      player ->
        home = player_region_tiles(state.world, player.region_id)
        explored = Map.get(state.explored, player.id, MapSet.new())

        visible? = fn tile_id ->
          MapSet.member?(home, tile_id) or MapSet.member?(explored, tile_id)
        end

        yield_improvements =
          for {tile_id, imp} <- state.improvements,
              visible?.(tile_id),
              do: format_improvement(tile_id, imp)

        roads =
          for {tile_id, imp} <- state.roads,
              visible?.(tile_id),
              do: format_improvement(tile_id, imp)

        yield_improvements ++ roads
    end
  end

  defp format_improvement(tile_id, imp),
    do: %{tile_id: tile_id, kind: imp.kind, status: imp.status, progress: imp.progress}

  # -------------------------------------------------------------------
  # Shared, trivial lookups — duplicated rather than reaching back into
  # `WorldServer`, matching the sibling `Rebellion.War`'s own "pure,
  # process-unaware, unit-testable with no GenServer running" contract
  # (small private helper copies rather than expanding public APIs).
  # -------------------------------------------------------------------

  defp find_player(state, user_id) do
    state.players |> Map.values() |> Enum.find(&(&1.user_id == user_id))
  end

  defp player_research_for(state, player_id),
    do: Map.get(state.player_research, player_id, Research.new())

  defp player_region_tiles(world, region_id) do
    world |> Regions.partition() |> Map.fetch!(:regions) |> Map.fetch!(region_id) |> MapSet.new()
  end

  defp improvement_map(%__MODULE__{} = i) do
    %{
      tile_id: i.tile_id,
      kind: i.kind,
      progress: i.progress,
      status: i.status,
      duration: i.duration,
      builder_unit_id: i.builder_unit_id
    }
  end
end
