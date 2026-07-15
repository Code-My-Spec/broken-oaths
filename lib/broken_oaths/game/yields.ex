defmodule BrokenOaths.Game.Yields do
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
  added again on top of `BrokenOaths.Game.Production`'s flat-5 base —
  the flat base already stands in for it (a real terrain floor would
  double-count); only its food counts toward growth.

  ## Deterministic tile-picking

  Both growth's territory claim and a new citizen's tile assignment
  score candidates and break ties the same way: highest score first,
  then (growth only) higher food, then smaller ring-distance from the
  city's own tile, then a fixed compass order (N, NE, SE, S, SW, NW —
  the six hex directions, by great-circle bearing from the city tile),
  then lowest tile id as a final, always-decisive tiebreak.
  """

  alias BrokenOaths.Worlds.Globe
  alias BrokenOaths.Worlds.Regions
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
  @type improvement :: %{kind: :farm | :mine | :road, status: :building | :complete}

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

  @doc "The city center's yield: raw terrain, floored at 2 food / 1 production."
  @spec city_center_yield(Terrain.t()) :: yield()
  def city_center_yield(terrain) do
    yield = tile_yield(terrain)
    %{food: max(yield.food, 2), production: max(yield.production, 1)}
  end

  @doc "False for mountains and ice — never claimable by growth, never assignable to a citizen."
  @spec workable?(Terrain.t()) :: boolean()
  def workable?(%Terrain{relief: :mountains}), do: false
  def workable?(%Terrain{feature: :ice}), do: false
  def workable?(%Terrain{}), do: true

  @doc "A completed improvement's yield bonus (farm +2 food, mine +2 production, road none)."
  @spec improvement_bonus(nil | :farm | :mine | :road) :: yield()
  def improvement_bonus(:farm), do: %{food: 2, production: 0}
  def improvement_bonus(:mine), do: %{food: 0, production: 2}
  def improvement_bonus(:road), do: %{food: 0, production: 0}
  def improvement_bonus(nil), do: %{food: 0, production: 0}

  @doc "A worked (non-center) tile's yield: raw terrain plus its completed improvement, if any."
  @spec worked_tile_yield(Terrain.t(), nil | :farm | :mine | :road) :: yield()
  def worked_tile_yield(terrain, improvement_kind) do
    base = tile_yield(terrain)
    bonus = improvement_bonus(improvement_kind)
    %{food: base.food + bonus.food, production: base.production + bonus.production}
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

  @doc "Yields for every currently worked (non-center) tile, in `worked_tiles` order."
  @spec worked_yields(city(), World.t(), %{tile_id() => improvement()}) :: [yield()]
  def worked_yields(city, world, improvements) do
    for tile_id <- city.worked_tiles do
      terrain = Regions.terrain(world, tile_id)
      worked_tile_yield(terrain, completed_kind(improvements, tile_id))
    end
  end

  @doc "The city center's own yield (always active, never assignable/unassignable)."
  @spec center_yield(city(), World.t()) :: yield()
  def center_yield(city, world), do: city_center_yield(Regions.terrain(world, city.tile_id))

  @doc """
  Bank this turn's food income: the center's floor plus every worked
  tile's food. Production income is a separate concern —
  `BrokenOaths.Game.Production.accrue/3`.
  """
  @spec accrue_food(city(), World.t(), %{tile_id() => improvement()}) :: city()
  def accrue_food(city, world, improvements) do
    center = center_yield(city, world)
    worked_food = worked_yields(city, world, improvements) |> Enum.map(& &1.food) |> Enum.sum()
    %{city | food: city.food + center.food + worked_food}
  end

  # -------------------------------------------------------------------
  # Growth
  # -------------------------------------------------------------------

  @doc "Food needed to grow FROM this size to size + 1. `nil` at the Stone Age cap (size 4)."
  @spec threshold(pos_integer()) :: pos_integer() | nil
  def threshold(1), do: 20
  def threshold(2), do: 30
  def threshold(3), do: 40
  def threshold(_capped), do: nil

  @doc "True at the Stone Age size cap — growth stops quietly, food still accrues."
  @spec capped?(pos_integer()) :: boolean()
  def capped?(size), do: size >= 4

  @doc """
  Apply at most one growth to `city` if its banked food has reached
  threshold: claims one deterministic new tile (respecting every other
  city's prior claims in `all_cities`), grows size by one, carries
  food overflow, and auto-assigns the new citizen a worked tile if one
  is available. A no-op below threshold, at the cap, or exactly at
  threshold with nothing left to claim/work (size and food still
  advance; territory/worked_tiles simply don't gain anything that
  turn).
  """
  @spec grow(city(), [city()], World.t()) :: city()
  def grow(city, all_cities, world) do
    case threshold(city.size) do
      nil ->
        city

      thresh when city.food < thresh ->
        city

      thresh ->
        city
        |> claim_growth_tile(all_cities, world)
        |> settle_growth(thresh)
        |> assign_new_citizen(world)
    end
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

  defp growth_key(world, center_tile, tile_id) do
    yield = tile_yield(Regions.terrain(world, tile_id))

    {-growth_score(yield), -yield.food, ring_distance(world, center_tile, tile_id),
     compass_bucket(world, center_tile, tile_id), tile_id}
  end

  defp assignment_key(world, center_tile, tile_id) do
    yield = tile_yield(Regions.terrain(world, tile_id))

    {-assignment_score(yield), ring_distance(world, center_tile, tile_id),
     compass_bucket(world, center_tile, tile_id), tile_id}
  end

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
