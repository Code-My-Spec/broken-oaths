defmodule BrokenOaths.Game.Siege do
  @moduledoc """
  Pure PvP city siege and capture core (story 906): who may lay siege,
  how a besieged city's HP breaks WITHOUT the barbarian-vs-city
  pillage-and-reset `BrokenOaths.Game.CityDefense.take_damage/3`
  already applies, when a broken city is actually captured, and the
  fallen garrison's fate once it is. No `Repo`, no process state —
  mirrors `CityDefense`'s own role: `BrokenOaths.Game.WorldServer`
  (the immediate "attack"/movement surfaces) and `BrokenOaths.Game.Turn`
  (the movement-collision exception below) are the imperative shells
  that read cities/units out of the canonical tick-state, call into
  this module, and write the result back.

  ## Who may besiege

  `validate_siege/3` layers ONE new rule on top of
  `CityDefense.validate_attack/3`'s existing movement/adjacency/
  not-your-own-city checks: the attacker must be a MILITARY unit
  (`CityDefense.military?/1`) — a civilian (a Settler) standing right
  next to a rival city cannot besiege it at all (`:not_military`),
  unlike today's barbarian-vs-city assault, which never checked the
  attacker's type.

  ## Breaking, not pillaging

  `take_damage/2` is `CityDefense.take_damage/3`'s player-siege sibling:
  the same floor-at-zero HP subtraction, but with NO `pillage/2` folded
  in. A city a PLAYER siege drives to 0 HP stays at exactly 0 — broken,
  not reset to 50 with a population loss — until it's actually captured
  (`materialize_captures/2`) or the siege is relieved by regen
  (`CityDefense.regen/1`, unchanged, still runs every quiet boundary).
  Barbarian assaults keep using `CityDefense.take_damage/3` unchanged —
  this module is only ever wired into the real-player "attack" surface.

  ## Status

  A city is `:free` (nobody else's, `CityDefense`'s own ordinary
  state), `:broken` (0 HP, not yet walked into), or `:occupied`
  (captured — `occupied_by_player_id` set). `status/1` and its
  boolean siblings (`free?/1`, `broken?/1`, `occupied?/1`) are the
  single source of truth every caller (the `city-status` badge, the
  last-free-city check) reads.

  ## Capture

  Zeroing a city's HP alone never captures it — "Civ-style. No
  range-flip — you commit and hold a body"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`). Capture is a
  MOVEMENT event: `materialize_captures/2` scans every city for one
  that's `broken?/1` with at least one OTHER player's unit now standing
  on its own tile (ties broken by lowest unit id, for determinism) and
  marks it occupied by that unit's own player. Idempotent and safe to
  call after every movement-producing change — a city already
  `occupied?/1` is skipped, so calling this twice in a row never
  double-reports the same capture. `enterable_despite_garrison?/2` is
  the sibling predicate `BrokenOaths.Game.Turn`'s own movement-collision
  check (`blocked?/6`) calls: once a city is broken, ANY other player's
  unit may step onto its tile even with the fallen (still-alive, not
  yet resolved) garrison still standing there — the walls are down, the
  garrison is defeated alongside them, but its own fate (survive or
  not) stays open until the conqueror chooses (`resolve_garrison_fate/3`).

  ## Last free city

  `no_free_cities?/2` is `BrokenOaths.Game.Vassalization`'s own trigger
  check: "'Free city' = a city you own that no other player occupies...
  Vassalization fires at ZERO free cities" (design doc, "Round-5
  decisions"). A player who has JUST been fully occupied (every city
  they own now `occupied?/1`) has zero free cities left.

  ## Garrison fate

  Once a city is captured with a living garrison still on its tile
  (`fallen_garrison/2`), the conqueror chooses: `:release` lets it
  survive untouched, `:execute` reports every one of its unit ids for
  the caller to remove from the board — "the conqueror chooses —
  execute the defenders or let them flee — and the choice carries a
  small Honor consequence" (design doc, "Round-4 final foundation
  mechanics": executing ≈ −2 Honor, releasing ≈ 0/neutral —
  `execute_garrison_honor_penalty/0`/`apply_execute_honor_penalty/1`,
  below).

  `fallen_garrison/2` is scoped to the DEFEATED city-owner's own units
  ONLY (`unit.player_id == city.player_id`), never the conqueror's —
  QA issue 94885d5e: filtering by tile alone (what
  `CityDefense.military_garrison/2` does) also matches the conqueror's
  own occupying unit, since it necessarily stands on the very same
  tile the instant a capture happens. "Execute" must never delete the
  conqueror's own army as a side effect of executing the people they
  just conquered.
  """

  alias BrokenOaths.Game.CityDefense

  @type tile_id :: CityDefense.tile_id()
  @type unit :: CityDefense.unit()
  @type city :: CityDefense.city()
  @type player_id :: term()
  @type refusal :: CityDefense.refusal() | :not_military
  @type garrison_fate :: :release | :execute

  @type capture_event :: %{
          city_id: term(),
          captor_player_id: player_id(),
          defeated_player_id: player_id()
        }

  # -------------------------------------------------------------------
  # Who may besiege
  # -------------------------------------------------------------------

  @doc """
  Whether `attacker` may legally besiege `city` right now: military
  only (`:not_military` otherwise), plus every `CityDefense.
  validate_attack/3` rule (movement, adjacency, not your own city).
  """
  @spec validate_siege(unit(), city(), [tile_id()]) :: :ok | {:error, refusal()}
  def validate_siege(attacker, city, adjacent_tile_ids) do
    if CityDefense.military?(attacker) do
      CityDefense.validate_attack(attacker, city, adjacent_tile_ids)
    else
      {:error, :not_military}
    end
  end

  # -------------------------------------------------------------------
  # Breaking, not pillaging
  # -------------------------------------------------------------------

  @doc "Apply `damage` to `city`'s HP, floored at 0 — unlike `CityDefense.take_damage/3`, never pillages."
  @spec take_damage(city(), non_neg_integer()) :: city()
  def take_damage(city, damage), do: %{city | hp: max(city.hp - damage, 0)}

  # -------------------------------------------------------------------
  # Status
  # -------------------------------------------------------------------

  @doc "Whether `city` is nobody's captive right now."
  @spec free?(city()) :: boolean()
  def free?(city), do: is_nil(Map.get(city, :occupied_by_player_id))

  @doc "Whether `city` is at 0 HP and not yet captured."
  @spec broken?(city()) :: boolean()
  def broken?(city), do: city.hp == 0 and free?(city)

  @doc "Whether `city` has been captured (occupied by someone other than its own owner)."
  @spec occupied?(city()) :: boolean()
  def occupied?(city), do: not free?(city)

  @doc "`:free`, `:broken`, or `:occupied` — the single status a `city-status` badge renders."
  @spec status(city()) :: :free | :broken | :occupied
  def status(city) do
    cond do
      occupied?(city) -> :occupied
      city.hp == 0 -> :broken
      true -> :free
    end
  end

  # -------------------------------------------------------------------
  # Capture
  # -------------------------------------------------------------------

  @doc """
  Whether `mover_player_id` may step onto `city`'s own tile despite
  living occupants already there — true only once `city` is broken AND
  the mover isn't its own owner (the owner's own regarrisoning march
  never needs this: `CityDefense.garrison_room?/2`'s existing
  own-city exception already covers that case).
  """
  @spec enterable_despite_garrison?(city(), player_id()) :: boolean()
  def enterable_despite_garrison?(city, mover_player_id),
    do: broken?(city) and city.player_id != mover_player_id

  @doc """
  Scans every city in `cities` for a first-time capture: broken, still
  free, with at least one OTHER player's unit standing on its own tile.
  Marks each such city occupied by that unit's own player (lowest unit
  id wins ties) and reports one `capture_event/0` per newly-captured
  city. Safe to call after every movement-producing change — a city
  already occupied is left untouched, so calling this again on an
  unchanged board reports no new events.
  """
  @spec materialize_captures(%{term() => city()}, %{term() => unit()}) ::
          {%{term() => city()}, [capture_event()]}
  def materialize_captures(cities, units) do
    unit_list = Map.values(units)

    {new_cities, events} =
      Enum.reduce(cities, {cities, []}, fn {id, city}, {acc_cities, acc_events} ->
        case captor(city, unit_list) do
          nil ->
            {acc_cities, acc_events}

          captor_player_id ->
            event = %{
              city_id: id,
              captor_player_id: captor_player_id,
              defeated_player_id: city.player_id
            }

            {Map.put(acc_cities, id, %{city | occupied_by_player_id: captor_player_id}),
             [event | acc_events]}
        end
      end)

    {new_cities, Enum.reverse(events)}
  end

  defp captor(city, units) do
    if broken?(city) do
      units
      |> Enum.filter(&(&1.tile_id == city.tile_id and &1.player_id != city.player_id))
      |> Enum.sort_by(& &1.id)
      |> case do
        [besieger | _] -> besieger.player_id
        [] -> nil
      end
    end
  end

  # -------------------------------------------------------------------
  # Last free city
  # -------------------------------------------------------------------

  @doc """
  Whether `player_id` has ZERO free cities among `cities` — the
  last-free-city trigger `BrokenOaths.Game.Vassalization` fires
  vassalization on. A player owning no cities at all also reads `true`
  (vacuously), but every real player always owns at least the city that
  just triggered this check.
  """
  @spec no_free_cities?([city()], player_id()) :: boolean()
  def no_free_cities?(cities, player_id) do
    cities
    |> Enum.filter(&(&1.player_id == player_id))
    |> Enum.all?(&occupied?/1)
  end

  # -------------------------------------------------------------------
  # Garrison fate
  # -------------------------------------------------------------------

  @doc """
  Every living military defender still standing on `city`'s own tile —
  the fallen garrison. NEVER includes the conqueror's own unit(s), even
  though they stand on the exact same tile the instant a capture
  happens — only units belonging to `city`'s own (defeated) owner
  (`city.player_id`, which never changes on capture — see
  `enterable_despite_garrison?/2`'s own doc) ever count (QA issue
  94885d5e).
  """
  @spec fallen_garrison(city(), [unit()]) :: [unit()]
  def fallen_garrison(city, units) do
    city
    |> CityDefense.military_garrison(units)
    |> Enum.filter(&(&1.hp > 0 and &1.player_id == city.player_id))
  end

  @doc """
  Resolve the conqueror's choice for `city`'s fallen garrison:
  `:release` reports nothing to remove (the garrison survives
  untouched), `:execute` reports every fallen garrison unit's own id
  for the caller to remove from the board.
  """
  @spec resolve_garrison_fate(garrison_fate(), city(), [unit()]) :: [term()]
  def resolve_garrison_fate(:release, _city, _units), do: []

  def resolve_garrison_fate(:execute, city, units),
    do: city |> fallen_garrison(units) |> Enum.map(& &1.id)

  # -------------------------------------------------------------------
  # Garrison-fate Honor consequence (story 906, QA issue ed1ff4c0)
  # -------------------------------------------------------------------

  @execute_garrison_honor_penalty 2

  @doc """
  How much Honor executing a fallen garrison costs (design doc,
  "Round-4 final foundation mechanics": "putting them to the sword
  costs Honor") — releasing is neutral, `0`, so it has no matching
  penalty function.
  """
  @spec execute_garrison_honor_penalty() :: pos_integer()
  def execute_garrison_honor_penalty, do: @execute_garrison_honor_penalty

  @doc "`honor - execute_garrison_honor_penalty/0` — the Honor consequence for choosing to execute a fallen garrison."
  @spec apply_execute_honor_penalty(integer()) :: integer()
  def apply_execute_honor_penalty(honor), do: honor - @execute_garrison_honor_penalty
end
