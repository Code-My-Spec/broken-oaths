defmodule BrokenOaths.Vision.VisibilityTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Vision.Visibility
  alias BrokenOaths.Worlds.Globe
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.World

  @frequency 8
  @seed 424_242

  defp world, do: %World{seed: @seed, frequency: @frequency}

  describe "vision_radius/1" do
    test "the lord sees farther than a settler" do
      assert Visibility.vision_radius(:lord) == 3
      assert Visibility.vision_radius(:settler) == 2
    end

    test "an unrecognized unit type falls back to the default radius" do
      assert Visibility.vision_radius(:catapult) == 2
    end
  end

  describe "visible_tiles/2" do
    test "is the BFS ball at the unit's vision radius, inclusive of its own tile" do
      w = world()
      assert Visibility.visible_tiles(w, [%{type: :lord, tile_id: 0}]) == ring(w, 0, 3)
      assert Visibility.visible_tiles(w, [%{type: :settler, tile_id: 0}]) == ring(w, 0, 2)
    end

    test "the lord's ball is strictly larger than the settler's from the same tile" do
      w = world()
      lord_ball = Visibility.visible_tiles(w, [%{type: :lord, tile_id: 0}])
      settler_ball = Visibility.visible_tiles(w, [%{type: :settler, tile_id: 0}])

      assert MapSet.subset?(settler_ball, lord_ball)
      assert MapSet.size(lord_ball) > MapSet.size(settler_ball)
    end

    test "is the union of every unit's ball" do
      w = world()
      [other | _] = Regions.adjacent_tiles(w, 0)

      units = [%{type: :lord, tile_id: 0}, %{type: :settler, tile_id: other}]
      expected = MapSet.union(ring(w, 0, 3), ring(w, other, 2))

      assert Visibility.visible_tiles(w, units) == expected
    end

    test "no units means nothing is visible" do
      assert Visibility.visible_tiles(world(), []) == MapSet.new()
    end
  end

  describe "filter/2" do
    test "own units are always included, explored is returned as a list" do
      w = world()

      state = %{
        world: w,
        turn: 1,
        units: %{
          1 => %{
            id: 1,
            player_id: :p1,
            type: :lord,
            tile_id: 0,
            hp: 10,
            max_hp: 10,
            movement: 3,
            max_movement: 3
          }
        },
        orders: %{},
        players: %{p1: %{id: :p1, user_id: 1, region_id: 0, gold: 50}},
        explored: %{p1: MapSet.new([0, 1])}
      }

      result = Visibility.filter(state, :p1)

      assert Enum.map(result.units, & &1.id) == [1]
      assert 0 in result.visible
      assert Enum.sort(result.explored) == [0, 1]
    end

    test "another player's unit leaks through only while it stands on a visible tile" do
      w = world()
      lord_ball = ring(w, 0, 3)
      hidden_tile = Enum.find(0..(Globe.tile_count(@frequency) - 1), &(&1 not in lord_ball))
      [visible_neighbor | _] = Regions.adjacent_tiles(w, 0)

      state = %{
        world: w,
        turn: 1,
        units: %{
          1 => %{
            id: 1,
            player_id: :p1,
            type: :lord,
            tile_id: 0,
            hp: 10,
            max_hp: 10,
            movement: 3,
            max_movement: 3
          },
          2 => %{
            id: 2,
            player_id: :p2,
            type: :lord,
            tile_id: visible_neighbor,
            hp: 10,
            max_hp: 10,
            movement: 3,
            max_movement: 3
          },
          3 => %{
            id: 3,
            player_id: :p2,
            type: :lord,
            tile_id: hidden_tile,
            hp: 10,
            max_hp: 10,
            movement: 3,
            max_movement: 3
          }
        },
        orders: %{},
        players: %{
          p1: %{id: :p1, user_id: 1, region_id: 0, gold: 50},
          p2: %{id: :p2, user_id: 2, region_id: 1, gold: 50}
        },
        explored: %{}
      }

      result = Visibility.filter(state, :p1)
      ids = Enum.map(result.units, & &1.id)

      assert 1 in ids
      assert 2 in ids
      refute 3 in ids
    end

    test "an unexplored, never-visible player has empty visible and explored sets" do
      state = %{
        world: world(),
        turn: 1,
        units: %{},
        orders: %{},
        players: %{p1: %{id: :p1, user_id: 1, region_id: 0, gold: 50}},
        explored: %{}
      }

      assert Visibility.filter(state, :p1) == %{visible: [], explored: [], units: []}
    end
  end

  # Independent BFS reference (mirrors the spex fixture technique) used to
  # cross-check Visibility's internal ball computation.
  defp ring(world, start, depth) do
    {_frontier, seen} =
      Enum.reduce(1..depth, {[start], MapSet.new([start])}, fn _, {frontier, seen} ->
        next =
          frontier
          |> Enum.flat_map(&Regions.adjacent_tiles(world, &1))
          |> Enum.uniq()
          |> Enum.reject(&MapSet.member?(seen, &1))

        {next, MapSet.union(seen, MapSet.new(next))}
      end)

    seen
  end
end
