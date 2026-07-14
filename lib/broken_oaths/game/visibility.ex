defmodule BrokenOaths.Game.Visibility do
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
  """

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

  @doc """
  The per-player fog filter.

  `state` is the canonical tick-state described in `BrokenOaths.Game.Turn`.
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
end
