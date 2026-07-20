defmodule BrokenOaths.Technology.Research do
  @moduledoc """
  Pure tech-tree core (story 902, EXPANDED per playtest issue 133b4893
  "basically copy Civ 6 ... beef up the tech tree"): the eleven
  Civ-6-accurate Ancient-era techs and their prerequisite edges,
  science cost, converting a player's cities into science income,
  banking that income toward whichever tech is currently selected, and
  completing a tech once its cost is banked. No `Repo`: every function
  here takes and returns a plain `player_research()` map — the same
  "pure functional core, `WorldServer` is the imperative shell" split
  `BrokenOaths.Cities.Production`/`BrokenOaths.Cities.Yields` already use.
  `BrokenOaths.Technology.PlayerResearch` is the Ecto-backed persistence
  shape this module's maps round-trip through.

  ## Science generation

  Every city generates `2 * size` science per turn (`science_per_turn/1`)
  — population is the only science lever in this MVP (see
  `.code_my_spec/knowledge/civ6_tech_tree.md`), so `size` (a city's
  population, same field `BrokenOaths.Cities.Yields.threshold/1` grows
  against) stands in for Civ's Palace + Campus + Library stack.

  ## One tech at a time, banked per tech

  `current_research` names at most one tech; `banked_science` tracks
  progress for EVERY tech independently, so switching
  `current_research` (`set_research/2`) never discards progress on the
  tech switched away from — resuming it later picks up exactly where
  it left off. A tech already in `completed_techs` can never be
  (re-)selected.

  ## The tech tree: eleven Ancient-era techs, with prerequisites

  Five techs have NO prerequisite (tier 1): Pottery (50), Animal
  Husbandry (50), Mining (75), Sailing (90), Astrology (90). Six more
  each require exactly one tier-1 tech first: Writing (90) and
  Irrigation (90) need Pottery; Archery (90) needs Animal Husbandry;
  Masonry (100), The Wheel (100), and Bronze Working (100) need
  Mining. These edges mirror Civ 6's own Ancient-era shape (see
  `.code_my_spec/knowledge/civ6_tech_tree.md`) — reaching the Bronze
  Age now requires researching Mining BEFORE Bronze Working, where
  previously Bronze Working had no prerequisite at all.

  `set_research/2` REFUSES to select a tech whose prerequisites
  aren't all in `completed_techs` yet (`{:error, :prereqs_not_met}`),
  exactly the same defensive-refusal shape it already uses for an
  unknown tech or one already completed. `prereqs_met?/2` is the
  underlying check; `tech_state/2` classifies a tech into exactly one
  of `:locked | :available | :in_progress | :completed` for a
  `TechPanel` (or any other surface) to render without duplicating
  that classification logic — this directly answers the "prerequisites
  aren't obvious" complaint issue 133b4893 raised: a locked tech's row
  is now unambiguous, and its own `prereqs/1` names exactly which
  tech(s) it is waiting on.

  ## Unlocks

  Completing a tech (`complete/1`) only ever moves it from
  `current_research` into `completed_techs` — every unlock's actual
  EFFECT is read back out of `completed_techs` on demand
  (`mine_duration/1`, `granary_enabled?/1`, `pasture_enabled?/1`,
  `age/1`), so there is exactly one source of truth for "has this
  player unlocked X" and no separate flag can ever drift out of sync
  with it.

  Four techs have a real, wired unlock today: Pottery (Granary),
  Animal Husbandry (Pasture), Mining (faster mines), and Bronze
  Working (the Bronze Age itself, plus Bronze units and — story 911 —
  revealing the Copper strategic resource). The other seven
  (Sailing, Astrology, Writing, Irrigation, Archery, Masonry, The
  Wheel) are STRUCTURE-ONLY for this story: they research, bank
  science, complete, and gate their own dependents exactly like every
  other tech, but the content they name (Galleys, the Holy Site,
  Library, Plantation, Archer, Walls/Quarry, roads/Heavy Chariot)
  doesn't exist in this codebase yet and ships in later stories. The
  Wheel in particular is the intended future gate for the deferred
  Road worker-improvement (story 882) — it is NOT wired to anything
  yet, on purpose.
  """

  @type tech ::
          :pottery
          | :animal_husbandry
          | :mining
          | :sailing
          | :astrology
          | :writing
          | :irrigation
          | :archery
          | :masonry
          | :the_wheel
          | :bronze_working

  @type age :: :stone_age | :bronze_age
  @type tech_state :: :locked | :available | :in_progress | :completed

  @type player_research :: %{
          completed_techs: [tech()],
          current_research: tech() | nil,
          banked_science: %{tech() => non_neg_integer()}
        }

  @type city :: %{required(:size) => pos_integer(), optional(atom()) => term()}

  @type set_research_error :: :invalid_tech | :already_completed | :prereqs_not_met

  @science_per_pop 2

  @catalog %{
    # Tier 1 — no prerequisite.
    pottery: %{
      cost: 50,
      prereqs: [],
      unlock: "Enables the Granary building (+2 food storage)"
    },
    animal_husbandry: %{
      cost: 50,
      prereqs: [],
      unlock: "Enables the Pasture improvement (+2 food on animal resources)"
    },
    mining: %{cost: 75, prereqs: [], unlock: "Workers build mines in 3 turns instead of 5"},
    sailing: %{cost: 90, prereqs: [], unlock: "Enables Galleys and coastal exploration"},
    astrology: %{cost: 90, prereqs: [], unlock: "Enables the Holy Site district"},
    # After Pottery.
    writing: %{cost: 90, prereqs: [:pottery], unlock: "Enables the Library building"},
    irrigation: %{cost: 90, prereqs: [:pottery], unlock: "Enables farming irrigated resources"},
    # After Animal Husbandry.
    archery: %{cost: 90, prereqs: [:animal_husbandry], unlock: "Enables the Archer unit"},
    # After Mining.
    masonry: %{
      cost: 100,
      prereqs: [:mining],
      unlock: "Enables Walls and the Quarry improvement"
    },
    the_wheel: %{cost: 100, prereqs: [:mining], unlock: "Enables roads and the Heavy Chariot"},
    bronze_working: %{
      cost: 100,
      prereqs: [:mining],
      unlock: "Advances your civilization to the Bronze Age"
    }
  }

  @techs Map.keys(@catalog)

  # -------------------------------------------------------------------
  # Catalog
  # -------------------------------------------------------------------

  @doc """
  Every Ancient-era tech, in a fixed presentation order: the five
  prereq-free tier-1 techs first (Pottery, Animal Husbandry, Mining,
  Sailing, Astrology), then each tier-2 tech grouped after the
  prerequisite it depends on (Writing/Irrigation after Pottery,
  Archery after Animal Husbandry, Masonry/The Wheel/Bronze Working
  after Mining) — what a `TechPanel` lists, top to bottom.
  """
  @spec techs() :: [tech()]
  def techs do
    [
      :pottery,
      :animal_husbandry,
      :mining,
      :sailing,
      :astrology,
      :writing,
      :irrigation,
      :archery,
      :masonry,
      :the_wheel,
      :bronze_working
    ]
  end

  @doc "The full tech catalog: `%{tech => %{cost:, unlock:, prereqs:}}` — what a TechPanel lists."
  @spec catalog() :: %{tech() => %{cost: pos_integer(), unlock: String.t(), prereqs: [tech()]}}
  def catalog, do: @catalog

  @doc "A tech's science cost."
  @spec cost(tech()) :: pos_integer()
  def cost(tech), do: fetch_tech!(tech).cost

  @doc "A tech's unlock, in prose — what a TechPanel shows as \"why research this\"."
  @spec unlock_description(tech()) :: String.t()
  def unlock_description(tech), do: fetch_tech!(tech).unlock

  @doc """
  `tech`'s prerequisite techs — empty for every tier-1 tech, exactly
  one entry for every tier-2 tech in this tree (`set_research/2`
  requires ALL of them to be completed, but no tech here currently has
  more than one). What a `TechPanel` row names as "Requires: ...".
  """
  @spec prereqs(tech()) :: [tech()]
  def prereqs(tech), do: fetch_tech!(tech).prereqs

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
  # Prerequisites
  # -------------------------------------------------------------------

  @doc """
  Whether every one of `tech`'s prerequisites is already in
  `completed_techs` (vacuously true for a tier-1 tech, whose `prereqs/1`
  is `[]`). This is independent of whether `tech` ITSELF has already
  been completed or is already selected — `set_research/2` and
  `tech_state/2` each layer their own additional checks on top.
  """
  @spec prereqs_met?(player_research(), tech()) :: boolean()
  def prereqs_met?(player_research, tech) do
    tech |> prereqs() |> Enum.all?(&completed?(player_research, &1))
  end

  @doc """
  `tech`'s current state for a `TechPanel` (or any other surface) to
  render, in exactly one of four buckets — the classification issue
  133b4893 asked for so a locked tech is never ambiguous:

    * `:completed` — already in `completed_techs`.
    * `:in_progress` — not completed, and IS `current_research`.
    * `:available` — not completed, not current, but every prerequisite
      is done (`prereqs_met?/2`) — researchable right now.
    * `:locked` — not completed, not current, and at least one
      prerequisite is still outstanding — `set_research/2` would
      refuse it with `{:error, :prereqs_not_met}`.
  """
  @spec tech_state(player_research(), tech()) :: tech_state()
  def tech_state(player_research, tech) do
    cond do
      completed?(player_research, tech) -> :completed
      player_research.current_research == tech -> :in_progress
      prereqs_met?(player_research, tech) -> :available
      true -> :locked
    end
  end

  # -------------------------------------------------------------------
  # Selecting research
  # -------------------------------------------------------------------

  @doc """
  Select `tech` as `current_research`, retaining whatever science was
  already banked for it (and for every other tech). Refuses an unknown
  tech, one already completed, or — new for the expanded tree — one
  whose prerequisites aren't all completed yet
  (`{:error, :prereqs_not_met}`, checked via `prereqs_met?/2`).
  """
  @spec set_research(player_research(), tech()) ::
          {:ok, player_research()} | {:error, set_research_error()}
  def set_research(player_research, tech) do
    cond do
      tech not in @techs ->
        {:error, :invalid_tech}

      tech in player_research.completed_techs ->
        {:error, :already_completed}

      not prereqs_met?(player_research, tech) ->
        {:error, :prereqs_not_met}

      true ->
        {:ok, %{player_research | current_research: tech}}
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
  banked anywhere (mirrors `BrokenOaths.Cities.Production.accrue/3`'s
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
  `BrokenOaths.Simulation.Turn`'s own tick phases return (an optional event
  alongside the new state), ready to drive a `{:tech_completed, ...}`
  event the same way `{:unit_spawned, ...}` is built from
  `BrokenOaths.Cities.Production.complete/3`.
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

  # -------------------------------------------------------------------
  # Tick-loop science accrual (story 902 — moved from `BrokenOaths.Game.
  # Turn`'s own private `accrue_science/1`/`accrue_one_player/4`, the
  # tick-decomposition pass, see
  # `.code_my_spec/knowledge/genserver_decomposition.md`)
  # -------------------------------------------------------------------

  @doc """
  Every player banks `science_per_turn/1` (their OWN cities' `2 * size`)
  toward their `current_research`, auto-completing it via
  `accrue_and_complete/2` the instant it reaches cost. A player missing
  from `state.player_research` (most hand-built tick-state test maps,
  and any player row created before this state key existed) is treated
  as `new/0` for this tick only — a player with `current_research: nil`
  simply banks nothing, same no-op `accrue/2` documents. `state` is the
  canonical tick-state described in `BrokenOaths.Simulation.Turn`.

  Returns `{new_state, tech_completed_events}`.
  """
  @spec accrue_science(map()) :: {map(), [tuple()]}
  def accrue_science(state) do
    player_research = Map.get(state, :player_research, %{})
    cities_by_player = Enum.group_by(Map.values(state.cities), & &1.player_id)

    {new_player_research, events} =
      Enum.reduce(state.players, {player_research, []}, fn {player_id, _player}, {acc, events} ->
        accrue_one_player(state, player_id, cities_by_player, acc, events)
      end)

    {Map.put(state, :player_research, new_player_research), Enum.reverse(events)}
  end

  defp accrue_one_player(state, player_id, cities_by_player, acc, events) do
    pr = Map.get(acc, player_id, new())
    income = science_per_turn(Map.get(cities_by_player, player_id, []))
    {new_pr, completed_tech} = accrue_and_complete(pr, income)
    acc = Map.put(acc, player_id, new_pr)

    case completed_tech do
      nil ->
        {acc, events}

      tech ->
        user_id = Map.fetch!(state.players, player_id).user_id
        {acc, [{:tech_completed, user_id, tech} | events]}
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
  Archery's unlock (QA issue da39e50b "No archer"): whether the Archer
  unit is buildable. `Production.can_queue?/3`'s `:archer` clause reads
  this the same "Production never touches Research" way
  `granary_enabled?/1`/`pasture_enabled?/1` are already read — the
  caller (`WorldServer`) resolves the flag and passes it in as
  `opts[:archery?]`.
  """
  @spec archery_enabled?(player_research()) :: boolean()
  def archery_enabled?(player_research), do: completed?(player_research, :archery)

  @doc """
  Bronze Working's unlock: the player's age. Derived entirely from
  `completed_techs` — there is no separate `age` field to keep in sync.
  Reaching Bronze Working now requires Mining first (`prereqs/1`), so
  the Bronze Age is only ever one step further than it used to be.
  """
  @spec age(player_research()) :: age()
  def age(player_research) do
    if completed?(player_research, :bronze_working), do: :bronze_age, else: :stone_age
  end

  @doc """
  Bronze Working's OTHER unlock (story 911): whether Copper, the map's
  first strategic resource, is revealed to this player yet. Mirrors
  Civ 6's own convention (Bronze Working reveals Iron there) — the
  same tech that flips `age/1` to `:bronze_age` also lifts Copper's
  fog. `BrokenOaths.Worlds.Resources.at/2` itself places Copper on the
  map unconditionally (it has no concept of a viewing player); THIS is
  the read `BrokenOathsWeb.GameLive.Play` gates a pushed
  `"game:resources"`/`select_tile` read on before a player ever learns
  a tile carries Copper. Never gates `BrokenOaths.Cities.Production`'s
  own `copper_access?` check — a city's ACCESS to Copper (needed to
  train a Bronze Spearman) is a territory fact, independent of whether
  the player has yet unlocked the tech that makes Copper VISIBLE on
  the map; in practice a Bronze Spearman is only ever offered once
  Bronze Working is already done (`age/1 == :bronze_age`), so by the
  time access matters, Copper is already revealed anyway.
  """
  @spec copper_revealed?(player_research()) :: boolean()
  def copper_revealed?(player_research), do: completed?(player_research, :bronze_working)
end
