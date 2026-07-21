defmodule BrokenOaths.Cities.Production do
  @moduledoc """
  Pure production core: the Stone Age buildable catalog (Settler 100,
  Worker 60, Warrior 40, Granary 60 — Monument is still out of scope,
  see story 879's own criteria) with per-type unit stats, per-turn
  production accrual, queue completion with overflow carry-over,
  completed-unit spawn placement, the settler population cost and
  size-1 guard, and city-founding validation (terrain, 4-hex spacing).
  No `Repo`: `complete/3` returns spawn intents as data (`spawn_event`)
  rather than inserting units itself — `BrokenOaths.Simulation.WorldServer`
  is the only place real unit ids get allocated.

  ## The flat production base

  Every city banks a flat 5 production per turn regardless of size or
  terrain (story 879), on top of its worked tiles' production —
  deliberately NOT the city center's own terrain-based production
  (that stays folded into the flat base; see
  `BrokenOaths.Cities.Yields`'s moduledoc). Food has no such override:
  the center's food floor accrues separately via
  `BrokenOaths.Cities.Yields.accrue_food/3`.

  ## Queue completion

  `complete/3` is a loop, not a single check: an overflow big enough to
  finish the next queued item too keeps cascading, and a fully blocked
  city (no free landing tile) simply stops with its current item's
  `banked` intact — nothing is lost, it just keeps growing next turn
  until a tile frees up (story 879, criterion 7472).

  ## Queue commands (pragdave decomposition, slice 3)

  `queue_production/4`, `reorder_production_item/4`, and
  `cancel_production_item/4` are the pure, process-unaware "domain
  model" home for the command logic `BrokenOaths.Simulation.WorldServer` used
  to bury inline as private `do_*` functions (see
  `.code_my_spec/knowledge/genserver_decomposition.md`). Each takes the
  WorldServer's own tick-`state` plus plain args and returns `{:ok,
  new_state} | {:error, reason}` — `WorldServer`'s own `handle_call`
  clauses are thin one-line delegations into this module.

  ## The Granary (story 902, criterion 7629)

  Unlike every other buildable, `:granary` is a BUILDING, not a unit:
  it needs no landing tile (`spawnable?/2`'s free-tile gate never
  applies to it) and its completion never produces a `spawn_event` —
  instead it flips `has_granary: true` directly on the completing city
  (read back by `BrokenOaths.Cities.Yields.accrue_food/3` for its +2
  food/turn bonus, the same "unlock flips a flag, read back on demand"
  pattern `BrokenOaths.Technology.Research` already documents for its own
  unlocks). Gated on the city's OWNER having completed Pottery
  (`can_queue?/3`'s `granary_available?` option) and on the city not
  already having one (`:already_built` — a Granary is built once,
  ever). `can_queue?/3` itself never touches `BrokenOaths.Technology.Research`
  directly — opts arrive pre-resolved. The resolution lives one level
  up, in `granary_available?/2`, called from `queue_production/4`
  (moved home from `WorldServer` in the pragdave decomposition, slice
  3 — previously the CALLER resolved the flag across a process
  boundary; now it's this module's own orchestration doing it, one
  function up from the pure gate it feeds).

  ## The Bronze Spearman's Copper gate (story 911, reworked for QA
  issue 3e6c124c "Copper availability wrong")

  `:bronze_spearman` needs TWO independent opts to queue, not one:
  `opts[:bronze_age?]` (story 903 — the owner has completed Bronze
  Working) AND `opts[:copper_access?]` (story 911 — see below). Missing
  Bronze Working reports `{:error, :locked}` (unchanged from story
  903 — the option never even appears in a Build UI until then, per
  `available_items/1` below); missing Copper with Bronze Working
  already done reports the more specific `{:error, :copper_required}`,
  so a caller can render "Requires Copper" rather than a generic
  locked message. As with `granary_available?/2` above, `can_queue?/3`
  stays opt-driven and dependency-free; `bronze_age?/2`/`copper_access?/2`
  do the actual `BrokenOaths.Technology.Research`/
  `BrokenOaths.Worlds.Resources` reads, called from `queue_production/4`.

  `opts[:copper_access?]` itself is no longer "does THIS city's own
  territory happen to contain a bare Copper tile" (story 911's
  original, MVP-narrow design) — QA issue 3e6c124c found that too
  permissive (no mine required) and too stingy (didn't share across a
  civilization's own cities) at once. The rule is now MINE-BASED and
  PLAYER-WIDE: `player_copper_access?/2` scans every city a PLAYER
  owns for a tile, anywhere in ANY of those cities' own `territory`,
  that carries BOTH a Copper resource (`Resources.at/2`) AND a
  COMPLETED (`status: :complete`) Mine improvement already built on
  it (`BrokenOaths.Cities.Improvement`, unlocked onto a Copper tile by
  `Improvement.mine_allowed?/2`'s own resource clause) — merely
  having Copper somewhere in a city's borders no longer counts on its
  own. Once true, the SAME single boolean unlocks `:bronze_spearman`
  in EVERY city that player owns, not only the one whose territory
  holds the mined tile — "build a mine, then build spearmen anywhere"
  per the product owner's own stated intent, mirroring how a real
  strategic resource is stockpiled and distributed across a
  civilization rather than fenced to one city's own dirt.
  `copper_access?/2` (per-CITY, singular) stays as a thin wrapper
  around `player_copper_access?/2` for callers that only have a
  `city()` map at hand (`queue_production/4` below,
  `BrokenOaths.Feudal.Stewardship.steward_city_view/2`) — it reads
  `city.player_id` and defers entirely to the player-wide rule; it
  does NOT recheck that specific city's own territory.

  ## The Archer (QA issue da39e50b "No archer")

  The expanded tech tree's Archery tech (story 902) unlocked nothing —
  `:archer` is the first-pass fix, gated on a single opt,
  `opts[:archery?]` (the owner has completed Archery), the same single-
  opt shape `:granary`'s `granary_available?` already uses. Missing
  Archery reports `{:error, :locked}` and the option never appears in a
  Build UI until then (`available_items/1` below), same as
  `:bronze_spearman`'s own `bronze_age?` gate.

  Civ 6's own Archer is a RANGED unit (attacks from 2 tiles away
  without retaliation); this game's whole combat model
  (`BrokenOaths.Combat.Resolver`) is melee/adjacent-only — no unit anywhere
  in this codebase has a ranged attack. Implementing true ranged combat
  is a genuine design/engineering project (attack range, no-retaliation
  math, a new UI affordance for "attack from range"), well beyond a bug
  fix's scope. This first pass ships the Archer as a buildable MELEE
  unit instead — real, buildable, fights (adjacent, both sides land a
  blow) — with stats scaled to sit between the Warrior and the Bronze
  Spearman (`@unit_stats`/`BrokenOaths.Combat.Resolver`'s own
  `@base_strength`): strength 14 (Warrior 10, Bronze Spearman 16), 100
  HP (Warrior's own HP), cost 40 production (cheaper than the Bronze
  Spearman's 60 — Archery is a tier-2 tech but doesn't need a strategic
  resource the way Bronze Spearman needs Copper). **True ranged attack
  (strike without retaliation, from 2 tiles away) is flagged here as a
  follow-up design item for the product owner** — this comment is that
  flag; see the QA issue's resolution for the full writeup.

  ## The Galley (story 921 — the unit-and-unlock convention's own
  exemplar, see `.code_my_spec/knowledge/unit_and_unlock_convention.md`)

  Sailing shipped as a dead tech (researchable, its own `unlock:` string
  reading "Enables Galleys and coastal exploration") with no Galley
  anywhere in the codebase — exactly the "structure-only tech advertises
  an effect it never delivers" failure that convention doc's guardrail
  exists to catch. The Galley is the fix: a real, buildable, water-only
  unit, gated on `opts[:sailing?]` (the owner has completed Sailing)
  AND `opts[:coastal?]` (THIS city has at least one adjacent
  `:coastal_water` tile — a landlocked city can never launch one, no
  matter how far along its owner's tech tree is) — the SAME two-opt
  compound-gate shape `:bronze_spearman`'s `bronze_age?`/`copper_access?`
  gate already established: `available_items/1` offers `:galley` once
  `sailing?` alone is true (so a landlocked city's owner still SEES the
  option, same "requirement legible whether or not it's met" posture
  the Copper note gives Bronze Spearman), while `can_queue?/3` refuses
  the more specific `{:error, :not_coastal}` once Sailing is done but
  this particular city isn't coastal.

  V1 is deliberately narrow (locked design decisions from story 921's
  own parked questions): water-only (no land-unit embarkation — that's
  a later story), `:coastal_water`-only (no deep-ocean sailing yet —
  another later story), no naval barbarians, no city bombardment.
  Combat is the existing `Combat.Resolver` unchanged — galley-vs-galley
  melee follows the identical adjacency/PvP rules land combat already
  enforces, nothing naval-specific about the fight itself.

  ## Story 930 — Library, Ancient Walls, Barracks, Water Mill

  Four more buildings, following the exact Granary/`building_convention.md`
  shape (own tech gate, own `_available?` opt, own `can_queue?/3`
  clause with the same `:already_built` refusal, own `available_items/1`
  offer): Library (Writing, +2 science/turn flat —
  `BrokenOaths.Technology.Research.science_per_turn/1`), Ancient Walls
  (Masonry, +50 max HP / +5 defense —
  `BrokenOaths.Combat.CityDefense`), Barracks (Bronze Working, +1
  production toward MILITARY queue items only — `accrue/3` below), and
  Water Mill (The Wheel, +1 food / +1 production flat, no river
  requirement modeled). Unlike the Granary, these four are never their
  own `has_*` boolean — see `BrokenOaths.Cities.City`'s own `buildings`
  field doc for why a FIFTH boolean (and a sixth, and a seventh) would
  have been exactly the scattered-flag growth the building convention
  warns about. `complete_loop/4`'s own `@passive_buildings` clause below
  handles all four (and any future addition to that list) with the same
  ONE clause, rather than four near-identical copies of the Granary's.

  `landing_tile/4`'s own `:galley` clause is why this module took on a
  4th arg there: a finished Galley can never land on the city's own
  (land) tile the way every other unit does, so it needs its OWN
  candidate list — the lowest-id adjacent `:coastal_water` tile that
  isn't already occupied, `Enum.sort/1`'d for determinism the way no
  other landing rule needed to care about (every land unit's own
  candidate order was already `[city.tile_id | adjacent land tiles]`,
  never sorted). No adjacent water free (or, per `available_items/1`'s
  own visible-but-refused posture, no water at all) means the item
  simply waits, same "nothing lost" posture every other blocked landing
  already has.

  ## Story 933 — the Pyramids and Hanging Gardens world wonders

  Two more buildables, but a different SHAPE from every one above:
  world-UNIQUE, not per-city. `can_queue?/3`'s `:pyramids`/
  `:hanging_gardens` clauses drop the standard buildings' own
  per-city `:already_built` refusal entirely and read a single
  `opts[:pyramids_claimed?]`/`opts[:hanging_gardens_claimed?]`
  boolean instead — `{:error, :wonder_taken}` once EITHER is true,
  resolved one level up in `queue_production/4` via
  `Buildings.wonder_built_or_building?/2` scanning every city in the
  WORLD (not just this player's own), the same "opts arrive
  pre-resolved" split every other gate here already keeps.
  `available_items/1` mirrors that same claimed-check (unlike
  `:bronze_spearman`'s Copper/`:galley`'s coastal gates, which stay
  VISIBLE-but-disabled once their own tech is done): a wonder drops
  off the list entirely, everywhere, the instant anyone claims it —
  there's no "requirement not yet met" state worth showing once a
  wonder is gone for good.

  The Hanging Gardens is otherwise an ordinary passive building —
  `@passive_buildings` below, no landing tile, no spawn event, just a
  `buildings` flip on completion, exactly like Library/Ancient
  Walls/Barracks/Water Mill. `BrokenOaths.Cities.Yields.grow_cities/2`
  is where its real effect (+15% growth, empire-wide) lives.

  The Pyramids is NOT passive: on top of the same `buildings` flip, it
  grants its owner a free Worker — `complete_loop/4`'s own `:pyramids`
  clause reuses the exact landing-tile machinery every ordinary unit
  completion already uses (`landing_tile/4`, blocked-tile-waits-a-turn
  and all), just with the SPAWNED unit's type (`:worker`) deliberately
  different from the QUEUE item's own type (`:pyramids`) — the wonder
  itself never becomes a placed unit; the free Worker it hands out
  does. The OTHER half of the Pyramids' effect — every Worker its
  owner ever builds afterward starts with 4 charges instead of 3, Civ
  6's own "+1 Builder charge" — lives in
  `BrokenOaths.Simulation.WorldServer`'s own `worker_charges/3`, since
  a unit's starting `charges` is set at the real-id-allocation step
  this pure module never performs itself (see `unit_stats/1`'s own
  doc: per-type starting stats live here, but `charges` isn't
  per-type, it's per-OWNER).
  """

  import Ecto.Query

  alias BrokenOaths.Cities.Buildings
  alias BrokenOaths.Combat.CityDefense
  alias BrokenOaths.Cities.ProductionItem
  alias BrokenOaths.Technology.Research
  alias BrokenOaths.Cities.Yields
  alias BrokenOaths.Repo
  alias BrokenOaths.Worlds.Globe
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.Resources
  alias BrokenOaths.Worlds.World

  @type tile_id :: non_neg_integer()
  @type unit_buildable :: :settler | :worker | :warrior | :bronze_spearman | :archer | :galley
  # Story 930 — the four buildings that land in `City.buildings` (as
  # opposed to `:granary`, still its own lone boolean). Story 933 adds
  # the Pyramids/Hanging Gardens wonders to the same list — see this
  # module's own moduledoc, "Story 933".
  @type building ::
          :library | :ancient_walls | :barracks | :water_mill | :pyramids | :hanging_gardens
  @type buildable :: unit_buildable() | :granary | building()
  @type unit_type ::
          :lord
          | :settler
          | :warrior
          | :worker
          | :barbarian_warrior
          | :bronze_spearman
          | :archer
          | :galley

  @type queue_item :: %{
          optional(:id) => term(),
          type: buildable(),
          banked: non_neg_integer(),
          cost: pos_integer()
        }

  @type city :: %{
          required(:player_id) => term(),
          required(:tile_id) => tile_id(),
          required(:size) => pos_integer(),
          required(:territory) => [tile_id()],
          required(:worked_tiles) => [tile_id()],
          required(:queue) => [queue_item()],
          optional(:has_granary) => boolean(),
          optional(:buildings) => [building()],
          optional(atom()) => term()
        }

  @type spawn_event :: %{player_id: term(), type: unit_buildable(), tile_id: tile_id()}
  # Playtest issue 6 — see `resolve_completions/1`'s own doc for why
  # this is a separate shape from `spawn_event()` above.
  @type completion_event :: %{user_id: term(), city_name: String.t(), type: buildable()}
  @type can_queue_error ::
          :size_one | :locked | :already_built | :copper_required | :not_coastal | :wonder_taken

  @flat_production 5
  @min_founding_spacing 4

  @catalog %{
    settler: 100,
    worker: 60,
    warrior: 40,
    granary: 60,
    bronze_spearman: 60,
    archer: 40,
    # Story 921 — see this module's own moduledoc, "The Galley": between
    # the Warrior and the Bronze Spearman, matching a tier-2-tech unit
    # with no strategic-resource gate of its own.
    galley: 50,
    # Story 930 — see this module's own moduledoc, "Library, Ancient
    # Walls, Barracks, Water Mill" — the Granary's own 60 as the
    # baseline, priced up slightly for a stronger flat effect.
    library: 90,
    ancient_walls: 80,
    barracks: 90,
    water_mill: 90,
    # Story 933 — the Pyramids/Hanging Gardens world wonders: a wonder
    # is a bigger empire-wide commitment than any standard building
    # above, priced accordingly (PM decision, see this module's own
    # moduledoc "Story 933").
    pyramids: 220,
    hanging_gardens: 220
  }

  @unit_stats %{
    lord: %{hp: 150, movement: 2},
    settler: %{hp: 50, movement: 2},
    warrior: %{hp: 100, movement: 1},
    worker: %{hp: 10, movement: 2},
    barbarian_warrior: %{hp: 120, movement: 1},
    # Story 903 — `.code_my_spec/knowledge/civ6_tech_tree.md` §5.
    bronze_spearman: %{hp: 120, movement: 1},
    # QA issue da39e50b — see this module's own moduledoc, "The Archer",
    # for the melee-for-now stats rationale and the ranged-attack flag.
    archer: %{hp: 100, movement: 1},
    # Story 921 — the Galley: the Warrior's own HP, but 2 movement (a
    # ship outpaces a foot soldier) — see this module's own moduledoc,
    # "The Galley".
    galley: %{hp: 100, movement: 2}
  }

  @doc "The buildable catalog: `%{settler: 100, worker: 60, warrior: 40}`."
  @spec catalog() :: %{buildable() => pos_integer()}
  def catalog, do: @catalog

  @doc "Every city's flat per-turn production base, before worked-tile production."
  @spec flat_base() :: pos_integer()
  def flat_base, do: @flat_production

  @doc "Production cost of a buildable type."
  @spec cost(buildable()) :: pos_integer()
  def cost(type), do: Map.fetch!(@catalog, type)

  @doc """
  A buildable's display label, e.g. `"Bronze Spearman"` for
  `:bronze_spearman` — the single source of truth `GameLive.CityPanel`
  reads (moved home from that module's own private copy) and, per the
  playtest "build complete" toast (`GameLive.Play`'s
  `{:city_completed, ...}` handler), what a completion notification
  names too.
  """
  @spec buildable_label(buildable()) :: String.t()
  def buildable_label(:settler), do: "Settler"
  def buildable_label(:worker), do: "Worker"
  def buildable_label(:warrior), do: "Warrior"
  def buildable_label(:granary), do: "Granary"
  def buildable_label(:bronze_spearman), do: "Bronze Spearman"
  def buildable_label(:archer), do: "Archer"
  def buildable_label(:galley), do: "Galley"
  def buildable_label(:library), do: "Library"
  def buildable_label(:ancient_walls), do: "Ancient Walls"
  def buildable_label(:barracks), do: "Barracks"
  def buildable_label(:water_mill), do: "Water Mill"
  def buildable_label(:pyramids), do: "Pyramids"
  def buildable_label(:hanging_gardens), do: "Hanging Gardens"

  @doc "Starting `%{hp:, movement:}` for any unit type — Lord and Settler included."
  @spec unit_stats(unit_type()) :: %{hp: pos_integer(), movement: pos_integer()}
  def unit_stats(type), do: Map.fetch!(@unit_stats, type)

  @doc "A fresh queue item for `type`, unbanked. Caller attaches an `id` once persisted."
  @spec new_item(buildable()) :: queue_item()
  def new_item(type), do: %{type: type, banked: 0, cost: cost(type)}

  @doc """
  Whether `type` can be queued right now (arity-2, backward-compatible
  shorthand for `can_queue?/3` with no options — `granary_available?`/
  `copper_access?` simply default to `false`, so a Granary or a Bronze
  Spearman is refused unless the caller explicitly opts them in).
  """
  @spec can_queue?(city(), buildable()) :: :ok | {:error, can_queue_error()}
  def can_queue?(city, type), do: can_queue?(city, type, [])

  @doc """
  Whether `type` can be queued right now: the size-1 settler rule (a
  size-1 city has no population to spare; story 883, criterion 7487),
  and — for `:granary` only (story 902) — the city's owner having
  completed Pottery (`opts[:granary_available?]`, since this
  dependency-free function never calls `BrokenOaths.Technology.Research`
  itself) and not already having one (`:already_built`). Story 903/911:
  `:bronze_spearman` needs BOTH `opts[:bronze_age?]` (Bronze Working
  completed) and `opts[:copper_access?]` (a Copper tile somewhere in
  the city's own territory) — see this module's own moduledoc, "The
  Bronze Spearman's Copper gate."
  """
  @spec can_queue?(city(), buildable(), keyword()) :: :ok | {:error, can_queue_error()}
  def can_queue?(%{size: 1}, :settler, _opts), do: {:error, :size_one}

  def can_queue?(city, :granary, opts) do
    cond do
      Map.get(city, :has_granary, false) -> {:error, :already_built}
      not Keyword.get(opts, :granary_available?, false) -> {:error, :locked}
      true -> :ok
    end
  end

  # Story 930 — Library/Ancient Walls/Barracks/Water Mill: the exact
  # same shape as `:granary` above (a single tech-gate opt, refused a
  # second time once already built), just reading `buildings` instead
  # of `has_granary` — see this module's own moduledoc.
  def can_queue?(city, :library, opts) do
    cond do
      :library in Map.get(city, :buildings, []) -> {:error, :already_built}
      not Keyword.get(opts, :library_available?, false) -> {:error, :locked}
      true -> :ok
    end
  end

  def can_queue?(city, :ancient_walls, opts) do
    cond do
      :ancient_walls in Map.get(city, :buildings, []) -> {:error, :already_built}
      not Keyword.get(opts, :walls_available?, false) -> {:error, :locked}
      true -> :ok
    end
  end

  def can_queue?(city, :barracks, opts) do
    cond do
      :barracks in Map.get(city, :buildings, []) -> {:error, :already_built}
      not Keyword.get(opts, :barracks_available?, false) -> {:error, :locked}
      true -> :ok
    end
  end

  def can_queue?(city, :water_mill, opts) do
    cond do
      :water_mill in Map.get(city, :buildings, []) -> {:error, :already_built}
      not Keyword.get(opts, :water_mill_available?, false) -> {:error, :locked}
      true -> :ok
    end
  end

  # Story 933 — the Pyramids/Hanging Gardens world wonders: ONE per
  # WORLD, not one per city, so — unlike every `can_queue?/3` clause
  # above — this never even looks at `city`'s own `:buildings`. The
  # single opt (`opts[:pyramids_claimed?]`/`opts[:hanging_gardens_claimed?]`)
  # is a WORLD-wide read, resolved one level up in `queue_production/4`
  # via `Buildings.wonder_built_or_building?/2` (see this module's own
  # moduledoc, "Story 933"): true the instant ANY city anywhere — this
  # one included — has it built or queued.
  def can_queue?(_city, :pyramids, opts) do
    cond do
      Keyword.get(opts, :pyramids_claimed?, false) -> {:error, :wonder_taken}
      not Keyword.get(opts, :pyramids_available?, false) -> {:error, :locked}
      true -> :ok
    end
  end

  def can_queue?(_city, :hanging_gardens, opts) do
    cond do
      Keyword.get(opts, :hanging_gardens_claimed?, false) -> {:error, :wonder_taken}
      not Keyword.get(opts, :hanging_gardens_available?, false) -> {:error, :locked}
      true -> :ok
    end
  end

  def can_queue?(_city, :bronze_spearman, opts) do
    cond do
      not Keyword.get(opts, :bronze_age?, false) -> {:error, :locked}
      not Keyword.get(opts, :copper_access?, false) -> {:error, :copper_required}
      true -> :ok
    end
  end

  # QA issue da39e50b — see this module's own moduledoc, "The Archer".
  def can_queue?(_city, :archer, opts) do
    if Keyword.get(opts, :archery?, false), do: :ok, else: {:error, :locked}
  end

  # Story 921 — see this module's own moduledoc, "The Galley": the SAME
  # two-independent-opts shape `:bronze_spearman` above already uses.
  # Missing Sailing reports the generic `:locked` (and, per
  # `available_items/1` below, the option never appears at all yet);
  # Sailing done but this city not coastal reports the more specific
  # `:not_coastal`, so a caller can render "Requires a coastal city"
  # rather than a bare disabled button.
  def can_queue?(_city, :galley, opts) do
    cond do
      not Keyword.get(opts, :sailing?, false) -> {:error, :locked}
      not Keyword.get(opts, :coastal?, false) -> {:error, :not_coastal}
      true -> :ok
    end
  end

  def can_queue?(_city, _type, _opts), do: :ok

  @always_available [:settler, :worker, :warrior]

  @doc """
  The buildable TYPES worth offering in a Build UI right now, given the
  same `opts` `can_queue?/3` reads (`:granary_available?`,
  `:bronze_age?`) — the always-available `:settler`/`:worker`/
  `:warrior` plus `:granary` once `opts[:granary_available?]` is true
  (story 902), `:bronze_spearman` once `opts[:bronze_age?]` is true
  (story 903), and `:galley` once `opts[:sailing?]` is true (story
  921 — `opts[:coastal?]` is deliberately NOT checked here, same
  "visible whether or not the second gate is met" posture
  `:bronze_spearman` already has for Copper). Deliberately narrower
  than `catalog/0` (never `:lord`) but NOT the same question as
  `can_queue?/3`: an item stays in this list even when `can_queue?/3`
  would still refuse it for another reason (a size-1 city's Settler, an
  already-built city's Granary, a Bronze Age city with no Copper access
  — story 911 — or a landlocked city with Sailing done — story 921) —
  those refusals are `disabled` states in the UI, not list exclusions.
  This is the one gate a caller (`BrokenOathsWeb.GameLive.CityPanel`)
  must apply to avoid offering — or hiding — anything
  `can_queue?/3`/`WorldServer`'s `queue_production` command wouldn't
  agree on, since both read the identical `opts`.
  """
  @spec available_items(keyword()) :: [buildable()]
  def available_items(opts \\ []) do
    @always_available
    |> maybe_offer(:granary, Keyword.get(opts, :granary_available?, false))
    |> maybe_offer(:bronze_spearman, Keyword.get(opts, :bronze_age?, false))
    |> maybe_offer(:archer, Keyword.get(opts, :archery?, false))
    |> maybe_offer(:galley, Keyword.get(opts, :sailing?, false))
    |> maybe_offer(:library, Keyword.get(opts, :library_available?, false))
    |> maybe_offer(:ancient_walls, Keyword.get(opts, :walls_available?, false))
    |> maybe_offer(:barracks, Keyword.get(opts, :barracks_available?, false))
    |> maybe_offer(:water_mill, Keyword.get(opts, :water_mill_available?, false))
    |> maybe_offer(:pyramids, wonder_offerable?(opts, :pyramids_available?, :pyramids_claimed?))
    |> maybe_offer(
      :hanging_gardens,
      wonder_offerable?(opts, :hanging_gardens_available?, :hanging_gardens_claimed?)
    )
  end

  defp maybe_offer(types, type, true), do: types ++ [type]
  defp maybe_offer(types, _type, false), do: types

  # Story 933 — unlike `:bronze_spearman`'s Copper gate or `:galley`'s
  # coastal gate (both stay VISIBLE-but-disabled once their own tech is
  # done, so the second requirement is legible), a wonder drops off the
  # list ENTIRELY, everywhere, once `claimed_key` is true — see this
  # module's own moduledoc, "Story 933", for why: there's no
  # "requirement not yet met" state worth showing for something that's
  # gone for good.
  defp wonder_offerable?(opts, available_key, claimed_key),
    do: Keyword.get(opts, available_key, false) and not Keyword.get(opts, claimed_key, false)

  # -------------------------------------------------------------------
  # Queue commands (moved from WorldServer, story 879)
  # -------------------------------------------------------------------

  @doc """
  Queue a new `type` item at the tail of `city_id`'s own build queue —
  resolves the Granary/Bronze Spearman/Archer/Galley gates itself
  (`granary_available?/2`/`bronze_age?/2`/`copper_access?/2`/
  `archery?/2`/`sailing?/2`/`coastal?/2`) before handing them to the
  pure `can_queue?/3`.
  """
  @spec queue_production(map(), map(), integer(), atom() | String.t()) ::
          {:ok, map()} | {:error, atom()}
  def queue_production(state, user, city_id, type) do
    with {:ok, city} <- owned_city(state, user, city_id),
         {:ok, type} <- parse_item_type(type),
         :ok <-
           can_queue?(city, type,
             granary_available?: granary_available?(state, city),
             bronze_age?: bronze_age?(state, city),
             copper_access?: copper_access?(state, city),
             archery?: archery?(state, city),
             sailing?: sailing?(state, city),
             coastal?: coastal?(state, city),
             library_available?: library_available?(state, city),
             walls_available?: walls_available?(state, city),
             barracks_available?: barracks_available?(state, city),
             water_mill_available?: water_mill_available?(state, city),
             pyramids_available?: pyramids_available?(state, city),
             pyramids_claimed?: pyramids_claimed?(state),
             hanging_gardens_available?: hanging_gardens_available?(state, city),
             hanging_gardens_claimed?: hanging_gardens_claimed?(state)
           ) do
      next_position =
        city.queue |> Enum.map(&Map.get(&1, :position, 0)) |> Enum.max(fn -> 0 end) |> Kernel.+(1)

      {:ok, item} =
        %ProductionItem{}
        |> ProductionItem.changeset(
          new_item(type)
          |> Map.put(:city_id, city_id)
          |> Map.put(:position, next_position)
        )
        |> Repo.insert()

      new_city = %{city | queue: city.queue ++ [queue_item_map(item)]}
      {:ok, %{state | cities: Map.put(state.cities, city_id, new_city)}}
    end
  end

  # Move a queued item one slot toward the head by swapping positions
  # with its predecessor. The head (current) item can't move; item
  # identity — and its banked progress — stays put, only order changes.
  @doc "Move `item_id` one slot toward the head of `city_id`'s own build queue."
  @spec reorder_production_item(map(), map(), integer(), integer()) ::
          {:ok, map()} | {:error, atom()}
  def reorder_production_item(state, user, city_id, item_id) do
    with {:ok, city} <- owned_city(state, user, city_id) do
      case Enum.find_index(city.queue, &(&1.id == item_id)) do
        nil ->
          {:error, :not_found}

        0 ->
          {:error, :invalid_item}

        idx ->
          above = Enum.at(city.queue, idx - 1)
          item = Enum.at(city.queue, idx)

          Repo.update_all(from(p in ProductionItem, where: p.id == ^item.id),
            set: [position: above.position]
          )

          Repo.update_all(from(p in ProductionItem, where: p.id == ^above.id),
            set: [position: item.position]
          )

          swapped = %{item | position: above.position}
          swapped_above = %{above | position: item.position}

          new_queue =
            city.queue
            |> List.replace_at(idx - 1, swapped)
            |> List.replace_at(idx, swapped_above)

          new_city = %{city | queue: new_queue}
          {:ok, %{state | cities: Map.put(state.cities, city_id, new_city)}}
      end
    end
  end

  @doc "Cancel (delete) `item_id` from `city_id`'s own build queue."
  @spec cancel_production_item(map(), map(), integer(), integer()) ::
          {:ok, map()} | {:error, atom()}
  def cancel_production_item(state, user, city_id, item_id) do
    with {:ok, city} <- owned_city(state, user, city_id) do
      if Enum.any?(city.queue, &(&1.id == item_id)) do
        Repo.delete_all(from(p in ProductionItem, where: p.id == ^item_id))
        new_city = %{city | queue: Enum.reject(city.queue, &(&1.id == item_id))}
        {:ok, %{state | cities: Map.put(state.cities, city_id, new_city)}}
      else
        {:error, :not_found}
      end
    end
  end

  @doc "Parses a build-type param (atom or string) into a known `buildable()`."
  @spec parse_item_type(term()) :: {:ok, buildable()} | {:error, :invalid_item}
  def parse_item_type(type)
      when type in [
             :settler,
             :worker,
             :warrior,
             :granary,
             :bronze_spearman,
             :archer,
             :galley,
             :library,
             :ancient_walls,
             :barracks,
             :water_mill,
             :pyramids,
             :hanging_gardens
           ],
      do: {:ok, type}

  def parse_item_type("settler"), do: {:ok, :settler}
  def parse_item_type("worker"), do: {:ok, :worker}
  def parse_item_type("warrior"), do: {:ok, :warrior}
  def parse_item_type("granary"), do: {:ok, :granary}
  def parse_item_type("bronze_spearman"), do: {:ok, :bronze_spearman}
  # QA issue da39e50b — the Archery tech unlocked nothing; a first-pass
  # Archer (melee-for-now — see this module's own moduledoc) buildable
  # once the city's owner has completed Archery.
  def parse_item_type("archer"), do: {:ok, :archer}
  # Story 921 — see this module's own moduledoc, "The Galley".
  def parse_item_type("galley"), do: {:ok, :galley}
  # Story 930 — see this module's own moduledoc, "Library, Ancient
  # Walls, Barracks, Water Mill".
  def parse_item_type("library"), do: {:ok, :library}
  def parse_item_type("ancient_walls"), do: {:ok, :ancient_walls}
  def parse_item_type("barracks"), do: {:ok, :barracks}
  def parse_item_type("water_mill"), do: {:ok, :water_mill}
  # Story 933 — see this module's own moduledoc, "Story 933".
  def parse_item_type("pyramids"), do: {:ok, :pyramids}
  def parse_item_type("hanging_gardens"), do: {:ok, :hanging_gardens}
  def parse_item_type(_other), do: {:error, :invalid_item}

  # Story 902, criterion 7629 — whether `city`'s OWNER has completed
  # Pottery, the option `can_queue?/3` needs to gate `:granary` on.
  @doc "Whether `city`'s OWNER has completed Pottery — the `:granary_available?` opt `can_queue?/3` needs."
  @spec granary_available?(map(), city()) :: boolean()
  def granary_available?(state, city),
    do: Research.granary_enabled?(player_research_for(state, city.player_id))

  # Story 903 — whether `city`'s OWNER is in the Bronze Age
  # (`Research.age/1`), the option `can_queue?/3` needs to gate
  # `:bronze_spearman` on.
  @doc "Whether `city`'s OWNER is in the Bronze Age — the `:bronze_age?` opt `can_queue?/3` needs."
  @spec bronze_age?(map(), city()) :: boolean()
  def bronze_age?(state, city),
    do: Research.age(player_research_for(state, city.player_id)) == :bronze_age

  # QA issue da39e50b — whether `city`'s OWNER has completed Archery,
  # the option `can_queue?/3` needs to gate `:archer` on.
  @doc "Whether `city`'s OWNER has completed Archery — the `:archery?` opt `can_queue?/3` needs."
  @spec archery?(map(), city()) :: boolean()
  def archery?(state, city),
    do: Research.archery_enabled?(player_research_for(state, city.player_id))

  # Story 921 — see this module's own moduledoc, "The Galley".
  @doc "Whether `city`'s OWNER has completed Sailing — the `:sailing?` opt `can_queue?/3` needs."
  @spec sailing?(map(), city()) :: boolean()
  def sailing?(state, city),
    do: Research.sailing_enabled?(player_research_for(state, city.player_id))

  # Story 930 — see this module's own moduledoc, "Library, Ancient
  # Walls, Barracks, Water Mill": four `_available?` accessors, the
  # exact same one-opt shape `granary_available?/2` above already uses.
  @doc "Whether `city`'s OWNER has completed Writing — the `:library_available?` opt `can_queue?/3` needs."
  @spec library_available?(map(), city()) :: boolean()
  def library_available?(state, city),
    do: Research.library_enabled?(player_research_for(state, city.player_id))

  @doc "Whether `city`'s OWNER has completed Masonry — the `:walls_available?` opt `can_queue?/3` needs."
  @spec walls_available?(map(), city()) :: boolean()
  def walls_available?(state, city),
    do: Research.walls_enabled?(player_research_for(state, city.player_id))

  @doc "Whether `city`'s OWNER has completed Bronze Working — the `:barracks_available?` opt `can_queue?/3` needs."
  @spec barracks_available?(map(), city()) :: boolean()
  def barracks_available?(state, city),
    do: Research.barracks_enabled?(player_research_for(state, city.player_id))

  @doc "Whether `city`'s OWNER has completed The Wheel — the `:water_mill_available?` opt `can_queue?/3` needs."
  @spec water_mill_available?(map(), city()) :: boolean()
  def water_mill_available?(state, city),
    do: Research.water_mill_enabled?(player_research_for(state, city.player_id))

  # Story 933 — the Pyramids/Hanging Gardens world wonders: their own
  # tech gates read exactly like every `_available?` accessor above
  # (city's OWNER, single tech). Their `_claimed?` siblings below are
  # the new, WORLD-wide half `can_queue?/3`'s one-per-world gate needs
  # — see this module's own moduledoc, "Story 933".
  @doc "Whether `city`'s OWNER has completed Masonry — the `:pyramids_available?` opt `can_queue?/3` needs."
  @spec pyramids_available?(map(), city()) :: boolean()
  def pyramids_available?(state, city),
    do: Research.pyramids_enabled?(player_research_for(state, city.player_id))

  @doc "Whether `city`'s OWNER has completed Irrigation — the `:hanging_gardens_available?` opt `can_queue?/3` needs."
  @spec hanging_gardens_available?(map(), city()) :: boolean()
  def hanging_gardens_available?(state, city),
    do: Research.hanging_gardens_enabled?(player_research_for(state, city.player_id))

  @doc """
  Whether the Pyramids has already been completed, or is currently
  queued (not yet complete), in ANY city anywhere in `state` — the
  `:pyramids_claimed?` opt `can_queue?/3` needs for its one-per-world
  gate. WORLD-level, unlike every `_available?` accessor above (each
  of which only ever reads ONE city's own owner) — a wonder has no
  single owner to check until someone actually claims it.
  """
  @spec pyramids_claimed?(map()) :: boolean()
  def pyramids_claimed?(state),
    do: Buildings.wonder_built_or_building?(Map.values(state.cities), :pyramids)

  @doc "The Hanging Gardens' own `pyramids_claimed?/1` sibling."
  @spec hanging_gardens_claimed?(map()) :: boolean()
  def hanging_gardens_claimed?(state),
    do: Buildings.wonder_built_or_building?(Map.values(state.cities), :hanging_gardens)

  @doc """
  Whether `city` itself has at least one adjacent `:coastal_water` tile
  — the `:coastal?` opt `can_queue?/3` needs (story 921): a
  Galley can only ever be built in a city that actually touches water
  (`landing_tile/4`'s own `:galley` clause is where that adjacent water
  tile gets used). Terrain-only, unlike `sailing?/2` above — no
  `Research` involved, no per-player state, just this ONE city's own
  territory.
  """
  @spec coastal?(map(), city()) :: boolean()
  def coastal?(state, city) do
    state.world
    |> Regions.adjacent_tiles(city.tile_id)
    |> Enum.any?(&(Regions.tile_class(state.world, &1) == :coastal_water))
  end

  # Story 911 rework (QA issue 3e6c124c "Copper availability wrong") —
  # whether PLAYER `player_id` has Copper access anywhere: a completed
  # Mine sitting on a Copper tile within territory ANY of their own
  # cities controls. Player-wide by design — see this module's own
  # moduledoc, "The Bronze Spearman's Copper gate" — so this is the one
  # true source `copper_access?/2` below defers to.
  @doc """
  Whether `player_id` has Copper access: at least one COMPLETED Mine
  improvement (`state.improvements`, `status: :complete`) sitting on a
  Copper tile (`Resources.at/2`) within territory ANY city that player
  owns controls — PLAYER-WIDE, not per-city (story 911 rework, QA
  issue 3e6c124c). See this module's own moduledoc for the full
  rationale.
  """
  @spec player_copper_access?(map(), term()) :: boolean()
  def player_copper_access?(state, player_id) do
    state.cities
    |> Map.values()
    |> Enum.filter(&(&1.player_id == player_id))
    |> Enum.flat_map(& &1.territory)
    |> Enum.uniq()
    |> Enum.any?(&copper_mine_tile?(state, &1))
  end

  defp copper_mine_tile?(state, tile_id) do
    match?(%{kind: :mine, status: :complete}, Map.get(state.improvements, tile_id)) and
      Resources.at(state.world, tile_id) == :copper
  end

  @doc """
  Whether `city`'s OWNER has Copper access — a thin per-city wrapper
  around `player_copper_access?/2` (the `:copper_access?` opt
  `can_queue?/3` needs). Defers entirely to the PLAYER-wide rule; does
  NOT recheck `city`'s own territory in isolation (story 911 rework,
  QA issue 3e6c124c — see this module's own moduledoc).
  """
  @spec copper_access?(map(), city()) :: boolean()
  def copper_access?(state, city), do: player_copper_access?(state, city.player_id)

  @doc """
  Test-only helper for `WorldServer`'s own `:grant_copper_access_for_test`
  bridge: the first tile id (mesh order) anywhere on `world` carrying
  Copper, or `nil` if this particular seed/density placed none at all.
  """
  @spec find_any_copper_tile(World.t()) :: tile_id() | nil
  def find_any_copper_tile(world) do
    mesh = Globe.get(world.frequency)

    Enum.find_value(mesh.tiles, fn {tile_id, _tile} ->
      if Resources.at(world, tile_id) == :copper, do: tile_id
    end)
  end

  # -------------------------------------------------------------------
  # Shared, trivial lookups — duplicated rather than reaching back into
  # `WorldServer` (or reaching sideways into `City`), matching the
  # sibling `Rebellion.War`'s own "pure, process-unaware, unit-testable
  # with no GenServer running" contract (small private helper copies
  # rather than expanding public APIs).
  # -------------------------------------------------------------------

  defp find_player(state, user_id) do
    state.players |> Map.values() |> Enum.find(&(&1.user_id == user_id))
  end

  defp owned_city(state, user, city_id) do
    player = find_player(state, user.id)
    city = Map.get(state.cities, city_id)

    if is_nil(player) or is_nil(city) or city.player_id != player.id do
      {:error, :not_owner}
    else
      {:ok, city}
    end
  end

  defp player_research_for(state, player_id),
    do: Map.get(state.player_research, player_id, Research.new())

  defp queue_item_map(%ProductionItem{} = item),
    do: %{
      id: item.id,
      type: item.type,
      banked: item.banked,
      cost: item.cost,
      position: item.position
    }

  # -------------------------------------------------------------------
  # Accrual
  # -------------------------------------------------------------------

  @doc """
  Bank this turn's production (flat base + worked-tile production +
  the Barracks'/Water Mill's own bonuses, story 930) into the current
  (head) queue item. A no-op with an empty queue — nothing is queued
  to receive it.
  """
  @spec accrue(city(), World.t(), map()) :: city()
  def accrue(%{queue: []} = city, _world, _improvements), do: city

  def accrue(%{queue: [current | rest]} = city, world, improvements) do
    income =
      @flat_production + worked_production(city, world, improvements) +
        barracks_bonus(city, current.type) + water_mill_production_bonus(city)

    %{city | queue: [%{current | banked: current.banked + income} | rest]}
  end

  @doc """
  Credit a one-time production LUMP straight onto `city`'s current
  (head) queue item's `banked` (story 927's Chop yield — see
  `BrokenOaths.Cities.Improvement.chop/3`) — a no-op with an empty
  queue, the same "nothing to receive it" posture `accrue/3` above
  already has. Unlike `accrue/3` (THIS TURN's recurring flat +
  worked-tile income), the caller supplies the raw amount directly, so
  this never touches `worked_production/3`/the Barracks/Water Mill
  bonuses. Overflow beyond the current item's own `cost` is never
  resolved HERE — it simply sits banked past `cost` until the next turn
  boundary's own `resolve_completions/1` cascades it into the NEXT item
  via `carry_overflow/2`, the exact same path an ordinary turn's own
  production income already relies on.
  """
  @spec credit(city(), non_neg_integer()) :: city()
  def credit(%{queue: []} = city, _amount), do: city

  def credit(%{queue: [current | rest]} = city, amount),
    do: %{city | queue: [%{current | banked: current.banked + amount} | rest]}

  defp worked_production(city, world, improvements) do
    city
    |> Yields.worked_yields(world, improvements)
    |> Enum.map(& &1.production)
    |> Enum.sum()
  end

  # Story 930 — the Barracks: +1 production, but ONLY toward a MILITARY
  # queue item (see this module's own moduledoc) — a Settler, Worker, or
  # another building banks the flat base and worked-tile production
  # alone, same as an unbarracked city.
  @military_types [:warrior, :archer, :bronze_spearman, :galley, :lord]
  @barracks_production_bonus 1

  @doc "How much production the Barracks adds toward a military queue item, once built."
  @spec barracks_production_bonus() :: pos_integer()
  def barracks_production_bonus, do: @barracks_production_bonus

  defp barracks_bonus(city, type) do
    if type in @military_types and :barracks in Map.get(city, :buildings, []) do
      @barracks_production_bonus
    else
      0
    end
  end

  # Story 930 — the Water Mill: +1 production flat, on top of whatever
  # else the city already banks (no river requirement modeled — see
  # this module's own moduledoc). `Yields.water_mill_food_bonus/0` is
  # the food half of this same building's effect.
  @water_mill_production_bonus 1

  @doc "How much production the Water Mill adds flat, once built."
  @spec water_mill_production_bonus() :: pos_integer()
  def water_mill_production_bonus, do: @water_mill_production_bonus

  defp water_mill_production_bonus(city) do
    if :water_mill in Map.get(city, :buildings, []), do: @water_mill_production_bonus, else: 0
  end

  # -------------------------------------------------------------------
  # Tick-loop accrual (moved from `BrokenOaths.Simulation.Turn`'s own private
  # `accrue_production/1`/`accrue_or_skip/2`, the tick-decomposition
  # pass — see `.code_my_spec/knowledge/genserver_decomposition.md`)
  # -------------------------------------------------------------------

  @doc """
  Bank this turn's production for every city in `state.cities`, skipping
  any city still serving `BrokenOaths.Combat.CityDefense.production_halted?/2`'s
  pillage freeze (story 895) -- that city's queue simply doesn't move
  this boundary; its banked progress is untouched, not lost. `state` is
  the canonical tick-state described in `BrokenOaths.Simulation.Turn`.
  """
  @spec accrue_cities(map()) :: map()
  def accrue_cities(state) do
    cities =
      Map.new(state.cities, fn {id, city} ->
        {id, accrue_or_skip(city, state)}
      end)

    %{state | cities: cities}
  end

  # A pillaged city's queue simply doesn't move while
  # `CityDefense.production_halted?/2` holds -- see that function's doc
  # for exactly which boundaries that covers.
  defp accrue_or_skip(city, state) do
    if CityDefense.production_halted?(city, state.turn) do
      city
    else
      accrue(city, state.world, state.improvements)
    end
  end

  # -------------------------------------------------------------------
  # Completion + spawn placement
  # -------------------------------------------------------------------

  @doc """
  Resolve as many completed queue items as banked production and free
  landing tiles allow. Returns `{new_city, spawn_events}`; each event
  is a placement intent for the caller to materialize into a real unit.
  """
  @spec complete(city(), %{tile_id() => term()}, World.t()) :: {city(), [spawn_event()]}
  def complete(city, occupied_tiles, world) do
    complete_loop(city, occupied_tiles, world, [])
  end

  defp complete_loop(%{queue: []} = city, _occupied, _world, events),
    do: {city, Enum.reverse(events)}

  # A Granary completion needs no landing tile and produces no
  # `spawn_event` — it just flips `has_granary: true` on the completing
  # city itself and moves on, same overflow-carry treatment as every
  # other completion (story 902).
  defp complete_loop(
         %{queue: [%{type: :granary} = current | rest]} = city,
         occupied,
         world,
         events
       )
       when current.banked >= current.cost do
    overflow = current.banked - current.cost

    city
    |> Map.put(:has_granary, true)
    |> Map.put(:queue, carry_overflow(rest, overflow))
    |> complete_loop(occupied, world, events)
  end

  # Story 930 — Library/Ancient Walls/Barracks/Water Mill: the exact
  # same "no landing tile, no spawn event, just flip storage" shape the
  # Granary clause above uses, generalized to one clause for all four
  # (and any future addition to `@passive_buildings`) via the
  # `buildings` LIST rather than four near-identical copies of the
  # Granary's own boolean-flip clause. Story 933 — the Hanging Gardens
  # wonder joins this same list: its own effect (`Yields.grow_cities/2`)
  # only ever needs the `buildings` flip, exactly like every standard
  # passive building above; ONLY its cap (one per world, not one per
  # city) works differently, and that's already handled a level up in
  # `can_queue?/3`/`available_items/1` before an item ever reaches this
  # queue at all. The Pyramids is NOT on this list — see its own
  # dedicated clause below.
  @passive_buildings [:library, :ancient_walls, :barracks, :water_mill, :hanging_gardens]

  defp complete_loop(
         %{queue: [%{type: type} = current | rest]} = city,
         occupied,
         world,
         events
       )
       when type in @passive_buildings and current.banked >= current.cost do
    overflow = current.banked - current.cost

    city
    |> Map.update(:buildings, [type], &Enum.uniq([type | &1]))
    |> Map.put(:queue, carry_overflow(rest, overflow))
    |> complete_loop(occupied, world, events)
  end

  # Story 933 — the Pyramids wonder: unlike every passive building
  # above, completing it ALSO grants a free Worker (Civ 6's own
  # Pyramids effect), so it needs BOTH the `buildings` flip AND a real
  # `spawn_event` — the SAME landing-tile machinery (`landing_tile/4`)
  # every ordinary unit completion below already uses, blocked-tile-
  # waits-a-turn included, per this story's own instruction to reuse
  # that path rather than hand-build a unit. The spawned event's own
  # `type` is `:worker` — deliberately NOT `current.type` (`:pyramids`)
  # the way the generic clause below builds its event, since the
  # WONDER itself never becomes a placed unit; the free Worker it hands
  # out does. No population cost (`apply_pop_cost/3` only ever touches
  # `:settler`) and no `spawnable?/2` gate — a wonder has no population
  # of its own to spare.
  defp complete_loop(
         %{queue: [%{type: :pyramids} = current | rest]} = city,
         occupied,
         world,
         events
       )
       when current.banked >= current.cost do
    case landing_tile(city, :worker, occupied, world) do
      nil ->
        {city, Enum.reverse(events)}

      tile ->
        overflow = current.banked - current.cost
        event = %{player_id: city.player_id, type: :worker, tile_id: tile}

        city
        |> Map.update(:buildings, [:pyramids], &Enum.uniq([:pyramids | &1]))
        |> Map.put(:queue, carry_overflow(rest, overflow))
        |> complete_loop(occupied, world, [event | events])
    end
  end

  defp complete_loop(%{queue: [current | rest]} = city, occupied, world, events) do
    if current.banked >= current.cost and spawnable?(city, current.type) do
      resolve_completion(city, current, rest, occupied, world, events)
    else
      {city, Enum.reverse(events)}
    end
  end

  defp resolve_completion(city, current, rest, occupied, world, events) do
    case landing_tile(city, current.type, occupied, world) do
      nil ->
        {city, Enum.reverse(events)}

      tile ->
        overflow = current.banked - current.cost
        event = %{player_id: city.player_id, type: current.type, tile_id: tile}

        city
        |> apply_pop_cost(current.type, world)
        |> Map.put(:queue, carry_overflow(rest, overflow))
        |> complete_loop(occupied, world, [event | events])
    end
  end

  # A settler costs its city one population, at the moment it spawns —
  # not while merely banked (story 883). A size-1 city can never pay
  # that cost, so its settler item simply waits, exactly like a
  # blocked landing tile.
  defp spawnable?(_city, type)
       when type in [:worker, :warrior, :bronze_spearman, :archer, :galley],
       do: true

  defp spawnable?(%{size: size}, :settler), do: size > 1

  # Story 921 — see this module's own moduledoc, "The Galley": a Galley
  # can never land on the city's own (land) tile the way every other
  # unit does — its own candidate list is the lowest-id adjacent
  # `:coastal_water` tile that isn't already occupied. `Enum.sort/1`
  # gives the "lowest id" a deterministic meaning; no other landing
  # rule needed to care about ordering since `[city.tile_id | ...]`
  # already puts the city tile first.
  defp landing_tile(city, :galley, occupied, world) do
    world
    |> Regions.adjacent_tiles(city.tile_id)
    |> Enum.filter(&(Regions.tile_class(world, &1) == :coastal_water))
    |> Enum.sort()
    |> Enum.find(&(not Map.has_key?(occupied, &1)))
  end

  defp landing_tile(city, _type, occupied, world) do
    candidates = [
      city.tile_id
      | world |> Regions.adjacent_tiles(city.tile_id) |> Enum.filter(&land?(world, &1))
    ]

    Enum.find(candidates, &(not Map.has_key?(occupied, &1)))
  end

  defp land?(world, tile_id), do: Regions.tile_class(world, tile_id) == :land

  defp carry_overflow([], _overflow), do: []

  defp carry_overflow([next | rest], overflow),
    do: [%{next | banked: next.banked + overflow} | rest]

  defp apply_pop_cost(city, :settler, world) do
    city
    |> Map.update!(:size, &(&1 - 1))
    |> unwork_weakest_tile(world)
  end

  defp apply_pop_cost(city, _type, _world), do: city

  # Territory is permanent (story 883) — only which tile is WORKED
  # shrinks. Drop the lowest-scoring worked tile so the city keeps its
  # best producers.
  defp unwork_weakest_tile(%{worked_tiles: []} = city, _world), do: city

  defp unwork_weakest_tile(city, world) do
    weakest =
      Enum.min_by(city.worked_tiles, fn tile_id ->
        yield = Yields.tile_yield(Regions.terrain(world, tile_id))
        {Yields.assignment_score(yield), tile_id}
      end)

    %{city | worked_tiles: List.delete(city.worked_tiles, weakest)}
  end

  # -------------------------------------------------------------------
  # Tick-loop completion resolution (moved from `BrokenOaths.Simulation.Turn`'s
  # own private `resolve_completions/1`/`resolve_city_completion/2`, the
  # tick-decomposition pass)
  # -------------------------------------------------------------------

  @doc """
  Resolve every city's queue completions for one tick, in ascending
  city id order, threading a running "occupied tiles" set through so a
  spawn from one city in this same tick correctly blocks a landing tile
  for the next city's completion -- before either lands in `state.units`,
  which only the caller can update (`{:unit_spawned, _}` events are
  placement intents, not real units -- this module never allocates a
  real unit id itself). Also threads a `MapSet` of city ids whose queue
  completed a `:settler` THIS tick (`apply_pop_cost/3` already docked
  their population the instant the spawn event was built) --
  `BrokenOaths.Cities.Yields.grow_cities/2` reads this to skip those
  cities' own growth this same tick (issue 63300098: growth resolving
  in the same tick otherwise silently refunds the settler's population
  cost the instant a well-fed city crosses its next growth threshold).
  `state` is the canonical tick-state described in
  `BrokenOaths.Simulation.Turn`.

  Also returns `completions` — one entry per queue item that finished
  THIS tick, unit or building alike (`%{user_id:, city_name:, type:}`,
  playtest issue 6's own "build complete" toast): every `spawn_event`
  above names ITS OWN completion, plus a Granary's (which produces no
  `spawn_event` at all — see `complete_loop/4`'s own Granary clause)
  detected by diffing `has_granary` before/after. `spawn_event` itself
  stays `%{player_id:, type:, tile_id:}` (unchanged, `turn_test.exs`
  asserts on it by exact map equality) — `completions` is a SEPARATE
  list built only here, at the tick-loop level, so it can carry the
  human-facing `user_id`/`city_name` a spawn intent has no reason to.

  Returns `{new_state, spawn_events, occupied, settled_this_tick, completions}`.
  """
  @spec resolve_completions(map()) ::
          {map(), [spawn_event()], map(), MapSet.t(), [completion_event()]}
  def resolve_completions(state) do
    occupied = Map.new(state.units, fn {_id, unit} -> {unit.tile_id, true} end)
    ids = state.cities |> Map.keys() |> Enum.sort()

    {cities, events, occupied, settled_this_tick, completions} =
      Enum.reduce(
        ids,
        {state.cities, [], occupied, MapSet.new(), []},
        &resolve_city_completion(state, &1, &2)
      )

    {%{state | cities: cities}, events, occupied, settled_this_tick, completions}
  end

  defp resolve_city_completion(
         state,
         id,
         {cities, events, occupied, settled_this_tick, completions}
       ) do
    city = Map.fetch!(cities, id)
    {new_city, city_events} = complete(city, occupied, state.world)
    newly_occupied = Map.new(city_events, fn event -> {event.tile_id, true} end)

    settled_this_tick =
      if Enum.any?(city_events, &(&1.type == :settler)) do
        MapSet.put(settled_this_tick, id)
      else
        settled_this_tick
      end

    {
      Map.put(cities, id, new_city),
      events ++ city_events,
      Map.merge(occupied, newly_occupied),
      settled_this_tick,
      completions ++ city_completions(state.players, city, new_city, city_events)
    }
  end

  # Every `city_events` entry (a real unit landing) is its own
  # completion; a Granary has none of its own (see `complete_loop/4`),
  # so it's detected separately off the `has_granary` flip — `Map.get/3`
  # defaults to `false` the same defensive way `Yields.accrue_food/3`/
  # `can_queue?/3` already read this optional field. `completion_base/2`
  # returning `nil` (no row in `players` for this city's own owner — a
  # gap plenty of hand-built tick-state fixtures leave, since they only
  # care about spawn placement, not the notification this feeds) simply
  # produces no completions for this city rather than raising: nobody's
  # `user_id` to notify means nothing to build here.
  defp city_completions(players, city, new_city, city_events) do
    case completion_base(players, city) do
      nil ->
        []

      base ->
        unit_completions = Enum.map(city_events, &Map.put(base, :type, &1.type))

        building_completions =
          Enum.map(newly_completed_buildings(city, new_city), &Map.put(base, :type, &1))

        unit_completions ++ building_completions
    end
  end

  # Story 930 — every completion `city_events` above doesn't already
  # cover: the Granary's own `has_granary` flip (story 902, unchanged)
  # plus a diff of the `buildings` list for the four newer ones (a
  # `MapSet` diff rather than one `if` per building, same generalization
  # `complete_loop/4`'s own `@passive_buildings` clause already made).
  defp newly_completed_buildings(city, new_city) do
    had_granary = Map.get(city, :has_granary, false)
    has_granary = Map.get(new_city, :has_granary, false)
    granary = if !had_granary and has_granary, do: [:granary], else: []

    had = MapSet.new(Map.get(city, :buildings, []))
    has = MapSet.new(Map.get(new_city, :buildings, []))

    granary ++ MapSet.to_list(MapSet.difference(has, had))
  end

  defp completion_base(players, city) do
    case Map.get(players, city.player_id) do
      nil -> nil
      player -> %{user_id: player.user_id, city_name: city.name}
    end
  end

  # -------------------------------------------------------------------
  # City founding
  # -------------------------------------------------------------------

  @doc """
  Validate founding a city on `tile_id`: must be passable land, and at
  least 4 hexes (over the land graph) from every existing city.
  """
  @spec validate_founding(World.t(), [city()], tile_id()) ::
          :ok | {:error, :invalid_terrain | :too_close}
  def validate_founding(world, cities, tile_id) do
    cond do
      not land?(world, tile_id) -> {:error, :invalid_terrain}
      too_close?(world, cities, tile_id) -> {:error, :too_close}
      true -> :ok
    end
  end

  @doc "A freshly founded city's territory: the tile plus its six neighbors, unconditionally."
  @spec founding_territory(World.t(), tile_id()) :: MapSet.t(tile_id())
  def founding_territory(world, tile_id),
    do: MapSet.new([tile_id | Regions.adjacent_tiles(world, tile_id)])

  defp too_close?(world, cities, tile_id) do
    max_depth = @min_founding_spacing - 1
    Enum.any?(cities, &(land_distance(world, tile_id, &1.tile_id, max_depth) <= max_depth))
  end

  # Land-only BFS distance, capped at `max_depth` (returns `max_depth + 1`
  # once exceeded or unreachable) — spacing only ever cares whether the
  # distance is under the minimum, so the search never needs to look
  # further than that.
  defp land_distance(_world, from, from, _max_depth), do: 0

  defp land_distance(world, from, to, max_depth),
    do: grow_land_ring(world, MapSet.new([from]), [from], to, 1, max_depth)

  defp grow_land_ring(_world, _seen, _frontier, _to, depth, max_depth) when depth > max_depth,
    do: max_depth + 1

  defp grow_land_ring(world, seen, frontier, to, depth, max_depth) do
    next =
      frontier
      |> Enum.flat_map(&Regions.adjacent_tiles(world, &1))
      |> Enum.uniq()
      |> Enum.filter(&land?(world, &1))
      |> Enum.reject(&MapSet.member?(seen, &1))

    cond do
      to in next ->
        depth

      next == [] ->
        max_depth + 1

      true ->
        grow_land_ring(
          world,
          MapSet.union(seen, MapSet.new(next)),
          next,
          to,
          depth + 1,
          max_depth
        )
    end
  end
end
