defmodule BrokenOaths.Vision.Visibility do
  @moduledoc """
  Pure fog-of-war math — vision radii per unit type, BFS visibility, and
  the per-player fog filter that keeps hidden state off the wire.

  Three states exist for a tile, from a given player's point of view:

    * visible  — currently within vision range of one of their units
    * explored — seen at some point in the past, terrain remembered but
      not live (no unit or enemy positions)
    * unknown  — never seen; absent from both sets

  `filter/2` is the leak barrier: it is the only place that decides what a
  player's client is allowed to know, so every other-player fact (unit
  positions, in particular) must be gated through it rather than sent raw.

  ## Visible-set reads (pragdave decomposition, slice 5)

  `player_units/2`, `visible_units/2`, `visibility/2`, `visible_camps/2`,
  `list_camps/1`, `visible_enemy_cities/2`, and `captured_cities/2` are
  the fog-filtered board reads moved home from `BrokenOaths.Game.
  WorldServer`'s own private `do_*`/formatting functions (see
  `.code_my_spec/knowledge/genserver_decomposition.md`) — every one of
  them takes the WorldServer's own tick-`state` plus plain args and
  returns a plain, wire-ready value; no `GenServer`, no process
  awareness. `WorldServer`'s own `handle_call` clauses for
  `:player_units`/`:units_visible_to`/`:visibility`/`:list_camps`/
  `:camps_visible_to`/`:enemy_cities_visible_to`/
  `:captured_cities_visible_to` are thin delegations into this module.
  """

  alias BrokenOaths.Game
  alias BrokenOaths.Combat.Resolver
  alias BrokenOaths.Combat.Siege
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.World

  @type tile_id :: non_neg_integer()
  @type unit_type :: :lord | :settler | atom()
  @type unit :: %{
          required(:type) => unit_type,
          required(:tile_id) => tile_id,
          optional(atom()) => term()
        }

  @default_vision_radius 2

  @doc "Vision radius, in tiles, for a unit type. The Lord out-scouts everything else."
  @spec vision_radius(unit_type()) :: pos_integer()
  def vision_radius(:lord), do: 3
  def vision_radius(:settler), do: 2
  def vision_radius(_other), do: @default_vision_radius

  @doc """
  Union of the BFS vision ball (mesh adjacency, `radius` hops, inclusive of
  the unit's own tile) around every given unit.
  """
  @spec visible_tiles(World.t(), [unit()]) :: MapSet.t(tile_id())
  def visible_tiles(world, units) do
    Enum.reduce(units, MapSet.new(), fn unit, acc ->
      MapSet.union(acc, vision_ball(world, unit.tile_id, vision_radius(unit.type)))
    end)
  end

  # -------------------------------------------------------------------
  # Tick-loop exploration (moved from `BrokenOaths.Simulation.Turn`'s own
  # private `refresh_explored/1`, the tick-decomposition pass, see
  # `.code_my_spec/knowledge/genserver_decomposition.md`)
  # -------------------------------------------------------------------

  @doc """
  Grow every player's own `state.explored` set by whatever their units
  can see this tick (`visible_tiles/2`), unioned onto whatever they'd
  already explored before — explored tiles are permanent, never
  forgotten. `state` is the canonical tick-state described in
  `BrokenOaths.Simulation.Turn`.
  """
  @spec refresh_explored(map()) :: map()
  def refresh_explored(state) do
    explored =
      Map.new(state.players, fn {player_id, _player} ->
        units = for {_id, unit} <- state.units, unit.player_id == player_id, do: unit
        newly_visible = visible_tiles(state.world, units)
        prior = Map.get(state.explored, player_id, MapSet.new())
        {player_id, MapSet.union(prior, newly_visible)}
      end)

    %{state | explored: explored}
  end

  @doc """
  The per-player fog filter.

  `state` is the canonical tick-state described in `BrokenOaths.Simulation.Turn`.
  Returns only what `player_id` is allowed to see: their own explored
  history, their current visibility, their own units always, and other
  players' units only while standing on a tile that is currently visible
  to them.
  """
  @spec filter(map(), term()) :: %{visible: [tile_id()], explored: [tile_id()], units: [map()]}
  def filter(state, player_id) do
    own_units = for {_id, unit} <- state.units, unit.player_id == player_id, do: unit
    visible = visible_tiles(state.world, own_units)
    explored = state.explored |> Map.get(player_id, MapSet.new()) |> MapSet.to_list()

    units =
      for {_id, unit} <- state.units,
          unit.player_id == player_id or MapSet.member?(visible, unit.tile_id),
          do: unit

    %{visible: MapSet.to_list(visible), explored: explored, units: units}
  end

  # BFS ball of tiles within `radius` hops of `start` (inclusive).
  defp vision_ball(world, start, radius) do
    grow_ball(world, MapSet.new([start]), [start], radius)
  end

  defp grow_ball(_world, visited, _frontier, 0), do: visited

  defp grow_ball(world, visited, frontier, radius) do
    next =
      frontier
      |> Enum.flat_map(&Regions.adjacent_tiles(world, &1))
      |> Enum.reject(&MapSet.member?(visited, &1))
      |> Enum.uniq()

    grow_ball(world, MapSet.union(visited, MapSet.new(next)), next, radius - 1)
  end

  # -------------------------------------------------------------------
  # Unit reads
  # -------------------------------------------------------------------

  @doc "Every unit `user` owns, formatted for the wire (own orders included)."
  @spec player_units(map(), map()) :: [map()]
  def player_units(state, user) do
    case find_player(state, user.id) do
      nil ->
        []

      player ->
        for {_id, unit} <- state.units,
            unit.player_id == player.id,
            do: format_unit(state, unit, player.id)
    end
  end

  @doc "Every unit currently within `user`'s own fog-of-war visibility, formatted for the wire."
  @spec visible_units(map(), map()) :: [map()]
  def visible_units(state, user) do
    case find_player(state, user.id) do
      nil ->
        []

      player ->
        %{units: units} = filter(state, player.id)
        for unit <- units, do: format_unit(state, unit, player.id)
    end
  end

  @doc "`user`'s own `visible`/`explored` tile sets — the `filter/2` payload trimmed for the client."
  @spec visibility(map(), map()) :: %{visible: [tile_id()], explored: [tile_id()]}
  def visibility(state, user) do
    case find_player(state, user.id) do
      nil -> %{visible: [], explored: []}
      player -> state |> filter(player.id) |> Map.take([:visible, :explored])
    end
  end

  # Orders are private intent — only a unit's own player ever sees it.
  defp format_unit(state, unit, viewer_player_id) do
    order =
      if unit.player_id == viewer_player_id do
        format_order(Map.get(state.orders, unit.id))
      end

    %{
      id: unit.id,
      type: unit.type,
      tile_id: unit.tile_id,
      hp: unit.hp,
      max_hp: unit.max_hp,
      movement: unit.movement,
      max_movement: unit.max_movement,
      charges: Map.get(unit, :charges, 3),
      # Story 915 — see `BrokenOathsSpex.Story915.Criterion7734Spex`'s
      # own "flagged temporary" read: the sanctioned board-state bridge
      # (`Fixtures.player_units/2`) needs this on every unit map, not
      # just the owner's own view, since a temporary rebellion unit's
      # own flag is public knowledge (it's on the board).
      temporary: Map.get(unit, :temporary, false),
      order: order
    }
  end

  defp format_order(nil), do: nil

  # The remaining path travels with the order (owner-only, see above) so
  # the board can render the route from the unit to its destination and
  # keep it current as movement consumes steps (story 875 rule).
  defp format_order(%{path: path, status: status}),
    do: %{target_tile: List.last(path), status: status, path: path}

  # -------------------------------------------------------------------
  # Camp reads
  # -------------------------------------------------------------------

  @doc "Every camp in the world, formatted for the wire — unfiltered (used by admin/debug reads)."
  @spec list_camps(map()) :: [map()]
  def list_camps(state), do: Enum.map(Map.values(state.camps), &format_camp(&1, state))

  @doc "Every non-destroyed camp currently within `user`'s own region or explored history."
  @spec visible_camps(map(), map()) :: [map()]
  def visible_camps(state, user) do
    case find_player(state, user.id) do
      nil ->
        []

      player ->
        home = player_region_tiles(state.world, player.region_id)
        explored = Map.get(state.explored, player.id, MapSet.new())

        state.camps
        |> Map.values()
        |> Enum.reject(&(!is_nil(&1.destroyed_at)))
        |> Enum.filter(
          &(MapSet.member?(home, &1.tile_id) or MapSet.member?(explored, &1.tile_id))
        )
        |> Enum.map(&format_camp(&1, state))
    end
  end

  # `warriors` nests the camp's own spawned units (matched by
  # `camp_id`, never by tile — a second warrior can land on an
  # adjacent tile, not the camp's own) — attack/defense both read off
  # `Resolver.base_strength/1` rather than a second hardcoded 15, so the
  # combat curve and this display can never drift apart.
  defp format_camp(camp, state) do
    strength = Resolver.base_strength(:barbarian_warrior)

    warriors =
      for {_id, unit} <- state.units, Map.get(unit, :camp_id) == camp.id do
        %{id: unit.id, tile_id: unit.tile_id, hp: unit.hp, attack: strength, defense: strength}
      end

    %{id: camp.id, tile_id: camp.tile_id, hp: camp.hp, warriors: warriors}
  end

  # -------------------------------------------------------------------
  # City reads
  # -------------------------------------------------------------------

  # QA issue 56ee521a: fog-filtered ENEMY (another player's own) cities
  # — the same "own region OR explored" rule `visible_camps/2` already
  # uses, minus every city already occupied by the VIEWER themselves
  # (their own captured holding isn't a fresh attack target — see
  # `captured_cities/2`'s own doc below). Empty unless
  # `Game.feudal_enabled?/0` — belt-and-suspenders alongside
  # `Siege.attack_city/4`'s own gate, matching `Vassalization.
  # apply_captures/1`'s own posture.
  @doc "Fog-filtered enemy cities `user` can see, gated on `Game.feudal_enabled?/0`."
  @spec visible_enemy_cities(map(), map()) :: [map()]
  def visible_enemy_cities(state, user) do
    if Game.feudal_enabled?(), do: do_visible_enemy_cities(state, user), else: []
  end

  defp do_visible_enemy_cities(state, user) do
    case find_player(state, user.id) do
      nil ->
        []

      player ->
        home = player_region_tiles(state.world, player.region_id)
        explored = Map.get(state.explored, player.id, MapSet.new())

        state.cities
        |> Map.values()
        |> Enum.filter(&enemy_city_visible?(&1, player, home, explored))
        |> Enum.map(&enemy_city_summary/1)
    end
  end

  # QA issue 7f91cff2 — `broken` (computed off the FULL city, which
  # still carries `occupied_by_player_id`, before `Map.take/2` drops it)
  # is what `GameLive.Play`'s `.Board` hook needs to route a right-click
  # (or the UnitPanel button) to `queue_move`/occupy instead of another
  # `attack` once the city is at 0 HP — `Siege.broken?/1` is the single
  # source of truth every other broken-city check already reads.
  defp enemy_city_summary(city) do
    city
    |> Map.take([:id, :name, :tile_id, :size, :hp])
    |> Map.put(:broken, Siege.broken?(city))
  end

  defp enemy_city_visible?(city, player, home, explored) do
    city.player_id != player.id and city.occupied_by_player_id != player.id and
      (MapSet.member?(home, city.tile_id) or MapSet.member?(explored, city.tile_id))
  end

  # QA issue ffa66192: cities the VIEWER has personally captured
  # (`occupied_by_player_id == their own player id`), each carrying
  # `fallen_garrison?` — whether `Siege.fallen_garrison/2` still finds a
  # living defender awaiting the execute/release choice. Empty unless
  # `Game.feudal_enabled?/0`, same belt-and-suspenders status as
  # `visible_enemy_cities/2` above.
  @doc "Cities `user` has personally captured, gated on `Game.feudal_enabled?/0`."
  @spec captured_cities(map(), map()) :: [map()]
  def captured_cities(state, user) do
    if Game.feudal_enabled?() do
      case find_player(state, user.id) do
        nil ->
          []

        player ->
          state.cities
          |> Map.values()
          |> Enum.filter(&(&1.occupied_by_player_id == player.id))
          |> Enum.map(&format_captured_city(state, &1))
      end
    else
      []
    end
  end

  defp format_captured_city(state, city) do
    fallen_garrison? = city |> Siege.fallen_garrison(Map.values(state.units)) |> Enum.any?()
    %{id: city.id, name: city.name, tile_id: city.tile_id, fallen_garrison?: fallen_garrison?}
  end

  defp player_region_tiles(world, region_id) do
    world |> Regions.partition() |> Map.fetch!(:regions) |> Map.fetch!(region_id) |> MapSet.new()
  end

  # -------------------------------------------------------------------
  # Shared, trivial lookup — duplicated rather than reaching back into
  # `WorldServer`, matching the sibling `BrokenOaths.Units.Unit`/
  # `BrokenOaths.Cities.City`'s own "pure, process-unaware, unit-testable
  # with no GenServer running" contract (small private helper copies
  # rather than expanding public APIs).
  # -------------------------------------------------------------------

  defp find_player(state, user_id) do
    state.players |> Map.values() |> Enum.find(&(&1.user_id == user_id))
  end
end
