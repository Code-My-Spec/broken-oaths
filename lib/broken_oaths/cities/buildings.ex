defmodule BrokenOaths.Cities.Buildings do
  @moduledoc """
  Story 923's building-maintenance catalog — the first module built to
  `.code_my_spec/knowledge/building_convention.md`: a building's gold
  upkeep lives in ONE place, never scattered wiring. Today's only
  building, `:granary` (Pottery-gated, `BrokenOaths.Cities.Production.
  granary_available?/2`), costs `1` gold/turn — every catalog entry
  states its upkeep explicitly (`0` is allowed, an omission is not),
  same guardrail `BrokenOaths.Units.Maintenance` keeps for units.

  Production cost and the tech gate for `:granary` already live in
  `BrokenOaths.Cities.Production`/`BrokenOaths.Technology.Research` —
  this module doesn't duplicate them (a second source of truth is
  exactly the drift the building convention warns about); it's the new
  home for the ONE property that was missing entirely: maintenance.

  ## Storage vs catalog

  A city still records which buildings it HAS via its own boolean field
  (`has_granary` on `BrokenOaths.Cities.City`) — this catalog doesn't
  change that storage, it only reads it: `city_upkeep/1` asks "what does
  THIS city, with the buildings it actually has, owe per turn," the same
  read `BrokenOaths.Feudal.Bank.maintenance_by_player/1` sums across a
  player's whole city list for the turn-boundary sweep (stories
  922/923's shared settlement path — see that module's own moduledoc).
  """

  @type building :: :granary
  @type city :: %{optional(atom()) => term()}

  @catalog %{granary: 1}

  @doc "The full per-building maintenance catalog."
  @spec catalog() :: %{building() => non_neg_integer()}
  def catalog, do: @catalog

  @doc "Gold upkeep/turn for `building` — raises for an undeclared building rather than silently defaulting, per this module's own guardrail."
  @spec maintenance(building()) :: non_neg_integer()
  def maintenance(building), do: Map.fetch!(@catalog, building)

  @doc """
  `city`'s own total building upkeep this turn — sums `maintenance/1`
  over whichever buildings `city`'s own fields say it HAS (today, just
  `has_granary`). `Map.get/3` defaults `has_granary` to `false` so a
  hand-built fixture that predates the field never raises, the same
  defensive idiom `Units.Unit.fortified?/1` already uses for
  `fortified_turns`.
  """
  @spec city_upkeep(city()) :: non_neg_integer()
  def city_upkeep(city) do
    if Map.get(city, :has_granary, false), do: maintenance(:granary), else: 0
  end
end
