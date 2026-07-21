defmodule BrokenOaths.Units.Actions do
  @moduledoc """
  The "units.actions context" QA issue 12bed1e4 asked for: a pure
  catalog of which general action KINDS a unit type carries — `:move`
  for everything, `:found_city` for a Settler, `:build_improvement`
  for a Worker, `:attack` for every melee-capable military type, and
  (QA issue 12bed1e4's own new addition) `:shoot` for an Archer. No
  `Repo`, no process state, no world/terrain access — this module
  answers "what KIND of thing can this unit type ever do," never "is
  THIS SPECIFIC move/target legal right now" (that stays with the
  module that already owns the real rule: `BrokenOaths.Combat.Resolver.
  validate_attack/3`/`shoot/4` for combat legality, `BrokenOathsWeb.
  GameLive.PlayView.worker_allowed_improvements/3` for which
  improvement kinds a worker's own tile supports, `PlayView.
  attackable_cities/3` for which cities a military unit may besiege
  right now). `available/1` is deliberately coarse so callers can use
  it as a cheap TYPE gate — "does this unit's type even carry
  `:build_improvement` at all" — before reaching for the real,
  state-aware rule.

  ## Vocabulary

  `:defend` (every player-commandable type carries it) is the type-gate
  for the Fortify stance (story 920, `BrokenOaths.Units.Unit.fortify/3`
  — `:defend in available(unit)` is exactly the check `fortify/3` runs
  before setting the flag) but isn't itself a `Game` command: merely
  standing still costs nothing and needs no order, same as it always
  did. It's listed here so this catalog answers the QA issue's own
  "build farm, shoot arrows, defend, etc." vocabulary completely, not
  because there's a `"defend"` LiveView event of its own.

  `:barbarian_warrior` carries `:move`/`:attack` only — no `:defend`
  (barbarians are never player-commanded, so "choosing" a stance is
  meaningless for one) and no civilian/settler actions (a barbarian
  warrior never founds cities or builds improvements).

  `:galley` (story 921, the first naval unit) ALSO carries `:move`/
  `:attack` only, same as a barbarian — but for a different reason: V1
  naval scope is deliberately narrow (the story's own locked design
  decisions), so a Galley gets none of a land combat unit's `:defend`
  Fortify stance yet, and obviously none of a civilian's `:found_city`/
  `:build_improvement` (a Galley carries no settler or worker
  actions).
  """

  @type unit :: %{optional(atom()) => term(), type: atom()}
  @type action :: :move | :found_city | :build_improvement | :chop | :attack | :shoot | :defend

  @doc """
  The action kinds `unit`'s own TYPE ever carries — `nil` (nothing
  selected) reports no actions at all.
  """
  @spec available(unit() | nil) :: [action()]
  def available(nil), do: []

  def available(%{type: :settler}), do: [:move, :found_city, :defend]

  # Story 927 — `:chop` joins `:build_improvement` as a Worker-only
  # coarse type gate: a worker standing on a Woods/Rainforest tile may
  # Chop it (`BrokenOaths.Cities.Improvement.chop/3`'s own doc has the
  # real, state-aware legality — tech gate, territory, a charge left,
  # no hostile co-occupant).
  def available(%{type: :worker}), do: [:move, :build_improvement, :chop, :defend]

  # QA issue 12bed1e4 — the Archer keeps its existing melee `:attack`
  # (the QA-issue-da39e50b first pass never took that away) AND gains
  # `:shoot`, its own ranged sibling — see `BrokenOaths.Combat.Resolver`'s
  # own "Ranged" doc for the mechanic `:shoot` actually drives.
  def available(%{type: :archer}), do: [:move, :attack, :shoot, :defend]

  def available(%{type: type}) when type in [:lord, :warrior, :bronze_spearman, :scout],
    do: [:move, :attack, :defend]

  # Story 921 — see this module's own moduledoc, "Vocabulary".
  def available(%{type: :galley}), do: [:move, :attack]

  def available(%{type: :barbarian_warrior}), do: [:move, :attack]

  def available(%{type: _other}), do: [:move]
end
