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
  """

  @type building :: :granary | :library | :ancient_walls | :barracks | :water_mill
  @type city :: %{optional(atom()) => term()}

  @catalog %{
    granary: 1,
    library: 1,
    ancient_walls: 0,
    barracks: 1,
    water_mill: 1
  }

  @doc "The full per-building maintenance catalog."
  @spec catalog() :: %{building() => non_neg_integer()}
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
    @catalog
    |> Map.keys()
    |> Enum.filter(&has?(city, &1))
    |> Enum.map(&maintenance/1)
    |> Enum.sum()
  end
end
