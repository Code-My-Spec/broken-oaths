defmodule BrokenOaths.Game.Spawner do
  @moduledoc """
  Spawn placement — pure selection of a new player's region and starting
  tiles. No `Repo` calls: the caller (a `Game` context function) turns the
  result into a `Player`, a Lord `Unit`, and a Settler `Unit`.

  Selection is deterministic given `world` and the set of already-claimed
  region ids, so two callers racing for the same world with the same
  snapshot of taken regions always agree.
  """

  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.World

  @type region_id :: non_neg_integer()
  @type tile_id :: non_neg_integer()

  @doc """
  Claim the first spawnable region not in `taken_region_ids`, then pick a
  spawn tile within it.

  The spawn tile (`lord_tile`) is the region's most central `:land` tile —
  the one with the greatest distance to the region boundary, ties broken
  by lowest tile id (`Regions.central_land_tiles/2`). `settler_tile` is
  the lowest-id adjacent `:land` tile, distinct from `lord_tile` (one unit
  per hex is a hard rule). If a candidate spawn tile has no adjacent land,
  the next-most-central candidate is tried.

  Returns `{:error, :world_full}` when every spawnable region is taken.
  """
  @spec spawn_player(World.t(), MapSet.t(region_id()) | [region_id()]) ::
          {:ok, %{region_id: region_id(), lord_tile: tile_id(), settler_tile: tile_id()}}
          | {:error, :world_full}
  def spawn_player(world, taken_region_ids) do
    taken = MapSet.new(taken_region_ids)

    world
    |> Regions.spawnable()
    |> Enum.reject(&MapSet.member?(taken, &1))
    |> place(world)
  end

  defp place([], _world), do: {:error, :world_full}

  defp place([region_id | rest], world) do
    world
    |> Regions.central_land_tiles(region_id)
    |> find_pair(world)
    |> case do
      nil ->
        place(rest, world)

      {lord_tile, settler_tile} ->
        {:ok, %{region_id: region_id, lord_tile: lord_tile, settler_tile: settler_tile}}
    end
  end

  defp find_pair(candidates, world) do
    Enum.find_value(candidates, fn lord_tile ->
      case adjacent_land(world, lord_tile) do
        [settler_tile | _] -> {lord_tile, settler_tile}
        [] -> nil
      end
    end)
  end

  defp adjacent_land(world, tile_id) do
    world
    |> Regions.adjacent_tiles(tile_id)
    |> Enum.filter(&(Regions.tile_class(world, &1) == :land))
    |> Enum.sort()
  end
end
