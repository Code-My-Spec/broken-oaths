defmodule BrokenOaths.Diplomacy.Discovery do
  @moduledoc """
  Pure first-contact detection (story 899): the moment a player's own
  CURRENT vision reveals another player's unit or city. No `Repo`, no
  process state — mirrors `BrokenOaths.Combat.CityDefense`'s role:
  `BrokenOaths.Game.WorldServer` is the imperative shell that holds the
  canonical tick-state (see `BrokenOaths.Game.Turn`'s moduledoc for that
  shape) plus the set of already-known player pairs, calls into this
  module at every turn boundary, and persists whatever comes back as
  `BrokenOaths.Diplomacy.KnownPlayer` rows.

  ## Detection

  A sighting is deliberately based on CURRENT vision
  (`BrokenOaths.Vision.Visibility.visible_tiles/2`), not the cumulative
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

  ## Tick orchestration + known-players read (pragdave decomposition, slice 5)

  `apply_discoveries/2` is the tick-time "logic out of the GenServer"
  home for `BrokenOaths.Game.WorldServer`'s own former private
  `apply_discoveries/2` — takes the pre-tick `state` and post-tick
  `ticked` state, folds every `new_contacts/2` pair into `ticked`'s own
  in-memory `known_players` `MapSet` (both directions, mirroring the
  mutual-contact rule above), and returns `{new_state,
  [{:discovery, user_id, message}, ...]}` for `WorldServer`'s own
  broadcast. This is the one function in this module that reads `Repo`
  (via `BrokenOaths.Users.get_user!/1`, building each side's own
  human-readable message) — `WorldServer` still owns the actual
  `Repo.transaction`/persist step (`persist_known_player_changes/3`
  diffs `state.known_players` the same way every other tick-state field
  is diffed), this module only decides WHAT changed and WHAT to say
  about it.

  `known_players/2` is the companion READ — `%{user_id:, email:}` for
  every player `user` has discovered, powering the client's own Known
  Players panel. Also moved home from `WorldServer`'s own private
  `known_players/2`.
  """

  alias BrokenOaths.Vision.Visibility
  alias BrokenOaths.Users

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
  `BrokenOaths.Diplomacy.KnownPlayer`).
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

  # -------------------------------------------------------------------
  # Tick orchestration — see this module's own "Tick orchestration +
  # known-players read" moduledoc section above.
  # -------------------------------------------------------------------

  @doc """
  Folds every fresh `new_contacts/2` pair (evaluated against `state`'s
  pre-tick `known_players`, over `ticked`'s post-tick unit/city
  positions) into `ticked`'s own `known_players` `MapSet` and returns
  `{new_state, events}` — one `{:discovery, user_id, message}` event per
  side of each newly-discovered pair.
  """
  @spec apply_discoveries(state(), state()) :: {state(), [{:discovery, term(), String.t()}]}
  def apply_discoveries(state, ticked) do
    known = Map.get(state, :known_players, MapSet.new())
    contacts = new_contacts(ticked, known)

    Enum.reduce(contacts, {ticked, []}, fn {a, b}, {acc_state, acc_events} ->
      updated_known =
        acc_state |> Map.get(:known_players, known) |> MapSet.put({a, b}) |> MapSet.put({b, a})

      new_acc_state = Map.put(acc_state, :known_players, updated_known)
      {new_acc_state, acc_events ++ discovery_events(acc_state, a, b)}
    end)
  end

  defp discovery_events(state, player_a_id, player_b_id) do
    user_a_id = Map.fetch!(state.players, player_a_id).user_id
    user_b_id = Map.fetch!(state.players, player_b_id).user_id
    email_a = Users.get_user!(user_a_id).email
    email_b = Users.get_user!(user_b_id).email

    [
      {:discovery, user_a_id, "You have discovered #{email_b}'s civilization!"},
      {:discovery, user_b_id, "#{email_a} has discovered your civilization!"}
    ]
  end

  # -------------------------------------------------------------------
  # Known-players read
  # -------------------------------------------------------------------

  @doc """
  `%{user_id:, email:}` for every player `user` has discovered — the
  `KnownPlayersPanel`'s own read. Ordered by `viewer_player_id`'s own
  directional `KnownPlayer` pairs in `state.known_players`, not
  fog-filtered current visibility (unrelated to current fog of war —
  see this module's own moduledoc).
  """
  @spec known_players(state(), map()) :: [%{user_id: term(), email: String.t()}]
  def known_players(state, user) do
    case find_player(state, user.id) do
      nil ->
        []

      player ->
        known = Map.get(state, :known_players, MapSet.new())

        for {viewer_id, discovered_id} <- known, viewer_id == player.id do
          discovered_player = Map.fetch!(state.players, discovered_id)
          discovered_user = Users.get_user!(discovered_player.user_id)
          %{user_id: discovered_user.id, email: discovered_user.email}
        end
    end
  end

  # -------------------------------------------------------------------
  # Shared, trivial lookup — duplicated rather than reaching back into
  # `WorldServer`, matching the sibling `BrokenOaths.Units.Unit`/
  # `BrokenOaths.Vision.Visibility`'s own "pure, process-unaware,
  # unit-testable with no GenServer running" contract (small private
  # helper copies rather than expanding public APIs).
  # -------------------------------------------------------------------

  defp find_player(state, user_id) do
    state.players |> Map.values() |> Enum.find(&(&1.user_id == user_id))
  end
end
