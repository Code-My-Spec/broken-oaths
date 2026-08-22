defmodule BrokenOaths.Cities.Yields do
  @moduledoc """
  Pure yields core (see `.code_my_spec/knowledge/stone_age_yields.md` for
  the canonical numbers this module implements): worked-hex food/
  production per terrain, the city center's guaranteed floor, food
  thresholds and growth to the Stone Age size cap, and deterministic
  worked-tile assignment. No `Repo`, no randomness — every pick here is
  a function of `world`, a city's own state, and (for growth) every
  other city's claimed territory, so the same inputs always produce the
  same outcome.

  ## Yield stacking

  `yield = base + relief + feature`, additive (Civ VI model): hills
  +1 production, woods +1 production, rainforest/marsh +1 food.
  Mountains and the `:ice` feature are never workable — `workable?/1`
  is the single gate every tile pick (growth claim, citizen
  assignment) filters through.

  ## City center floor

  The city center tile is always worked for free at a guaranteed
  minimum of 2 food / 1 production (`city_center_yield/1`), upgraded
  if the terrain beats it. Its production side is deliberately NOT
  added again on top of `BrokenOaths.Cities.Production`'s flat-5 base —
  the flat base already stands in for it (a real terrain floor would
  double-count); only its food counts toward growth.

  ## Deterministic tile-picking

  Both growth's territory claim and a new citizen's tile assignment
  score candidates and break ties the same way: highest score first,
  then (growth only) higher food, then smaller ring-distance from the
  city's own tile, then a fixed compass order (N, NE, SE, S, SW, NW —
  the six hex directions, by great-circle bearing from the city tile),
  then lowest tile id as a final, always-decisive tiebreak.

  ## The Granary bonus (story 902, criterion 7629)

  A city with `has_granary: true` (`BrokenOaths.Cities.Production`'s
  `:granary` buildable, gated on the owner having completed Pottery)
  banks a flat +2 food every turn on top of the center's floor and
  every worked tile's food — `accrue_food/3`'s own read of `Map.get(
  city, :has_granary, false)`, the same defensive-default idiom
  `worked_yields/3` already uses for `improvements`.

  ## The Water Mill bonus (story 930)

  A city with `:water_mill` in its `buildings` list
  (`BrokenOaths.Cities.Production`'s `:water_mill` buildable, gated on
  the owner having completed The Wheel) banks a flat +1 food every turn
  — `accrue_food/3`'s own read of `Map.get(city, :buildings, [])`, the
  same defensive-default idiom the Granary's own `has_granary` read
  already uses. The building's other half, +1 production, is
  `BrokenOaths.Cities.Production.water_mill_production_bonus/0`'s own
  concern, not this module's.

  ## The Hanging Gardens bonus (story 933)

  A player who holds the Hanging Gardens wonder (`BrokenOaths.Cities.
  Production`'s `:hanging_gardens` buildable, gated on Irrigation, ONE
  PER WORLD — see `BrokenOaths.Cities.Buildings`'s own moduledoc,
  "Wonders") grows every one of THEIR OWN cities ~15% faster —
  empire-wide, not scoped to the one city that built it, the same
  player-wide reach `Production.player_copper_access?/2` established
  for Copper. `grow_cities/2` is where this lives, not `accrue_food/3`
  above: rather than inflate the FOOD a city banks each turn (which
  would leave `city.food` sitting above the raw threshold after a
  growth, an awkward number to explain on the next turn's readout),
  `effective_threshold/2` shrinks the FOOD REQUIRED to cross it —
  `div(threshold * 100, 115)` (integer division, no floats: a size-1
  city needs 17 food to grow instead of 20) — so a Hanging-Gardens
  city's own `food` value always reads exactly like an ordinary
  city's, just crossing its next growth line sooner.

  ## Bonus resources (story 905)

  `resource_bonus/1` is the resource layer's own additive term —
  Cattle/Sheep/Wheat +1 food, Stone +1 production, no resource nothing
  (`.code_my_spec/knowledge/civ6_resources.md` §5) — stacking on top of
  raw terrain exactly the way an improvement's bonus already does,
  never gated behind any tech or improvement itself (a bonus resource's
  OWN yield is visible/worked the moment a citizen sits on the tile;
  only its IMPROVEMENT's extra yield, e.g. Pasture, needs research).
  The arity-1/2 building blocks (`tile_yield/1`, `city_center_yield/1`,
  `worked_tile_yield/2`) stay deliberately resource-BLIND — several
  callers (story 905's own criterion 7650 chief among them) need the
  raw terrain score on its own — so resource stacking lives in the
  arity-3/2 siblings (`worked_tile_yield/3`, `city_center_yield/2`)
  and in the `world`-aware readers below (`worked_yields/3`,
  `center_yield/2`, and the deterministic tile-picking keys), which
  already have a `tile_id` to resolve a resource from.

  ## Copper — a strategic resource with NO yield (story 911)

  Copper (`BrokenOaths.Worlds.Resources`'s first STRATEGIC resource)
  reads through this exact same `resource_bonus/1`/`Resources.at/2`
  plumbing as every bonus resource (a worked or growth-scored Copper
  tile is a completely ordinary candidate, and `candidate_yield/2`
  below would crash without a matching clause the instant Copper
  starts appearing on the map), but its own additive term is `0F 0P`
  — Copper is a pure ACCESS GATE for the Bronze Spearman
  (`BrokenOaths.Cities.Production.can_queue?/3`'s `copper_access?`
  option), never a tile-yield bonus a citizen benefits from by working
  it.

  ## Gold (story 912)

  A city's per-turn GOLD income is a separate channel from food/
  production, computed by `city_gold_income/2`: a per-size `base_gold/1`
  (`1 + floor(size/2)`) plus `tile_gold/1` summed over every currently
  worked tile — today, only worked Coast tiles (`Terrain.base ==
  :coast`) contribute, +1 gold each (Civ's "commerce from the sea"
  convention; copper/river gold is a deliberately deferred fork, see
  `tile_gold/1`'s own doc). Recomputed fresh every turn boundary from
  the city's current `size`/`worked_tiles` — nothing about gold is
  cached on the city struct itself, the same "always live, never
  stale" contract `worked_yields/3` already keeps for food/production.
  `BrokenOaths.Simulation.WorldServer`'s `apply_tribute/1`/`apply_bank/1`
  sum this over every city a player owns once per turn boundary — see
  those modules' own moduledocs for the treasury-while-online/
  bank-while-offline split this feeds.
  """

  alias BrokenOaths.Cities.Buildings
  alias BrokenOaths.Technology.Research
  alias BrokenOaths.Worlds.Globe
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.Resources
  alias BrokenOaths.Worlds.Terrain
  alias BrokenOaths.Worlds.World

  @type yield :: %{food: non_neg_integer(), production: non_neg_integer()}
  @type tile_id :: non_neg_integer()
  @type city :: %{
          required(:tile_id) => tile_id(),
          required(:size) => pos_integer(),
          required(:food) => non_neg_integer(),
          required(:territory) => [tile_id()],
          required(:worked_tiles) => [tile_id()],
          optional(atom()) => term()
        }
  @type improvement :: %{kind: :farm | :mine | :road | :pasture, status: :building | :complete}

  # -------------------------------------------------------------------
  # Raw terrain yield
  # -------------------------------------------------------------------

  @doc "A tile's raw yield: base + relief + feature, stacked. Unworkable terrain yields nothing."
  @spec tile_yield(Terrain.t()) :: yield()
  def tile_yield(%Terrain{relief: :mountains}), do: %{food: 0, production: 0}
  def tile_yield(%Terrain{feature: :ice}), do: %{food: 0, production: 0}

  def tile_yield(%Terrain{base: base, relief: relief, feature: feature}) do
    {base_food, base_production} = base_yield(base)

    %{
      food: base_food + feature_food_bonus(feature),
      production: base_production + relief_bonus(relief) + feature_production_bonus(feature)
    }
  end

  @doc """
  A tile's yield including its bonus resource (story 905): raw terrain
  plus resource, stacked — e.g. a Cattle tile on flat grassland is
  `2 (terrain) + 1 (resource) = 3` food, with no improvement involved.
  The resource-blind sibling above (`tile_yield/1`) stays untouched —
  several callers (not least criterion 7650's own spec) need the raw
  terrain score on its own.
  """
  @spec tile_yield(Terrain.t(), Resources.kind() | nil) :: yield()
  def tile_yield(terrain, resource), do: add_yield(tile_yield(terrain), resource_bonus(resource))

  @doc "The city center's yield: raw terrain, floored at 2 food / 1 production."
  @spec city_center_yield(Terrain.t()) :: yield()
  def city_center_yield(terrain) do
    yield = tile_yield(terrain)
    %{food: max(yield.food, 2), production: max(yield.production, 1)}
  end

  @doc """
  The city center's yield including its own bonus resource (story
  905), if it happens to be settled on one — still floored at 2 food /
  1 production. The resource-blind sibling above (`city_center_yield/1`)
  stays untouched for callers that only ever have a bare `Terrain.t()`.
  """
  @spec city_center_yield(Terrain.t(), Resources.kind() | nil) :: yield()
  def city_center_yield(terrain, resource) do
    yield = add_yield(tile_yield(terrain), resource_bonus(resource))
    %{food: max(yield.food, 2), production: max(yield.production, 1)}
  end

  @doc "False for mountains and ice — never claimable by growth, never assignable to a citizen."
  @spec workable?(Terrain.t()) :: boolean()
  def workable?(%Terrain{relief: :mountains}), do: false
  def workable?(%Terrain{feature: :ice}), do: false
  def workable?(%Terrain{}), do: true

  @doc "A completed improvement's yield bonus (farm/pasture +food, mine +production, road none)."
  @spec improvement_bonus(nil | :farm | :mine | :road | :pasture) :: yield()
  def improvement_bonus(:farm), do: %{food: 2, production: 0}
  def improvement_bonus(:mine), do: %{food: 0, production: 2}
  def improvement_bonus(:road), do: %{food: 0, production: 0}
  def improvement_bonus(:pasture), do: %{food: 2, production: 0}
  def improvement_bonus(nil), do: %{food: 0, production: 0}

  @doc """
  A bonus resource's own additive yield (story 905): Cattle, Sheep, and
  Wheat each add +1 food; Stone adds +1 production; no resource adds
  nothing. Never gated on research or an improvement — a resource's OWN
  bonus is visible/worked unconditionally (only its IMPROVEMENT's extra
  yield, e.g. Pasture, needs a tech). Copper (story 911, a STRATEGIC
  resource) adds nothing at all — see this module's own moduledoc
  section "Copper — a strategic resource with NO yield."
  """
  @spec resource_bonus(Resources.kind() | nil) :: yield()
  def resource_bonus(kind) when kind in [:cattle, :sheep, :wheat], do: %{food: 1, production: 0}
  def resource_bonus(:stone), do: %{food: 0, production: 1}
  def resource_bonus(:copper), do: %{food: 0, production: 0}
  def resource_bonus(nil), do: %{food: 0, production: 0}

  @doc "A worked (non-center) tile's yield: raw terrain plus its completed improvement, if any."
  @spec worked_tile_yield(Terrain.t(), nil | :farm | :mine | :road | :pasture) :: yield()
  def worked_tile_yield(terrain, improvement_kind) do
    base = tile_yield(terrain)
    bonus = improvement_bonus(improvement_kind)
    %{food: base.food + bonus.food, production: base.production + bonus.production}
  end

  @doc """
  A worked (non-center) tile's yield including its bonus resource
  (story 905): raw terrain + resource + completed improvement, all
  additive — e.g. a Pasture-improved Cattle tile on grassland is
  `2 (terrain) + 1 (resource) + 2 (pasture) = 5` food. The resource-
  blind sibling above (`worked_tile_yield/2`) stays untouched for
  callers that only have a bare terrain + improvement kind.
  """
  @spec worked_tile_yield(
          Terrain.t(),
          nil | :farm | :mine | :road | :pasture,
          Resources.kind() | nil
        ) ::
          yield()
  def worked_tile_yield(terrain, improvement_kind, resource) do
    terrain
    |> worked_tile_yield(improvement_kind)
    |> add_yield(resource_bonus(resource))
  end

  @doc "Citizen auto-assign score: food weighted double (2F + P) — growth is the win condition."
  @spec assignment_score(yield()) :: non_neg_integer()
  def assignment_score(%{food: food, production: production}), do: 2 * food + production

  @doc "Growth tile-pick score: total yield (F + P)."
  @spec growth_score(yield()) :: non_neg_integer()
  def growth_score(%{food: food, production: production}), do: food + production

  # -------------------------------------------------------------------
  # Per-city accrual
  # -------------------------------------------------------------------

  @doc """
  Yields for every currently worked (non-center) tile, in
  `worked_tiles` order — terrain + bonus resource (story 905) +
  completed improvement, all stacked (`worked_tile_yield/3`).
  """
  @spec worked_yields(city(), World.t(), %{tile_id() => improvement()}, MapSet.t(tile_id())) ::
          [yield()]
  def worked_yields(city, world, improvements, cleared_features \\ MapSet.new()) do
    for tile_id <- city.worked_tiles do
      terrain = Regions.terrain(world, tile_id, cleared_features)
      resource = Resources.at(world, tile_id)
      worked_tile_yield(terrain, completed_kind(improvements, tile_id), resource)
    end
  end

  @doc """
  The city center's own yield (always active, never assignable/
  unassignable), including its bonus resource (story 905) if it's
  settled on one.
  """
  @spec center_yield(city(), World.t(), MapSet.t(tile_id())) :: yield()
  def center_yield(city, world, cleared_features \\ MapSet.new()),
    do:
      city_center_yield(
        Regions.terrain(world, city.tile_id, cleared_features),
        Resources.at(world, city.tile_id)
      )

  @doc """
  Bank this turn's food income: the center's floor, every worked
  tile's food, plus the Granary's flat +2 (story 902) and the Water
  Mill's flat +1 (story 930) if `city` has either. Production income
  is a separate concern — `BrokenOaths.Cities.Production.accrue/3`
  (which reads its own `water_mill_production_bonus/0` for that
  building's other half).
  """
  @spec accrue_food(city(), World.t(), %{tile_id() => improvement()}, MapSet.t(tile_id())) ::
          city()
  def accrue_food(city, world, improvements, cleared_features \\ MapSet.new()) do
    center = center_yield(city, world, cleared_features)

    worked_food =
      worked_yields(city, world, improvements, cleared_features)
      |> Enum.map(& &1.food)
      |> Enum.sum()

    %{
      city
      | food: city.food + center.food + worked_food + granary_bonus(city) + water_mill_bonus(city)
    }
  end

  @granary_food_bonus 2

  @doc """
  The Granary's flat per-turn food bonus (story 902, criterion 7629) —
  a public accessor so callers outside this module (QA issue
  `1c47edff`'s `GameLive.CityPanel` Granary indicator) can state the
  real number instead of hardcoding a copy of it that could drift from
  `accrue_food/3`'s own math.
  """
  @spec granary_food_bonus() :: pos_integer()
  def granary_food_bonus, do: @granary_food_bonus

  defp granary_bonus(city) do
    if Map.get(city, :has_granary, false), do: @granary_food_bonus, else: 0
  end

  @water_mill_food_bonus 1

  @doc """
  The Water Mill's flat per-turn food bonus (story 930) — the food half
  of that building's effect; `Production.water_mill_production_bonus/0`
  is the other half. A public accessor for the same "no hardcoded copy"
  reason `granary_food_bonus/0` is.
  """
  @spec water_mill_food_bonus() :: pos_integer()
  def water_mill_food_bonus, do: @water_mill_food_bonus

  defp water_mill_bonus(city) do
    if Buildings.has?(city, :water_mill), do: @water_mill_food_bonus, else: 0
  end

  # -------------------------------------------------------------------
  # Tick-loop food accrual (moved from `BrokenOaths.Simulation.Turn`'s own
  # private `accrue_food/1`, the tick-decomposition pass, see
  # `.code_my_spec/knowledge/genserver_decomposition.md`)
  # -------------------------------------------------------------------

  @doc """
  Bank this turn's food income (`accrue_food/3`) for every city in
  `state.cities`. `state` is the canonical tick-state described in
  `BrokenOaths.Simulation.Turn`.
  """
  @spec accrue_food_all(map()) :: map()
  def accrue_food_all(state) do
    cleared = Map.get(state, :cleared_features, MapSet.new())

    cities =
      Map.new(state.cities, fn {id, city} ->
        {id, accrue_food(city, state.world, state.improvements, cleared)}
      end)

    %{state | cities: cities}
  end

  # -------------------------------------------------------------------
  # Gold (story 912)
  # -------------------------------------------------------------------

  @doc """
  A city's base per-turn gold, scaled by `size` alone (story 912, PO
  decision 2026-07-18): `1 + floor(size/2)` — size 1 -> 1, 2 -> 2,
  3 -> 2, 4 -> 3. Every city earns this regardless of terrain; tile
  gold (`tile_gold/1`) stacks additively on top, the same "base +
  bonus, never multiplicative" shape every other yield in this module
  already follows.
  """
  @spec base_gold(pos_integer()) :: non_neg_integer()
  def base_gold(size), do: 1 + div(size, 2)

  @doc """
  A tile's own gold yield when worked (story 912): Coast (`Terrain.
  base == :coast` — the shallow, workable water ring the generator lays
  down between deep ocean and land, `BrokenOaths.Worlds.Generator`'s
  own `classify/4`, elevation band `[0.30, 0.37)`) yields +1 gold,
  Civ's own "commerce from the sea" convention. Every other terrain
  yields 0 gold — copper/river gold is a deliberately deferred fork
  (story 912's own PO note), not implemented here. Deep ocean
  (`:ocean`) carries no gold either, and is never a real concern in
  practice: nothing in this codebase's territory rules ever lets a
  city claim/work true open ocean.
  """
  @spec tile_gold(Terrain.t()) :: non_neg_integer()
  def tile_gold(%Terrain{base: :coast}), do: 1
  def tile_gold(%Terrain{}), do: 0

  @doc """
  A city's total per-turn gold income (story 912): `base_gold/1` on the
  city's current `size`, plus `tile_gold/1` summed over every currently
  worked (non-center) tile — recomputed fresh from `size`/`worked_tiles`
  every call, exactly like `worked_yields/3`'s own food/production read,
  never cached on the city itself. This is the REAL basis
  `BrokenOaths.Feudal.Tribute`/`BrokenOaths.Feudal.Bank` tax/bank each turn
  boundary, replacing the test-only `set_player_gold_income_for_test`
  seam those two modules' own moduledocs used to document as the only
  source.
  """
  @spec city_gold_income(city(), World.t()) :: non_neg_integer()
  def city_gold_income(city, world) do
    base_gold(city.size) + worked_gold(city, world)
  end

  defp worked_gold(city, world) do
    city.worked_tiles
    |> Enum.map(&(world |> Regions.terrain(&1) |> tile_gold()))
    |> Enum.sum()
  end

  # -------------------------------------------------------------------
  # Growth
  # -------------------------------------------------------------------

  @type age :: :stone_age | :bronze_age

  @doc """
  Food needed to grow FROM this size to size + 1 in the Stone Age
  (arity-1 shorthand for `threshold/2` with `:stone_age` — every
  existing Stone Age caller keeps working unchanged). `nil` at the
  Stone Age cap (size 4).
  """
  @spec threshold(pos_integer()) :: pos_integer() | nil
  def threshold(size), do: threshold(size, :stone_age)

  @doc """
  Food needed to grow FROM this size to size + 1, age-aware (story
  903): the Bronze Age raises the size cap from 4 to 6 — `50` for
  4->5, `60` for 5->6, continuing the Stone Age's own clean +10 curve
  (`.code_my_spec/knowledge/stone_age_yields.md`). `nil` once a Stone
  Age city hits 4 or a Bronze Age city hits 6.
  """
  @spec threshold(pos_integer(), age()) :: pos_integer() | nil
  def threshold(1, _age), do: 20
  def threshold(2, _age), do: 30
  def threshold(3, _age), do: 40
  def threshold(4, :bronze_age), do: 50
  def threshold(5, :bronze_age), do: 60
  def threshold(_capped, _age), do: nil

  @doc "True at the Stone Age size cap (arity-1 shorthand for `capped?/2` with `:stone_age`)."
  @spec capped?(pos_integer()) :: boolean()
  def capped?(size), do: capped?(size, :stone_age)

  @doc """
  True at `age`'s own size cap (story 903: 4 in the Stone Age, 6 in
  the Bronze Age) — growth stops quietly, food still accrues.
  """
  @spec capped?(pos_integer(), age()) :: boolean()
  def capped?(size, :bronze_age), do: size >= 6
  def capped?(size, :stone_age), do: size >= 4

  @doc """
  Apply at most one growth to `city` if its banked food has reached
  threshold, at the Stone Age cap (arity-3 shorthand for `grow/4` with
  `:stone_age` — every existing Stone Age caller keeps working
  unchanged). See `grow/4` for the full behavior.
  """
  @spec grow(city(), [city()], World.t()) :: city()
  def grow(city, all_cities, world), do: grow(city, all_cities, world, :stone_age)

  @doc """
  Apply at most one growth to `city` if its banked food has reached
  threshold: claims one deterministic new tile (respecting every other
  city's prior claims in `all_cities`), grows size by one, carries
  food overflow, and auto-assigns the new citizen a worked tile if one
  is available. A no-op below threshold, at the cap, or exactly at
  threshold with nothing left to claim/work (size and food still
  advance; territory/worked_tiles simply don't gain anything that
  turn). `age` (story 903) decides whether the cap is 4 (Stone Age) or
  6 (Bronze Age) — `Research.age/1` over the city's OWNER, not the city
  itself, since a city has no age of its own. Arity-4 shorthand for
  `grow/5` with `hanging_gardens?: false` — every existing caller keeps
  working unchanged.
  """
  @spec grow(city(), [city()], World.t(), age()) :: city()
  def grow(city, all_cities, world, age), do: grow(city, all_cities, world, age, false)

  @doc """
  `grow/4`, plus the Hanging Gardens' own growth bonus (story 933):
  when `hanging_gardens?` is true, the food required to cross THIS
  growth threshold shrinks by `effective_threshold/2` — see this
  module's own moduledoc, "The Hanging Gardens bonus", for why the
  threshold shrinks rather than the banked food being inflated.
  """
  @spec grow(city(), [city()], World.t(), age(), boolean()) :: city()
  def grow(city, all_cities, world, age, hanging_gardens?) do
    case threshold(city.size, age) do
      nil ->
        city

      raw_thresh ->
        thresh = effective_threshold(raw_thresh, hanging_gardens?)

        if city.food < thresh do
          city
        else
          city
          |> claim_growth_tile(all_cities, world)
          |> settle_growth(thresh)
          |> assign_new_citizen(world)
        end
    end
  end

  # Story 933 — the Hanging Gardens' "+15% growth": integer division,
  # no floats, so the result is always a whole, deterministic food
  # amount (`div(20 * 100, 115) == 17`). A no-op (returns `thresh`
  # unchanged) without the wonder — every existing caller's own math is
  # untouched.
  @hanging_gardens_growth_pct 115

  defp effective_threshold(thresh, false), do: thresh
  defp effective_threshold(thresh, true), do: div(thresh * 100, @hanging_gardens_growth_pct)

  @doc """
  Apply at most one growth (`grow/4`) to every city in `state.cities`,
  in ascending city id order -- each city grows against the CURRENT
  territory of every city (including siblings already grown earlier in
  this same reduce), so two cities eligible for the same tile in one
  tick resolve by ascending city id, the same determinism rule `grow/4`
  itself promises. The size cap (story 903) is the city OWNER's own age
  (`BrokenOaths.Technology.Research.age/1`, read off `state.player_research`
  -- already advanced by `BrokenOaths.Technology.Research.accrue_science/1`
  earlier in the tick pipeline, so a Bronze Working completion lifts
  the cap the instant it lands, same turn), never the city's own state.

  `settled_this_tick` (issue 63300098) is `BrokenOaths.Cities.Production.
  resolve_completions/1`'s own set of city ids that completed a
  `:settler` THIS tick -- a city in that set never grows this same
  tick, even if its banked food already clears the (now one-lower,
  post-pop-cost) next threshold. Without this, a well-fed city's
  settler pop cost and growth cancel out invisibly in the same
  boundary, defeating story 883's "a settler costs the city one
  population" intent. The city's CURRENT (already pop-cost-adjusted)
  state still threads through to its siblings' own territory checks
  below -- only ITS OWN growth is skipped, nothing else about this
  tick's bookkeeping changes. `state` is the canonical tick-state
  described in `BrokenOaths.Simulation.Turn`.
  """
  @spec grow_cities(map(), MapSet.t()) :: map()
  def grow_cities(state, settled_this_tick) do
    ids = state.cities |> Map.keys() |> Enum.sort()
    player_research = Map.get(state, :player_research, %{})

    # Story 933 — Hanging Gardens ownership is invariant across this phase
    # (wonders complete in the earlier production phase; growth never
    # builds one), so resolve the owning players ONCE up front instead of
    # re-scanning every city per city (was O(N^2)).
    hg_players =
      for {_id, c} <- state.cities, Buildings.has?(c, :hanging_gardens), into: MapSet.new(), do: c.player_id

    cities =
      Enum.reduce(ids, state.cities, fn id, cities ->
        city = Map.fetch!(cities, id)

        if MapSet.member?(settled_this_tick, id) do
          cities
        else
          pr = Map.get(player_research, city.player_id, Research.new())
          hanging_gardens? = MapSet.member?(hg_players, city.player_id)
          grown = grow(city, Map.values(cities), state.world, Research.age(pr), hanging_gardens?)
          Map.put(cities, id, grown)
        end
      end)

    %{state | cities: cities}
  end

  @doc "The next deterministic territory claim, or `nil` if nothing adjacent is left to claim."
  @spec pick_growth_tile(city(), [city()], World.t()) :: tile_id() | nil
  def pick_growth_tile(city, all_cities, world) do
    claimed = claimed_tiles(all_cities)

    candidates =
      city.territory
      |> Enum.flat_map(&Regions.adjacent_tiles(world, &1))
      |> Enum.uniq()
      |> Enum.reject(&(&1 in city.territory or MapSet.member?(claimed, &1)))
      |> Enum.filter(&workable?(Regions.terrain(world, &1)))

    pick_best(candidates, &growth_key(world, city.tile_id, &1))
  end

  @doc """
  Story 927 (chopping a worked tile) — drop any of `state.cities`' own
  `worked_tiles` entries that have been permanently Chopped
  (`state.cleared_features`, story 927's own delta set) since they were
  assigned. `assign_new_citizen/2` only ever FILLS a city's worked-tile
  slots when it's under capacity — nothing revisits an EXISTING
  assignment once made, so a citizen working a woods tile stays pinned
  there forever even after a worker chops the feature out from under
  them unless something else evicts it. This is that eviction, run every
  tick (not economy-gated — "by the next turn" means the very next turn
  boundary, not the next economy tick, `economy_turns` defaulting to 10
  would otherwise make this feel arbitrarily delayed).

  Deliberately narrow: only DROPS the stale assignment, it does not
  auto-pick a replacement (`assign_new_citizen/2`'s own economy-tick
  pass already re-fills any city left under capacity, on its own
  schedule — duplicating that here would double-run the same fill
  logic on two different cadences).
  """
  @spec revalidate_worked_tiles(map()) :: map()
  def revalidate_worked_tiles(state) do
    cleared = Map.get(state, :cleared_features, MapSet.new())

    cities =
      Map.new(state.cities, fn {id, city} ->
        {id, %{city | worked_tiles: Enum.reject(city.worked_tiles, &MapSet.member?(cleared, &1))}}
      end)

    %{state | cities: cities}
  end

  @doc "The best unworked, owned, workable tile for a new citizen, or `nil` if none is free."
  @spec pick_worked_tile(city(), World.t()) :: tile_id() | nil
  def pick_worked_tile(city, world) do
    worked = MapSet.new(city.worked_tiles)

    candidates =
      city.territory
      |> Enum.reject(&(&1 == city.tile_id or MapSet.member?(worked, &1)))
      |> Enum.filter(&workable?(Regions.terrain(world, &1)))

    pick_best(candidates, &assignment_key(world, city.tile_id, &1))
  end

  defp claim_growth_tile(city, all_cities, world) do
    case pick_growth_tile(city, all_cities, world) do
      nil -> city
      tile -> %{city | territory: city.territory ++ [tile]}
    end
  end

  defp settle_growth(city, threshold) do
    %{city | size: city.size + 1, food: city.food - threshold}
  end

  defp assign_new_citizen(city, world) do
    if length(city.worked_tiles) < city.size do
      case pick_worked_tile(city, world) do
        nil -> city
        tile -> %{city | worked_tiles: city.worked_tiles ++ [tile]}
      end
    else
      city
    end
  end

  defp claimed_tiles(all_cities) do
    Enum.reduce(all_cities, MapSet.new(), fn city, acc ->
      MapSet.union(acc, MapSet.new(city.territory))
    end)
  end

  defp pick_best([], _key_fun), do: nil
  defp pick_best(candidates, key_fun), do: Enum.min_by(candidates, key_fun)

  # -------------------------------------------------------------------
  # Deterministic tiebreak keys
  # -------------------------------------------------------------------

  # Both keys fold in the tile's bonus resource (story 905, criterion
  # 7650: "a city works its resource tile first") on top of raw
  # terrain — a resource tile's own additive bonus can only ever raise
  # its score, never lower a plain tile's, so ties still resolve the
  # same deterministic way whether or not either candidate happens to
  # carry one.
  defp growth_key(world, center_tile, tile_id) do
    yield = candidate_yield(world, tile_id)

    {-growth_score(yield), -yield.food, ring_distance(world, center_tile, tile_id),
     compass_bucket(world, center_tile, tile_id), tile_id}
  end

  defp assignment_key(world, center_tile, tile_id) do
    yield = candidate_yield(world, tile_id)

    {-assignment_score(yield), ring_distance(world, center_tile, tile_id),
     compass_bucket(world, center_tile, tile_id), tile_id}
  end

  defp candidate_yield(world, tile_id) do
    terrain = Regions.terrain(world, tile_id)
    add_yield(tile_yield(terrain), resource_bonus(Resources.at(world, tile_id)))
  end

  defp add_yield(%{food: f1, production: p1}, %{food: f2, production: p2}),
    do: %{food: f1 + f2, production: p1 + p2}

  # Unfiltered mesh-hop BFS distance — candidates are always within a
  # handful of rings of `from` (a Stone Age city tops out at size 4),
  # so this terminates almost immediately; the depth cap is a pure
  # safety net against a malformed mesh, never expected to bite.
  defp ring_distance(_world, from, from), do: 0
  defp ring_distance(world, from, to), do: grow_ring(world, MapSet.new([from]), [from], to, 1)

  @max_ring_depth 12
  defp grow_ring(_world, _seen, _frontier, _to, depth) when depth > @max_ring_depth, do: 999

  defp grow_ring(world, seen, frontier, to, depth) do
    next =
      frontier
      |> Enum.flat_map(&Regions.adjacent_tiles(world, &1))
      |> Enum.uniq()
      |> Enum.reject(&MapSet.member?(seen, &1))

    cond do
      to in next -> depth
      next == [] -> 999
      true -> grow_ring(world, MapSet.union(seen, MapSet.new(next)), next, to, depth + 1)
    end
  end

  # Great-circle initial bearing from `from` to `to`, bucketed into the
  # six 60°-wide hex directions starting at N (0 = N, 1 = NE, 2 = SE,
  # 3 = S, 4 = SW, 5 = NW), ascending = the fixed compass order.
  defp compass_bucket(world, from, to) do
    mesh = Globe.get(world.frequency)
    {from_lat, from_lon} = Globe.latlon(Globe.tile(mesh, from).center)
    {to_lat, to_lon} = Globe.latlon(Globe.tile(mesh, to).center)

    from_lat
    |> bearing_degrees(from_lon, to_lat, to_lon)
    |> Kernel./(60)
    |> round()
    |> rem(6)
  end

  defp bearing_degrees(lat1, lon1, lat2, lon2) do
    phi1 = deg2rad(lat1)
    phi2 = deg2rad(lat2)
    dlon = deg2rad(lon2 - lon1)

    y = :math.sin(dlon) * :math.cos(phi2)
    x = :math.cos(phi1) * :math.sin(phi2) - :math.sin(phi1) * :math.cos(phi2) * :math.cos(dlon)

    degrees = :math.atan2(y, x) * 180.0 / :math.pi()
    :math.fmod(degrees + 360.0, 360.0)
  end

  defp deg2rad(degrees), do: degrees * :math.pi() / 180.0

  defp completed_kind(improvements, tile_id) do
    case Map.get(improvements, tile_id) do
      %{status: :complete, kind: kind} -> kind
      _ -> nil
    end
  end

  # -------------------------------------------------------------------
  # Yield table (base + relief + feature, additive stacking)
  # -------------------------------------------------------------------

  defp base_yield(:grassland), do: {2, 0}
  defp base_yield(:plains), do: {1, 1}
  defp base_yield(:desert), do: {0, 0}
  defp base_yield(:tundra), do: {1, 0}
  defp base_yield(:snow), do: {0, 0}
  defp base_yield(:coast), do: {1, 0}
  defp base_yield(:ocean), do: {1, 0}

  defp relief_bonus(:hills), do: 1
  defp relief_bonus(_other), do: 0

  defp feature_food_bonus(feature) when feature in [:rainforest, :marsh], do: 1
  defp feature_food_bonus(_other), do: 0

  defp feature_production_bonus(:woods), do: 1
  defp feature_production_bonus(_other), do: 0
end
