defmodule BrokenOaths.Units.Maintenance do
  @moduledoc """
  Stories 922/923's gold-maintenance economy: a pure per-type gold
  upkeep catalog, mirroring `BrokenOaths.Units.Actions`'s own shape — no
  `Repo`, no process state, no world/terrain access, just "what does one
  of these cost per turn." Numbers are Civ-6-grounded (leader, civilian,
  and the free starter warrior cost nothing; every OTHER military unit
  costs 1): `:lord`/`:settler`/`:worker`/`:warrior` are `0`,
  `:archer`/`:bronze_spearman`/`:galley`/`:scout` (story 931) are `1`.

  `:barbarian_warrior` is never player-owned (`BrokenOaths.Units.Unit`'s
  own moduledoc: it carries `camp_id`, never `player_id`), so it has no
  catalog entry at all — `upkeep/1` still answers `0` for it (and any
  other unrecognized type) rather than raising, since nobody ever OWES
  for a unit nobody owns; `BrokenOaths.Feudal.Bank.maintenance_by_player/1`
  never sums a barbarian's upkeep into any player's bill regardless,
  because it groups by `player_id` and a barbarian has none.

  `BrokenOaths.Feudal.Bank` is the one caller outside `Units` (the
  turn-boundary upkeep sweep, `apply_upkeep/2`) — reached through `Units`/
  `Game` only if some OTHER caller ever needs it; none does yet.
  """

  @type unit_type :: BrokenOaths.Units.Unit.unit_type()
  @type unit :: %{optional(atom()) => term(), type: unit_type()}

  @catalog %{
    lord: 0,
    settler: 0,
    worker: 0,
    warrior: 0,
    archer: 1,
    bronze_spearman: 1,
    galley: 1,
    scout: 1
  }

  @doc "The full per-type upkeep catalog — every player-owned unit type declares its own entry (this module's own guardrail: 0 is allowed, but never an omission)."
  @spec catalog() :: %{unit_type() => non_neg_integer()}
  def catalog, do: @catalog

  @doc """
  Gold upkeep/turn for `unit_or_type` — a bare type atom or a unit-shaped
  map both work, same calling convention `Units.Actions.available/1`
  offers. `:barbarian_warrior` (never player-owned) and any type this
  catalog doesn't recognize both fall back to `0` — see this module's
  own moduledoc for why that's a safe default rather than a guardrail
  violation.
  """
  @spec upkeep(unit_type() | unit()) :: non_neg_integer()
  def upkeep(%{type: type}), do: upkeep(type)
  def upkeep(type) when is_atom(type), do: Map.get(@catalog, type, 0)
end
