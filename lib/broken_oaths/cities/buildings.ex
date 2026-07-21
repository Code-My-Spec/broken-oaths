defmodule BrokenOaths.Cities.Buildings do
  @moduledoc """
  Story 923's building-maintenance catalog — the first module built to
  `.code_my_spec/knowledge/building_convention.md`: a building's gold
  upkeep lives in ONE place, never scattered wiring. Every catalog entry
  states its upkeep explicitly (`0` is allowed, an omission is not),
  same guardrail `BrokenOaths.Units.Maintenance` keeps for units.

  Story 930 adds four more buildings on top of the Granary: Library
  (Writing-gated, 1 gold/turn), Ancient Walls (Masonry-gated, 0 —
  Civ 6's own Walls carry no upkeep either), Barracks (Bronze
  Working-gated, 1 gold/turn), and Water Mill (The Wheel-gated, 1
  gold/turn).

  Production cost and each building's tech gate already live in
  `BrokenOaths.Cities.Production`/`BrokenOaths.Technology.Research` —
  this module doesn't duplicate them (a second source of truth is
  exactly the drift the building convention warns about); it's the
  home for the ONE property that was missing entirely: maintenance.

  ## Storage vs catalog

  A city records which buildings it HAS two ways: `has_granary`, a
  lone boolean on `BrokenOaths.Cities.City` (story 902, untouched by
  this story), and — for every building since — a `buildings` LIST
  field (story 930; see that field's own doc on `City` for why four
  more buildings got a list instead of four more parallel booleans).
  This catalog doesn't change either storage, it only reads it:
  `has?/2` is the one place that knows which of the two a given
  building lives in, so `city_upkeep/1` can ask "what does THIS city,
  with the buildings it actually has, owe per turn" without its own
  caller (`BrokenOaths.Feudal.Bank.maintenance_by_player/1`, which sums
  this across a player's whole city list for the turn-boundary sweep —
  stories 922/923's shared settlement path) needing to know that split
  exists at all.

  ## Wonders (story 933): Pyramids and Hanging Gardens

  Two more buildings land in the exact same `buildings` list — 0
  upkeep each, wonders are maintenance-free in Civ 6 too — but they're
  a different SHAPE of building: world-unique. Every standard building
  above caps at one PER CITY (`can_queue?/3`'s own `:already_built`);
  a wonder caps at one PER WORLD, across every city any player owns.
  `wonder?/1` flags the two; `wonder_built_or_building?/2` is the
  world-wide read `BrokenOaths.Cities.Production.can_queue?/3` gates
  `:pyramids`/`:hanging_gardens` on instead of the per-city
  `:already_built` check, and `player_has?/3` is the player-wide read
  their own EFFECTS need (a wonder is built in exactly one city, but
  its bonus always applies empire-wide — the Pyramids' extra Worker
  charge, `BrokenOaths.Simulation.WorldServer`'s own
  `worker_charges/3`, and the Hanging Gardens' growth bonus,
  `BrokenOaths.Cities.Yields.grow_cities/2` — the same player-wide
  shape `BrokenOaths.Cities.Production.player_copper_access?/2`
  already established for Copper).
  """

  @type building ::
          :granary
          | :library
          | :ancient_walls
          | :barracks
          | :water_mill
          | :pyramids
          | :hanging_gardens
  @type city :: %{optional(atom()) => term()}

  @catalog %{
    granary: 1,
    library: 1,
    ancient_walls: 0,
    barracks: 1,
    water_mill: 1,
    pyramids: 0,
    hanging_gardens: 0
  }

  @doc "The full per-building maintenance catalog."
  @spec catalog() :: %{building() => non_neg_integer()}
  @catalog_keys Map.keys(@catalog)

  def catalog, do: @catalog

  @doc "Gold upkeep/turn for `building` — raises for an undeclared building rather than silently defaulting, per this module's own guardrail."
  @spec maintenance(building()) :: non_neg_integer()
  def maintenance(building), do: Map.fetch!(@catalog, building)

  @doc """
  Whether `city` has completed `building` — `:granary` reads the lone
  `has_granary` boolean (story 902), every other building reads the
  `buildings` list (story 930). `Map.get/3` defaults both fields to
  `false`/`[]` so a hand-built fixture that predates either field never
  raises, the same defensive idiom `Units.Unit.fortified?/1` already
  uses for `fortified_turns`.
  """
  @spec has?(city(), building()) :: boolean()
  def has?(city, :granary), do: Map.get(city, :has_granary, false)
  def has?(city, building), do: building in Map.get(city, :buildings, [])

  @doc """
  `city`'s own total building upkeep this turn — sums `maintenance/1`
  over whichever buildings `has?/2` says it HAS, across the whole
  catalog.
  """
  @spec city_upkeep(city()) :: non_neg_integer()
  def city_upkeep(city) do
    @catalog_keys
    |> Enum.filter(&has?(city, &1))
    |> Enum.map(&maintenance/1)
    |> Enum.sum()
  end

  @wonders [:pyramids, :hanging_gardens]

  @doc "Whether `building` is a world-unique wonder (Pyramids, Hanging Gardens) rather than a standard, per-city buildable (story 933)."
  @spec wonder?(building()) :: boolean()
  def wonder?(building), do: building in @wonders

  @doc """
  Whether `wonder` is already completed in ANY city, OR is currently
  queued (not yet complete) in ANY city's own build queue, anywhere in
  `cities` — the ONE-PER-WORLD gate a wonder needs instead of the
  per-city `:already_built` check every standard building uses (a
  wonder has no per-city cap to begin with; its cap is world-wide,
  across every player). `cities` is expected to carry each city's own
  `:queue` (the `queue_item()` shape `BrokenOaths.Cities.Production`
  already threads through `state.cities`), not just `:buildings` —
  a wonder mid-build (banked but not yet complete) counts as claimed
  too, so a second city can't start racing to finish first.
  """
  @spec wonder_built_or_building?([city()], building()) :: boolean()
  def wonder_built_or_building?(cities, wonder) do
    Enum.any?(cities, fn city ->
      has?(city, wonder) or Enum.any?(Map.get(city, :queue, []), &(&1.type == wonder))
    end)
  end

  @doc """
  Whether `player_id` has completed `building` in ANY city they own —
  the player-wide read `BrokenOaths.Cities.Production.
  player_copper_access?/2` already established for Copper access
  (story 911), reused here for a wonder's empire-wide effect (story
  933): a wonder is built in exactly ONE city, but its effect always
  reads back player-wide, never scoped to just that one city.
  """
  @spec player_has?([city()], term(), building()) :: boolean()
  def player_has?(cities, player_id, building) do
    cities
    |> Enum.filter(&(Map.get(&1, :player_id) == player_id))
    |> Enum.any?(&has?(&1, building))
  end
end
