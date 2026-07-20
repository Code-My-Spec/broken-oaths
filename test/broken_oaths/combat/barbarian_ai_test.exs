defmodule BrokenOaths.Combat.BarbarianAITest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Combat.BarbarianAI
  alias BrokenOaths.Game.Spawner
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.World

  @frequency 8
  @seed 424_242
  @aggro_range 5
  @roam_radius 2

  defp world, do: %World{seed: @seed, frequency: @frequency}

  defp land?(tile), do: Regions.tile_class(world(), tile) == :land

  # A real, seed-derived land tile to anchor scenarios on — mirrors
  # CampsTest's own `home_region_and_city_tile/0` pattern.
  defp anchor_tile do
    {:ok, %{lord_tile: lord_tile}} = Spawner.spawn_player(world(), [])
    lord_tile
  end

  # Every land tile whose land-path distance from `start` is exactly
  # `depth` (the ring's outer frontier), via the same BFS-growth idiom
  # every spex in 893/894 already uses for "how many hexes away."
  defp ring(start, depth) do
    Enum.reduce(1..depth, {[start], MapSet.new([start])}, fn _, {frontier, seen} ->
      next =
        frontier
        |> Enum.flat_map(&Regions.adjacent_tiles(world(), &1))
        |> Enum.uniq()
        |> Enum.filter(&land?/1)
        |> Enum.reject(&MapSet.member?(seen, &1))

      {next, MapSet.union(seen, MapSet.new(next))}
    end)
    |> elem(0)
  end

  defp land_distance(from, to, max_depth \\ 12) do
    0..max_depth
    |> Enum.reduce_while({[from], MapSet.new([from])}, fn depth, {frontier, seen} ->
      if to in frontier do
        {:halt, {:found, depth}}
      else
        next =
          frontier
          |> Enum.flat_map(&Regions.adjacent_tiles(world(), &1))
          |> Enum.uniq()
          |> Enum.filter(&land?/1)
          |> Enum.reject(&MapSet.member?(seen, &1))

        {:cont, {next, MapSet.union(seen, MapSet.new(next))}}
      end
    end)
    |> case do
      {:found, depth} -> depth
      _ -> nil
    end
  end

  defp unit(id, opts) do
    max_hp = Keyword.get(opts, :max_hp, 100)
    max_movement = Keyword.get(opts, :max_movement, 1)

    %{
      id: id,
      player_id: Keyword.get(opts, :player_id, 1),
      type: Keyword.get(opts, :type, :warrior),
      tile_id: Keyword.fetch!(opts, :tile),
      hp: Keyword.get(opts, :hp, max_hp),
      max_hp: max_hp,
      movement: Keyword.get(opts, :movement, max_movement),
      max_movement: max_movement
    }
  end

  defp barbarian(id, tile) do
    unit(id, player_id: nil, type: :barbarian_warrior, tile: tile, max_hp: 120, max_movement: 1)
  end

  defp city(id, tile), do: %{id: id, tile_id: tile}

  defp decide(barbarian, camp_tile, units, cities \\ [], opts \\ []) do
    opts = Keyword.put_new(opts, :seed, {:test, barbarian.id})
    BarbarianAI.decide(world(), barbarian, camp_tile, units, cities, opts)
  end

  describe "bounty_gold/0" do
    test "pays 10 gold" do
      assert BarbarianAI.bounty_gold() == 10
    end
  end

  describe "decide/6 — attack (criteria 7553, 7555)" do
    test "attacks a player unit standing on an adjacent tile" do
      camp = anchor_tile()
      [adjacent | _] = Regions.adjacent_tiles(world(), camp) |> Enum.filter(&land?/1)

      barb = barbarian(1, camp)
      target = unit(2, tile: adjacent, player_id: 9)

      assert decide(barb, camp, [barb, target]) == {:attack, 2}
    end

    test "never attacks another barbarian, even standing right next to it" do
      camp = anchor_tile()
      [adjacent | _] = Regions.adjacent_tiles(world(), camp) |> Enum.filter(&land?/1)

      barb = barbarian(1, camp)
      other_barb = barbarian(2, adjacent)

      # Nothing else in range, no camp target: falls through to a roam
      # (or hold) decision — anything but attacking its own kind.
      assert decide(barb, camp, [barb, other_barb]) != {:attack, 2}
    end

    test "ties among several adjacent player units break on lowest id" do
      camp = anchor_tile()
      adjacent = Regions.adjacent_tiles(world(), camp) |> Enum.filter(&land?/1)
      [a, b | _] = adjacent

      barb = barbarian(1, camp)
      target_hi = unit(30, tile: a, player_id: 9)
      target_lo = unit(20, tile: b, player_id: 9)

      assert decide(barb, camp, [barb, target_hi, target_lo]) == {:attack, 20}
    end
  end

  describe "decide/6 — movement toward the nearest target (criterion 7551)" do
    test "steps exactly one hex closer to a unit within range" do
      camp = anchor_tile()
      target_tile = ring(camp, 3) |> List.first()
      refute is_nil(target_tile)

      barb = barbarian(1, camp)
      target = unit(2, tile: target_tile, player_id: 9)

      distance_before = land_distance(camp, target_tile)
      assert distance_before in 2..@aggro_range

      assert {:move, next_tile} = decide(barb, camp, [barb, target])
      assert next_tile in Regions.adjacent_tiles(world(), camp)
      assert land_distance(next_tile, target_tile) == distance_before - 1
    end

    test "holds instead of walking onto an undefended city it's already adjacent to" do
      camp = anchor_tile()
      [adjacent | _] = Regions.adjacent_tiles(world(), camp) |> Enum.filter(&land?/1)

      barb = barbarian(1, camp)
      undefended_city = city(1, adjacent)

      assert decide(barb, camp, [barb], [undefended_city]) == :hold
    end

    test "prefers an undefended city over a closer player unit" do
      camp = anchor_tile()
      city_tile = ring(camp, 3) |> List.first()
      # A unit strictly closer to the barbarian than the city.
      unit_tile = ring(camp, 2) |> List.first()
      refute is_nil(city_tile)
      refute is_nil(unit_tile)

      barb = barbarian(1, camp)
      near_unit = unit(2, tile: unit_tile, player_id: 9)
      far_city = city(1, city_tile)

      distance_to_city_before = land_distance(camp, city_tile)
      distance_to_unit_before = land_distance(camp, unit_tile)
      assert distance_to_city_before > distance_to_unit_before

      assert {:move, next_tile} = decide(barb, camp, [barb, near_unit], [far_city])
      # Proof it's heading for the (farther) city, not the (closer) unit.
      assert land_distance(next_tile, city_tile) == distance_to_city_before - 1
    end

    test "a defended city (a unit garrisoned on its own tile) is not preferred over an in-range unit" do
      camp = anchor_tile()
      city_tile = ring(camp, 2) |> List.first()
      unit_tile = ring(camp, 3) |> List.first()
      refute is_nil(city_tile)
      refute is_nil(unit_tile)

      barb = barbarian(1, camp)
      garrison = unit(2, tile: city_tile, player_id: 9)
      lone_unit = unit(3, tile: unit_tile, player_id: 9)
      defended_city = city(1, city_tile)

      distance_to_unit_before = land_distance(camp, unit_tile)

      assert {:move, next_tile} = decide(barb, camp, [barb, garrison, lone_unit], [defended_city])
      assert land_distance(next_tile, unit_tile) == distance_to_unit_before - 1
    end
  end

  describe "decide/6 — roaming (criterion 7552)" do
    test "with nothing in range, stays within a couple of hexes of its own camp" do
      camp = anchor_tile()
      barb = barbarian(1, camp)

      tiles =
        for seed <- 1..8 do
          case decide(barb, camp, [barb], [], seed: {:roam_seed, seed}) do
            {:move, tile} -> tile
            :hold -> camp
          end
        end

      for tile <- tiles do
        distance = land_distance(camp, tile, @roam_radius + 1)
        refute is_nil(distance)
        assert distance <= @roam_radius
      end
    end

    test "a camp-less (orphaned) warrior holds rather than roaming nowhere" do
      barb = barbarian(1, anchor_tile())
      assert decide(barb, nil, [barb]) == :hold
    end
  end

  describe "decide/6 — leash (a warrior never chases far from its own camp)" do
    test "ignores a unit within aggro range of its current tile but well beyond leash range of camp" do
      camp = anchor_tile()

      # A barbarian already at the edge of plausible roam drift, and a
      # target close enough to be a normal aggro-range catch from RIGHT
      # HERE, but whose distance from home camp is well past the leash.
      barb_tile = ring(camp, @roam_radius) |> List.first()
      refute is_nil(barb_tile)

      target_tile =
        Enum.find(ring(barb_tile, @aggro_range), fn t ->
          d = land_distance(camp, t, 20)
          not is_nil(d) and d > @aggro_range
        end)

      refute is_nil(target_tile), "expected geometry to yield a leash-violating candidate"

      barb = barbarian(1, barb_tile)
      target = unit(2, tile: target_tile, player_id: 9)

      # Never a move toward the out-of-leash target's tile.
      case decide(barb, camp, [barb, target]) do
        {:attack, _} -> flunk("target should not be adjacent in this setup")
        {:move, tile} -> assert land_distance(camp, tile, @roam_radius + 1) <= @roam_radius
        :hold -> :ok
      end
    end

    test "an orphaned (camp-less) warrior has no leash at all" do
      camp = anchor_tile()
      barb_tile = ring(camp, 6) |> List.first()
      target_tile = ring(barb_tile, 3) |> List.first()
      refute is_nil(barb_tile)
      refute is_nil(target_tile)

      barb = barbarian(1, barb_tile)
      target = unit(2, tile: target_tile, player_id: 9)

      distance_before = land_distance(barb_tile, target_tile)

      if distance_before && distance_before in 2..@aggro_range do
        assert {:move, next_tile} = decide(barb, nil, [barb, target])
        assert land_distance(next_tile, target_tile) == distance_before - 1
      end
    end
  end
end
