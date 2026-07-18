defmodule BrokenOaths.Game.Research do
  @moduledoc """
  Pure tech-tree core (story 902): the four Stone Age techs and their
  science cost, converting a player's cities into science income,
  banking that income toward whichever tech is currently selected, and
  completing a tech once its cost is banked. No `Repo`: every function
  here takes and returns a plain `player_research()` map — the same
  "pure functional core, `WorldServer` is the imperative shell" split
  `BrokenOaths.Game.Production`/`BrokenOaths.Game.Yields` already use.
  `BrokenOaths.Game.PlayerResearch` is the Ecto-backed persistence
  shape this module's maps round-trip through.

  ## Science generation

  Every city generates `2 * size` science per turn (`science_per_turn/1`)
  — population is the only science lever in this MVP (see
  `.code_my_spec/knowledge/civ6_tech_tree.md`), so `size` (a city's
  population, same field `BrokenOaths.Game.Yields.threshold/1` grows
  against) stands in for Civ's Palace + Campus + Library stack.

  ## One tech at a time, banked per tech

  `current_research` names at most one tech; `banked_science` tracks
  progress for EVERY tech independently, so switching
  `current_research` (`set_research/2`) never discards progress on the
  tech switched away from — resuming it later picks up exactly where
  it left off. A tech already in `completed_techs` can never be
  (re-)selected.

  ## Unlocks

  Completing a tech (`complete/1`) only ever moves it from
  `current_research` into `completed_techs` — every unlock's actual
  EFFECT is read back out of `completed_techs` on demand
  (`mine_duration/1`, `granary_enabled?/1`, `pasture_enabled?/1`,
  `age/1`), so there is exactly one source of truth for "has this
  player unlocked X" and no separate flag can ever drift out of sync
  with it. Story 903 (Bronze Age units) should read `age/1` rather than
  adding its own tracking field; story 905 (Pasture/resources) should
  read `pasture_enabled?/1` the same way. `mine_duration/1` is
  computed here but not yet wired into
  `BrokenOaths.Game.Improvement.duration/1`/`BrokenOaths.Game.Turn`'s
  improvement-progress phase — improvements in this codebase aren't
  player-owned (any player's worker can resume one), so "whose
  research decides the duration" needs its own design call before that
  wiring happens.
  """

  @type tech :: :animal_husbandry | :pottery | :mining | :bronze_working
  @type age :: :stone_age | :bronze_age

  @type player_research :: %{
          completed_techs: [tech()],
          current_research: tech() | nil,
          banked_science: %{tech() => non_neg_integer()}
        }

  @type city :: %{required(:size) => pos_integer(), optional(atom()) => term()}

  @type set_research_error :: :invalid_tech | :already_completed

  @science_per_pop 2

  @catalog %{
    animal_husbandry: %{
      cost: 50,
      unlock: "Enables the Pasture improvement (+2 food on animal resources)"
    },
    pottery: %{cost: 50, unlock: "Enables the Granary building (+2 food storage)"},
    mining: %{cost: 75, unlock: "Workers build mines in 3 turns instead of 5"},
    bronze_working: %{cost: 100, unlock: "Advances your civilization to the Bronze Age"}
  }

  @techs Map.keys(@catalog)

  # -------------------------------------------------------------------
  # Catalog
  # -------------------------------------------------------------------

  @doc "Every Stone Age tech, in a fixed presentation order."
  @spec techs() :: [tech()]
  def techs, do: [:animal_husbandry, :pottery, :mining, :bronze_working]

  @doc "The full tech catalog: `%{tech => %{cost:, unlock:}}` — what a TechPanel lists."
  @spec catalog() :: %{tech() => %{cost: pos_integer(), unlock: String.t()}}
  def catalog, do: @catalog

  @doc "A tech's science cost."
  @spec cost(tech()) :: pos_integer()
  def cost(tech), do: fetch_tech!(tech).cost

  @doc "A tech's unlock, in prose — what a TechPanel shows as \"why research this\"."
  @spec unlock_description(tech()) :: String.t()
  def unlock_description(tech), do: fetch_tech!(tech).unlock

  defp fetch_tech!(tech), do: Map.fetch!(@catalog, tech)

  # -------------------------------------------------------------------
  # Fresh state
  # -------------------------------------------------------------------

  @doc "A fresh player's research state: nothing completed, nothing selected, nothing banked."
  @spec new() :: player_research()
  def new, do: %{completed_techs: [], current_research: nil, banked_science: %{}}

  # -------------------------------------------------------------------
  # Science generation
  # -------------------------------------------------------------------

  @doc "A player's total science income this turn: `2 * size` summed over every one of their cities."
  @spec science_per_turn([city()]) :: non_neg_integer()
  def science_per_turn(cities) do
    cities |> Enum.map(&(&1.size * @science_per_pop)) |> Enum.sum()
  end

  # -------------------------------------------------------------------
  # Selecting research
  # -------------------------------------------------------------------

  @doc """
  Select `tech` as `current_research`, retaining whatever science was
  already banked for it (and for every other tech). Refuses an unknown
  tech or one already completed.
  """
  @spec set_research(player_research(), tech()) ::
          {:ok, player_research()} | {:error, set_research_error()}
  def set_research(player_research, tech) do
    case {tech in @techs, tech in player_research.completed_techs} do
      {false, _} -> {:error, :invalid_tech}
      {true, true} -> {:error, :already_completed}
      {true, false} -> {:ok, %{player_research | current_research: tech}}
    end
  end

  # -------------------------------------------------------------------
  # Banking + completion
  # -------------------------------------------------------------------

  @doc "Science currently banked toward `tech` (0 if none has ever been banked)."
  @spec banked(player_research(), tech()) :: non_neg_integer()
  def banked(player_research, tech), do: Map.get(player_research.banked_science, tech, 0)

  @doc """
  Bank `income` science toward `current_research`. A no-op with nothing
  selected — science generated with no active research is simply not
  banked anywhere (mirrors `BrokenOaths.Game.Production.accrue/3`'s
  own no-op on an empty queue).
  """
  @spec accrue(player_research(), non_neg_integer()) :: player_research()
  def accrue(%{current_research: nil} = player_research, _income), do: player_research

  def accrue(%{current_research: tech} = player_research, income) do
    banked_science = Map.update(player_research.banked_science, tech, income, &(&1 + income))
    %{player_research | banked_science: banked_science}
  end

  @doc "Whether `current_research` has banked at least its cost."
  @spec ready?(player_research()) :: boolean()
  def ready?(%{current_research: nil}), do: false

  def ready?(%{current_research: tech} = player_research),
    do: banked(player_research, tech) >= cost(tech)

  @doc """
  Complete `current_research`: moves it into `completed_techs` and
  clears `current_research` (the player must explicitly pick a next
  tech — see `set_research/2`). Refuses to complete with nothing
  selected, or with less than its cost banked.
  """
  @spec complete(player_research()) ::
          {:ok, player_research()} | {:error, :no_current_research | :not_ready}
  def complete(%{current_research: nil}), do: {:error, :no_current_research}

  def complete(%{current_research: tech} = player_research) do
    if ready?(player_research) do
      completed = %{
        player_research
        | completed_techs: Enum.uniq([tech | player_research.completed_techs]),
          current_research: nil
      }

      {:ok, completed}
    else
      {:error, :not_ready}
    end
  end

  @doc """
  One turn's worth of research: bank `income` toward `current_research`,
  then complete it if that reached its cost. Returns
  `{new_player_research, completed_tech | nil}` — the shape
  `BrokenOaths.Game.Turn`'s own tick phases return (an optional event
  alongside the new state), ready to drive a `{:tech_completed, ...}`
  event the same way `{:unit_spawned, ...}` is built from
  `BrokenOaths.Game.Production.complete/3`.
  """
  @spec accrue_and_complete(player_research(), non_neg_integer()) ::
          {player_research(), tech() | nil}
  def accrue_and_complete(player_research, income) do
    accrued = accrue(player_research, income)

    case complete(accrued) do
      {:ok, completed} -> {completed, accrued.current_research}
      {:error, _reason} -> {accrued, nil}
    end
  end

  @doc "`%{tech:, banked:, cost:}` for `current_research`, or `nil` if nothing is selected."
  @spec progress(player_research()) ::
          %{tech: tech(), banked: non_neg_integer(), cost: pos_integer()} | nil
  def progress(%{current_research: nil}), do: nil

  def progress(%{current_research: tech} = player_research),
    do: %{tech: tech, banked: banked(player_research, tech), cost: cost(tech)}

  # -------------------------------------------------------------------
  # Unlocks
  # -------------------------------------------------------------------

  @doc "Whether `tech` has been completed."
  @spec completed?(player_research(), tech()) :: boolean()
  def completed?(player_research, tech), do: tech in player_research.completed_techs

  @doc "Mining's unlock: 3 turns to build a mine once researched, else the base 5."
  @spec mine_duration(player_research()) :: 3 | 5
  def mine_duration(player_research) do
    if completed?(player_research, :mining), do: 3, else: 5
  end

  @doc "Pottery's unlock: whether the Granary building is available."
  @spec granary_enabled?(player_research()) :: boolean()
  def granary_enabled?(player_research), do: completed?(player_research, :pottery)

  @doc """
  Animal Husbandry's unlock: whether the Pasture improvement is
  available. Story 905 builds the Pasture itself (and its resource
  gating) on top of this flag; for now completing Animal Husbandry
  only ever flips it.
  """
  @spec pasture_enabled?(player_research()) :: boolean()
  def pasture_enabled?(player_research), do: completed?(player_research, :animal_husbandry)

  @doc """
  Bronze Working's unlock: the player's age. Derived entirely from
  `completed_techs` — there is no separate `age` field to keep in sync.
  Story 903 (Bronze units, the size-6 city cap) should read this
  instead of adding its own tracking.
  """
  @spec age(player_research()) :: age()
  def age(player_research) do
    if completed?(player_research, :bronze_working), do: :bronze_age, else: :stone_age
  end
end
