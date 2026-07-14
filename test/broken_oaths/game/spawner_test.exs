defmodule BrokenOaths.Game.SpawnerTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Game.Spawner
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.World

  # This seed/frequency pair has exactly two spawnable regions (0 and 1),
  # which makes the "next region" and "world full" paths cheap to exercise.
  @frequency 8
  @seed 424242

  defp world, do: %World{seed: @seed, frequency: @frequency}

  describe "spawn_player/2" do
    test "claims the first spawnable region not already taken" do
      assert {:ok, %{region_id: 0}} = Spawner.spawn_player(world(), [])
    end

    test "skips regions already taken" do
      assert {:ok, %{region_id: 1}} = Spawner.spawn_player(world(), [0])
    end

    test "returns :world_full once every spawnable region is taken" do
      taken = Regions.spawnable(world())
      assert taken != []
      assert {:error, :world_full} = Spawner.spawn_player(world(), taken)
    end

    test "accepts a MapSet or a list interchangeably" do
      assert Spawner.spawn_player(world(), [0]) == Spawner.spawn_player(world(), MapSet.new([0]))
    end

    test "lord_tile and settler_tile are land, distinct, and mesh-adjacent" do
      {:ok, %{lord_tile: lord_tile, settler_tile: settler_tile}} = Spawner.spawn_player(world(), [])

      assert Regions.tile_class(world(), lord_tile) == :land
      assert Regions.tile_class(world(), settler_tile) == :land
      refute lord_tile == settler_tile
      assert settler_tile in Regions.adjacent_tiles(world(), lord_tile)
    end

    test "both spawn tiles belong to the claimed region" do
      {:ok, %{region_id: region_id, lord_tile: lord_tile, settler_tile: settler_tile}} =
        Spawner.spawn_player(world(), [])

      region_tiles = world() |> Regions.partition() |> Map.fetch!(:regions) |> Map.fetch!(region_id)

      assert lord_tile in region_tiles
      assert settler_tile in region_tiles
    end

    test "is deterministic for a given world and taken set" do
      assert Spawner.spawn_player(world(), [0]) == Spawner.spawn_player(world(), [0])
    end

    test "sequential spawns land in distinct regions" do
      {:ok, first} = Spawner.spawn_player(world(), [])
      {:ok, second} = Spawner.spawn_player(world(), [first.region_id])

      refute first.region_id == second.region_id
    end
  end
end
