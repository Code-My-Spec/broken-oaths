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

  `:defend` (every player-commandable type carries it) isn't wired to
  a `BrokenOaths.Game` command of its own — "defending" is simply
  choosing not to move (or not to spend every point of movement) this
  turn, which every unit can already do with no explicit order; it's
  listed here only so this catalog answers the QA issue's own
  "build farm, shoot arrows, defend, etc." vocabulary completely, not
  because there's a `"defend"` LiveView event or a `Game.defend/2` to
  gate. A future story that DOES give "defend" real teeth (a
  fortify-style combat bonus, say) has a name to key off of already.

  `:barbarian_warrior` carries `:move`/`:attack` only — no `:defend`
  (barbarians are never player-commanded, so "choosing" a stance is
  meaningless for one) and no civilian/settler actions (a barbarian
  warrior never founds cities or builds improvements).
  """

  @type unit :: %{optional(atom()) => term(), type: atom()}
  @type action :: :move | :found_city | :build_improvement | :attack | :shoot | :defend

  @doc """
  The action kinds `unit`'s own TYPE ever carries — `nil` (nothing
  selected) reports no actions at all.
  """
  @spec available(unit() | nil) :: [action()]
  def available(nil), do: []

  def available(%{type: :settler}), do: [:move, :found_city, :defend]

  def available(%{type: :worker}), do: [:move, :build_improvement, :defend]

  # QA issue 12bed1e4 — the Archer keeps its existing melee `:attack`
  # (the QA-issue-da39e50b first pass never took that away) AND gains
  # `:shoot`, its own ranged sibling — see `BrokenOaths.Combat.Resolver`'s
  # own "Ranged" doc for the mechanic `:shoot` actually drives.
  def available(%{type: :archer}), do: [:move, :attack, :shoot, :defend]

  def available(%{type: type}) when type in [:lord, :warrior, :bronze_spearman],
    do: [:move, :attack, :defend]

  def available(%{type: :barbarian_warrior}), do: [:move, :attack]

  def available(%{type: _other}), do: [:move]
end
