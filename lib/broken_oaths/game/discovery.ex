defmodule BrokenOaths.Game.Discovery do
  @moduledoc """
  Pure first-contact detection (story 899): the moment a player's own
  CURRENT vision reveals another player's unit or city. No `Repo`, no
  process state — mirrors `BrokenOaths.Game.CityDefense`'s role:
  `BrokenOaths.Game.WorldServer` is the imperative shell that holds the
  canonical tick-state (see `BrokenOaths.Game.Turn`'s moduledoc for that
  shape) plus the set of already-known player pairs, calls into this
  module at every turn boundary, and persists whatever comes back as
  `BrokenOaths.Game.KnownPlayer` rows.

  ## Detection

  A sighting is deliberately based on CURRENT vision
  (`BrokenOaths.Game.Visibility.visible_tiles/2`), not the cumulative
  explored history fog-of-war otherwise tracks — first contact is about
  a LIVE sighting the instant it happens, not a tile remembered from
  the past. Barbarians (`player_id: nil`) are never a "viewer" (the
  canonical tick-state's own `players` map only ever holds real
  players) or a "discovered" party — there is no civilization behind an
  ownerless unit to discover.

  ## Mutual, canonical contact

  Sighting itself is one-directional (only the VIEWER's own vision is
  checked), but discovery is mutual: `new_contacts/2` folds both
  directions of a pair into a single canonical `{lowest_id, highest_id}`
  tuple, so a pair already known in EITHER direction is skipped, and a
  tick where both players happen to sight each other at once still
  reports that pair exactly once — never twice for the same first
  contact.
  """

  alias BrokenOaths.Game.Visibility

  @type player_id :: term()
  @type state :: %{
          optional(atom()) => term(),
          world: BrokenOaths.Worlds.World.t(),
          units: %{term() => map()},
          players: %{player_id() => map()}
        }

  @doc """
  Every NEW first-contact pair as of `state`'s current unit/city
  positions: `{player_a_id, player_b_id}`, canonical (lowest id first),
  one entry per pair of players not already present (in either
  direction) in `known` — the set of directional `{viewer_player_id,
  discovered_player_id}` pairs already recorded (see
  `BrokenOaths.Game.KnownPlayer`).
  """
  @spec new_contacts(state(), MapSet.t({player_id(), player_id()})) :: [
          {player_id(), player_id()}
        ]
  def new_contacts(state, known) do
    state
    |> new_sightings(known)
    |> Enum.map(&canonicalize/1)
    |> Enum.uniq()
  end

  # One-directional sightings: `viewer_id`'s OWN current vision reveals
  # a unit or city belonging to `discovered_id`, and neither direction
  # of that pair is already known.
  defp new_sightings(state, known) do
    for viewer_id <- Map.keys(state.players),
        discovered_id <- sighted_player_ids(state, viewer_id),
        discovered_id != viewer_id,
        not MapSet.member?(known, {viewer_id, discovered_id}),
        not MapSet.member?(known, {discovered_id, viewer_id}) do
      {viewer_id, discovered_id}
    end
  end

  defp sighted_player_ids(state, viewer_id) do
    visible = viewer_vision(state, viewer_id)

    unit_owners =
      for {_id, unit} <- state.units,
          not is_nil(unit.player_id),
          unit.player_id != viewer_id,
          MapSet.member?(visible, unit.tile_id),
          do: unit.player_id

    city_owners =
      for {_id, city} <- Map.get(state, :cities, %{}),
          city.player_id != viewer_id,
          MapSet.member?(visible, city.tile_id),
          do: city.player_id

    Enum.uniq(unit_owners ++ city_owners)
  end

  defp viewer_vision(state, viewer_id) do
    own_units = for {_id, unit} <- state.units, unit.player_id == viewer_id, do: unit
    Visibility.visible_tiles(state.world, own_units)
  end

  defp canonicalize({a, b}) when a <= b, do: {a, b}
  defp canonicalize({a, b}), do: {b, a}
end
