defmodule BrokenOaths.Game.Rebellion do
  @moduledoc """
  The first-class Rebellion record (stories 915/917/919): "declared →
  active → ended" (`.code_my_spec/knowledge/feudal_vassalage_design.md`,
  "Round 2 — first-class Rebellion"). Declaring independence (915, or
  via the story-917 "seize the moment" prompt fired the moment a lord's
  Lord unit dies) creates this row `active`, naming the rebel and their
  former lord, and it settles EXACTLY ONCE into one of three ended
  statuses (919): `independence_won`, `crushed`, or `peace` — never
  back to `active`.

  Mirrors `BrokenOaths.Game.Vassalage`'s own split with `BrokenOaths.
  Game.Vassalization`: this module owns the schema, `t()`, and the
  changeset (invalid states impossible); its sibling
  `BrokenOaths.Game.Rebellion.Resolution`, in this same file per this
  component's own task, owns the PURE business math (city-rise
  formula, army sizing, end-condition detection, peace, heir
  retention) — no `Repo`, no process state, same "pure changesets/pure
  math, no I/O" role `Vassalization` already documents for itself.

  ## Fields

    * `rebel_player_id` / `former_lord_player_id` — the two parties;
      always distinct (`validate_rebel_and_lord_distinct/1`), mirroring
      `Vassalage`'s own lord/vassal distinctness guard.
    * `status` — `:active` (default) while the war is undecided, then
      exactly one of `:independence_won` | `:crushed` | `:peace`.
    * `started_turn` — the world-turn the declaration fired, so a later
      "N consecutive turns held" check has a fixed anchor
      (`Resolution.independence_won?/3`).
    * `risen_city_ids` / `loyal_city_ids` — which of the rebel's
      occupied cities rose back to them vs stayed loyal to the former
      lord, AT THE MOMENT of declaration (`Resolution.
      resolve_risings/4` computes the split; this row just records it).
      Loyal cities are never re-derived later — they're retaken only by
      the pre-existing, ordinary siege mechanic (906), same as any
      other contested city.
    * `army_size` — the size of the temporary rebellion army spawned at
      declaration (`Resolution.army_size/1`, delegating to `OathStrain.
      rebellion_army_size/1`). Recorded here so "it records... the
      spawned temporary army" (criterion 7747) has a durable source of
      truth independent of the units themselves (which disband once the
      war ends).
    * `peace_outcome` / `reparations_gold` — only ever set together with
      `status: :peace`. A negotiated peace resolves to exactly one of
      two clean outcomes (`:restored_vassal` | `:independence`) — see
      `Resolution.resolve_peace/3` and `validate_peace_outcome/1` below,
      which make "peace with no outcome" and "an outcome without peace"
      both unrepresentable.

  ## Scope note

  This module (schema + migration + `Resolution`'s pure math) is the
  full extent of THIS task. Wiring `declare_independence`/
  `confirm_declare_independence`/`open_independence_preview`/
  `offer_peace`/`accept_peace`/`reject_peace` event handlers, spawning
  the actual temporary units, turn-by-turn win/lose detection, the
  `"game:rebellion*"` push notifications, and reconciling this story's
  heir logic with the already-shipped, unconditional `WorldServer.
  schedule_heir_if_lord_fell/3` (story 896) are a SEPARATE, later,
  coordinated integration step — see `Resolution`'s own moduledoc for
  the heir-reconciliation note in particular.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BrokenOaths.Game.Player
  alias BrokenOaths.Worlds.World

  @type status :: :active | :independence_won | :crushed | :peace
  @type peace_outcome :: :restored_vassal | :independence

  @type t :: %__MODULE__{
          id: integer() | nil,
          status: status(),
          started_turn: integer() | nil,
          risen_city_ids: [integer()],
          loyal_city_ids: [integer()],
          army_size: integer(),
          peace_outcome: peace_outcome() | nil,
          reparations_gold: integer() | nil,
          world_id: integer() | nil,
          rebel_player_id: integer() | nil,
          former_lord_player_id: integer() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t(),
          rebel_player: Player.t() | Ecto.Association.NotLoaded.t(),
          former_lord_player: Player.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "game_rebellions" do
    field :status, Ecto.Enum, values: [:active, :independence_won, :crushed, :peace], default: :active
    field :started_turn, :integer
    field :risen_city_ids, {:array, :integer}, default: []
    field :loyal_city_ids, {:array, :integer}, default: []
    field :army_size, :integer, default: 0
    field :peace_outcome, Ecto.Enum, values: [:restored_vassal, :independence]
    field :reparations_gold, :integer

    belongs_to :world, World
    belongs_to :rebel_player, Player
    belongs_to :former_lord_player, Player

    timestamps()
  end

  @doc false
  def changeset(rebellion, attrs) do
    rebellion
    |> cast(attrs, [
      :world_id,
      :rebel_player_id,
      :former_lord_player_id,
      :status,
      :started_turn,
      :risen_city_ids,
      :loyal_city_ids,
      :army_size,
      :peace_outcome,
      :reparations_gold
    ])
    |> validate_required([
      :world_id,
      :rebel_player_id,
      :former_lord_player_id,
      :status,
      :started_turn,
      :risen_city_ids,
      :loyal_city_ids,
      :army_size
    ])
    |> validate_number(:started_turn, greater_than_or_equal_to: 0)
    |> validate_number(:army_size, greater_than_or_equal_to: 0)
    |> validate_optional_number(:reparations_gold, greater_than_or_equal_to: 0)
    |> validate_rebel_and_lord_distinct()
    |> validate_peace_outcome()
    |> validate_status_transition()
    |> assoc_constraint(:world)
    |> assoc_constraint(:rebel_player)
    |> assoc_constraint(:former_lord_player)
  end

  # validate_number chokes on an explicit `nil` change (it isn't a
  # number) — only run it when the optional field actually carries a
  # real value, the same guard shape `reparations_gold`/`peace_outcome`
  # both need since they're nil until a peace resolves.
  defp validate_optional_number(changeset, field, opts) do
    case get_change(changeset, field) do
      nil -> changeset
      _value -> validate_number(changeset, field, opts)
    end
  end

  # A rebel never rebels against themselves — mirrors Vassalage's own
  # validate_lord_and_vassal_distinct/1.
  defp validate_rebel_and_lord_distinct(changeset) do
    rebel_id = get_field(changeset, :rebel_player_id)
    lord_id = get_field(changeset, :former_lord_player_id)

    if is_nil(rebel_id) or is_nil(lord_id) or rebel_id != lord_id do
      changeset
    else
      add_error(changeset, :rebel_player_id, "can't be the same as the former lord")
    end
  end

  # A negotiated peace is BINARY (`resolve_restored_vassal` or
  # `independence`) and never optional once `status` is `:peace`;
  # conversely `peace_outcome` is meaningless (and forbidden) for any
  # other status — makes "peace with no outcome" and "an outcome with
  # no peace" both unrepresentable.
  defp validate_peace_outcome(changeset) do
    case get_field(changeset, :status) do
      :peace -> validate_required(changeset, [:peace_outcome])
      _other -> reject_peace_outcome_outside_peace(changeset)
    end
  end

  defp reject_peace_outcome_outside_peace(changeset) do
    case get_field(changeset, :peace_outcome) do
      nil -> changeset
      _outcome -> add_error(changeset, :peace_outcome, "can only be set when status is peace")
    end
  end

  # The "transitions exactly once" guard: once `status` has settled to
  # anything other than `:active`, no further status change is ever
  # accepted — not back to `:active`, not to a DIFFERENT ended status.
  # A no-op change (new value == the value already persisted) is not a
  # transition at all and always passes through untouched.
  defp validate_status_transition(changeset) do
    data_status = changeset.data.status
    new_status = get_change(changeset, :status)

    cond do
      is_nil(new_status) -> changeset
      new_status == data_status -> changeset
      data_status == :active -> changeset
      true -> add_error(changeset, :status, "cannot change once a rebellion has ended (already #{data_status})")
    end
  end
end

defmodule BrokenOaths.Game.Rebellion.Resolution do
  @moduledoc """
  PURE resolution math for `BrokenOaths.Game.Rebellion` (stories
  915/917/919) — no `Repo`, no `IO`, no process state. Every function
  here takes plain data (a `Rebellion.t()`, primitive numbers, or the
  same open `city()`/`unit()` maps `BrokenOaths.Game.Siege` already
  works with) and returns a new value or an `Ecto.Changeset.t()` — the
  caller (the FUTURE `WorldServer` integration, out of THIS task's own
  scope) is responsible for all `Repo` writes, unit spawning/removal,
  and push notifications.

  ## City rise rule (story 915's own "Three Amigos" open item — LOCKED
  here as this component's own deterministic formula)

  A city rises to the rebel iff `tyranny_score(lord_honor, tribute_rate)
  >= city_resistance(seed, tile_id)`:

    * `tyranny_score/2` — 0..100, INCREASING as the lord's Honor falls
      and as their tribute rate rises (so a dishonorable, heavy-taxing
      lord scores high — "tyranny"). Honor's own domain is deliberately
      UNCLAMPED elsewhere in this codebase (`BrokenOaths.Game.Tribute`'s
      own moduledoc: "the execute-garrison penalty's own unclamped
      `honor - N` shape") — this function accepts any integer Honor and
      clamps it to `0..100` internally before scoring, rather than
      guarding the caller's domain the way `OathStrain` guards `strain`
      (Honor simply isn't bounded the way `strain` is elsewhere in this
      batch). `tribute_rate` IS guarded to its own real `0.0..1.0`
      domain (`Vassalage.tribute_rate`'s own bounds) — an out-of-domain
      rate crashes the calling process. Honor and tribute rate are
      weighted EQUALLY (`@honor_weight == @tribute_weight == 0.5`) — a
      balancing pass, not a blocker, exactly the stance `OathStrain`'s
      own moduledoc already takes for ITS magnitude constants; only the
      RELATIONSHIP is locked (falling Honor and rising tribute both
      raise tyranny, monotonically, never the reverse).
    * `city_resistance/2` — 0..100, a STABLE, DETERMINISTIC per-city
      value derived from `:erlang.phash2({seed, tile_id}, 101)` — NOT
      live RNG, so the SAME `(seed, tile_id)` pair always resistances
      the same, inspectable BEFORE the player commits (criterion
      7732's own preview) and reproducible turn after turn. Because
      resistance is roughly uniform across `0..100` per city while
      `tyranny_score` is a single lord-wide number, a tyrant (high
      score) clears most cities' resistance and a just lord (low score)
      clears almost none — "a tyrant frees MOST cities, a just lord
      keeps most" falls directly out of comparing one fixed threshold
      against many independently-hashed per-city values, without any
      per-city RNG roll at resolution time.

  `city_rises?/4` is the per-city verdict (`criterion_7732`'s own
  preview reads this exactly); `resolve_risings/4` is the batch form
  `criterion_7734`'s/`criterion_7736`'s own multi-city resolution needs,
  returning `{risen_city_ids, loyal_city_ids}` — a `Rebellion.
  changeset/2`-ready pair.

  ## Army sizing

  `army_size/1` is a thin, deliberate delegation to the ALREADY-BUILT
  `BrokenOaths.Game.OathStrain.rebellion_army_size/1` (story 913) —
  this module does not re-derive the strain -> army-size curve, it only
  owns WHICH strain reading feeds it (the rebel's own Oath Strain
  against the former lord, read by the future integration off the
  `Vassalage` row that existed the instant before it was severed).

  ## End conditions (919)

  `crushed?/2` and `independence_won?/3` are read-only PREDICATES over
  a `Rebellion.t()` and the current board's own `city()` maps — they
  never write anything; the caller decides what to DO once one reads
  `true` (typically: call `crush/1` or `win_independence/1` below, then
  persist the resulting changeset).

    * `crushed?/2` — true once the former lord holds (`occupied_by_
      player_id == former_lord_player_id`) EVERY one of the rebellion's
      own `risen_city_ids` again ("the former lord retakes AND HOLDS
      the contested cities" — plural, ALL of them; a PARTIAL retaking
      leaves the war merely contested, not yet crushed, matching the
      design doc's own "contested (neither fully controls until it
      flips or is re-secured)" wartime-control note). Always `false` for
      a rebellion with an EMPTY `risen_city_ids` — nothing rose, so there
      is nothing here for the former lord to retake; that rebel's own
      fate instead turns on `rebel_defeated?/2`, a SEPARATE predicate
      (see its own doc below for why the two are kept apart rather than
      combined into one opinionated `crushed?/2`).
    * `rebel_defeated?/2` — `Siege.no_free_cities?/2` applied to the
      rebel: true once the rebel's own last free city (whichever
      city — risen or otherwise) falls to anyone. Kept SEPARATE from
      `crushed?/2` rather than OR'd into it here: for a rebel whose
      cities never rose at all (`risen_city_ids == []`), this predicate
      is vacuously true from the moment they declare (every city they
      have was already occupied, or they'd have never been a vassal to
      begin with) — folding it unconditionally into `crushed?/2` would
      make a "few or none rise" rebellion (criterion 7735) crushed
      instantly, contradicting "Wes remains at war... with those cities
      still to be taken by force." Combining the two into a single
      "is this rebellion over" verdict needs the caller's own turn-by-
      turn knowledge of whether the rebel ever HELD a free city during
      the war at all — real state this pure module doesn't track and
      doesn't fabricate an answer for; flagging this here as the one
      open combination decision the future integration owns.
    * `independence_won?/3` — true once EVERY one of `risen_city_ids`
      reads free (`occupied_by_player_id` is `nil`) AND at least
      `independence_hold_turns/0` turns have passed since `started_
      turn`. Always `false` for an empty `risen_city_ids` — holding
      zero freed cities is not a win condition; a rebel who freed
      nothing cannot win by merely waiting (see `crushed?/2`'s own
      note above for the same "empty risen list" carve-out).

  `independence_hold_turns/0` (`N = 5`) is an explicit, still-OPEN
  balancing placeholder — the design doc's own "Three Amigos" note lists
  "the 'hold for N turns' threshold" as unresolved, and this component
  picks its own concrete number purely so the predicate above is
  computable today. A future integration (or the story-919 spex, which
  independently picked their own placeholder `10`) is free to move this
  constant; nothing else in this module depends on its exact value.

  ## Status transitions

  `win_independence/1` and `crush/1` build the (once-only, changeset-
  guarded — see `Rebellion.changeset/2`'s own `validate_status_
  transition/1`) `:independence_won`/`:crushed` transition. Both are
  ALSO guarded at the function-clause level (`%Rebellion{status:
  :active}`) — calling either on an already-ended rebellion raises a
  `FunctionClauseError` rather than silently building a doomed
  changeset (`.code_my_spec/rules/elixir.md`: "Crash the process rather
  than propagating invalid data through the system").

  ## Peace (919) — BINARY only

  `resolve_peace/3` accepts only `:restored_vassal` or `:independence`
  as `outcome` — "nobody loses cities in a peace" (both binary outcomes
  keep the rebel's OWN cities theirs; the difference is purely whether
  the Vassalage itself is restored) — with an optional `reparations_
  gold` passed straight through to the built changeset. "If the sides
  cannot agree, the war simply continues" needs no function here at
  all: refusing an offer is simply never calling this — the rebellion
  stays `:active` by doing nothing.

  ## Heir helper (story 917) — a pure decision only

  `heir_retained_vassals/3` answers "which of a fallen lord's own
  vassals does the respawned heir keep lordship over": every vassal who
  did NOT win independence (`:independence_won`) against that SAME
  `former_lord_player_id` during the leaderless window. This is
  intentionally the FULL extent of story 917's heir logic this task
  owns — a pure decision function, no `Repo`, no timing.

  **Integration note, NOT wired here:** `BrokenOaths.Game.WorldServer`
  already ships `schedule_heir_if_lord_fell/3` (story 896) — an
  UNCONDITIONAL heir respawn exactly 10 turns after ANY Lord unit's
  death, with no awareness of `Vassalage` or `Rebellion` at all. Story
  917's own locked design instead ties heir arrival to "the last active
  rebellion against the realm resolves" — a materially different,
  war-duration-dependent trigger. These two mechanics are NOT
  reconciled by this task (see this batch's own task instructions:
  "do NOT modify `world_server.ex`... a SEPARATE coordinated
  integration step"); the future integration must make story 917's
  rebellion-gated trigger SUPERSEDE (not duplicate alongside) the old
  flat 10-turn timer once a lord has any vassals, while presumably
  still leaving the flat timer's own behavior intact for a lord who
  dies with NO vassals at all (criterion 7750's own "a quiet death still
  brings an heir" case, which the old mechanic already satisfies
  correctly on its own).
  """

  alias BrokenOaths.Game.OathStrain
  alias BrokenOaths.Game.Rebellion
  alias BrokenOaths.Game.Siege

  @type city :: Siege.city()
  @type player_id :: integer()
  @type seed :: integer()
  @type tile_id :: Siege.tile_id()
  @type honor :: integer()
  @type tribute_rate :: float()

  defguardp valid_tribute_rate(rate) when is_float(rate) and rate >= 0.0 and rate <= 1.0

  # -------------------------------------------------------------------
  # City rise rule
  # -------------------------------------------------------------------

  @honor_weight 0.5
  @tribute_weight 0.5

  @doc """
  0..100 tyranny score for a lord: rises as `lord_honor` falls and as
  `tribute_rate` rises, weighted equally. `lord_honor` accepts any
  integer (Honor is unclamped elsewhere in this codebase) and is
  clamped to `0..100` internally; `tribute_rate` must be a real
  `0.0..1.0` rate — an out-of-domain rate crashes the calling process.
  """
  @spec tyranny_score(honor(), tribute_rate()) :: 0..100
  def tyranny_score(lord_honor, tribute_rate) when is_integer(lord_honor) and valid_tribute_rate(tribute_rate) do
    honor_component = (100 - clamp_to_100(lord_honor)) * @honor_weight
    tribute_component = tribute_rate * 100 * @tribute_weight

    (honor_component + tribute_component)
    |> round()
    |> clamp_to_100()
  end

  @doc """
  A stable, deterministic 0..100 resistance value for one city, derived
  from `seed` and the city's own `tile_id` — NOT live RNG. The SAME
  `(seed, tile_id)` pair always produces the SAME resistance, so the
  outcome is inspectable before a player commits and reproducible on
  every later resolution.
  """
  @spec city_resistance(seed(), tile_id()) :: 0..100
  def city_resistance(seed, tile_id) when is_integer(seed) and is_integer(tile_id) do
    :erlang.phash2({seed, tile_id}, 101)
  end

  @doc "Whether one city rises to the rebel: `tyranny_score/2 >= city_resistance/2`."
  @spec city_rises?(honor(), tribute_rate(), seed(), tile_id()) :: boolean()
  def city_rises?(lord_honor, tribute_rate, seed, tile_id) do
    tyranny_score(lord_honor, tribute_rate) >= city_resistance(seed, tile_id)
  end

  @doc """
  Splits `cities` into `{risen_city_ids, loyal_city_ids}` per
  `city_rises?/4`, applied per city's own `tile_id`.
  """
  @spec resolve_risings(honor(), tribute_rate(), seed(), [city()]) :: {[term()], [term()]}
  def resolve_risings(lord_honor, tribute_rate, seed, cities) do
    {risen, loyal} = Enum.split_with(cities, &city_rises?(lord_honor, tribute_rate, seed, &1.tile_id))

    {Enum.map(risen, & &1.id), Enum.map(loyal, & &1.id)}
  end

  defp clamp_to_100(value), do: value |> max(0) |> min(100)

  # -------------------------------------------------------------------
  # Army sizing
  # -------------------------------------------------------------------

  @doc "The temporary rebellion army size for `oath_strain` — delegates to `OathStrain.rebellion_army_size/1`."
  @spec army_size(OathStrain.strain()) :: pos_integer()
  def army_size(oath_strain), do: OathStrain.rebellion_army_size(oath_strain)

  # -------------------------------------------------------------------
  # End conditions (919)
  # -------------------------------------------------------------------

  @independence_hold_turns 5

  @doc """
  The number of consecutive turns (from the rebellion's own
  `started_turn`) a rebel must hold every one of their risen cities,
  uncontested, to win independence outright. An explicitly OPEN
  balancing placeholder (`N = 5`) — see this module's own moduledoc.
  """
  @spec independence_hold_turns() :: pos_integer()
  def independence_hold_turns, do: @independence_hold_turns

  @doc """
  Whether the former lord has retaken and now holds EVERY one of this
  rebellion's own `risen_city_ids` again. Always `false` when
  `risen_city_ids` is empty — see this module's own moduledoc for why
  that case is `rebel_defeated?/2`'s own concern instead.
  """
  @spec crushed?(Rebellion.t(), [city()]) :: boolean()
  def crushed?(%Rebellion{risen_city_ids: []}, _cities), do: false

  def crushed?(%Rebellion{former_lord_player_id: lord_id, risen_city_ids: risen}, cities) do
    cities
    |> Enum.filter(&(&1.id in risen))
    |> Enum.all?(&(Map.get(&1, :occupied_by_player_id) == lord_id))
  end

  @doc "Whether the rebel has zero free cities left among `cities` — `Siege.no_free_cities?/2` applied to the rebel."
  @spec rebel_defeated?(Rebellion.t(), [city()]) :: boolean()
  def rebel_defeated?(%Rebellion{rebel_player_id: rebel_id}, cities), do: Siege.no_free_cities?(cities, rebel_id)

  @doc """
  Whether the rebel has held EVERY one of their risen cities free (no
  re-occupation) for at least `independence_hold_turns/0` turns since
  `started_turn`. Always `false` when `risen_city_ids` is empty.
  """
  @spec independence_won?(Rebellion.t(), [city()], integer()) :: boolean()
  def independence_won?(%Rebellion{risen_city_ids: []}, _cities, _current_turn), do: false

  def independence_won?(%Rebellion{risen_city_ids: risen, started_turn: started}, cities, current_turn) do
    current_turn - started >= @independence_hold_turns and all_held_free?(risen, cities)
  end

  defp all_held_free?(risen_city_ids, cities) do
    cities
    |> Enum.filter(&(&1.id in risen_city_ids))
    |> Enum.all?(&is_nil(Map.get(&1, :occupied_by_player_id)))
  end

  # -------------------------------------------------------------------
  # Status transitions
  # -------------------------------------------------------------------

  @doc "Build the once-only `:active -> :independence_won` transition changeset."
  @spec win_independence(Rebellion.t()) :: Ecto.Changeset.t()
  def win_independence(%Rebellion{status: :active} = rebellion) do
    Rebellion.changeset(rebellion, %{status: :independence_won})
  end

  @doc "Build the once-only `:active -> :crushed` transition changeset."
  @spec crush(Rebellion.t()) :: Ecto.Changeset.t()
  def crush(%Rebellion{status: :active} = rebellion) do
    Rebellion.changeset(rebellion, %{status: :crushed})
  end

  @doc """
  Build the once-only `:active -> :peace` transition changeset. `outcome`
  is BINARY only — `:restored_vassal` (the rebel swears fealty again) or
  `:independence` (the rebel is granted full freedom) — nobody loses
  cities either way. `reparations_gold` (optional, gold paid winner to
  loser) is passed straight through, unvalidated beyond the changeset's
  own `>= 0` check.
  """
  @spec resolve_peace(Rebellion.t(), Rebellion.peace_outcome(), non_neg_integer() | nil) :: Ecto.Changeset.t()
  def resolve_peace(rebellion, outcome, reparations_gold \\ nil)

  def resolve_peace(%Rebellion{status: :active} = rebellion, outcome, reparations_gold)
      when outcome in [:restored_vassal, :independence] do
    Rebellion.changeset(rebellion, %{
      status: :peace,
      peace_outcome: outcome,
      reparations_gold: reparations_gold
    })
  end

  # -------------------------------------------------------------------
  # Heir helper (story 917) — pure decision only, see moduledoc
  # -------------------------------------------------------------------

  @doc """
  The subset of `vassal_player_ids` the respawned heir keeps lordship
  over: every one of `former_lord_player_id`'s own vassals who did NOT
  win independence (`:independence_won`) against them, per `rebellions`.
  """
  @spec heir_retained_vassals(player_id(), [player_id()], [Rebellion.t()]) :: [player_id()]
  def heir_retained_vassals(former_lord_player_id, vassal_player_ids, rebellions) do
    freed_player_ids =
      rebellions
      |> Enum.filter(&(&1.former_lord_player_id == former_lord_player_id and &1.status == :independence_won))
      |> Enum.map(& &1.rebel_player_id)
      |> MapSet.new()

    Enum.reject(vassal_player_ids, &MapSet.member?(freed_player_ids, &1))
  end
end
