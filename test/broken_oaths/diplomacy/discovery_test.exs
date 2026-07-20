defmodule BrokenOaths.Diplomacy.DiscoveryTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Diplomacy.Discovery
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.World

  @frequency 8
  @seed 424_242

  defp world, do: %World{seed: @seed, frequency: @frequency}

  defp unit(id, player_id, type, tile_id),
    do:
      {id,
       %{
         id: id,
         player_id: player_id,
         type: type,
         tile_id: tile_id,
         hp: 10,
         max_hp: 10,
         movement: 3,
         max_movement: 3
       }}

  defp state(units, opts \\ []) do
    %{
      world: world(),
      turn: 1,
      units: Map.new(units),
      cities: Keyword.get(opts, :cities, %{}),
      players: %{
        p1: %{id: :p1, user_id: 1, region_id: 0, gold: 50},
        p2: %{id: :p2, user_id: 2, region_id: 1, gold: 50}
      }
    }
  end

  # A tile whose mesh-adjacency distance from `start` is exactly `depth`
  # hops — the ring at `depth`, minus everything already inside the
  # `depth - 1` ball. Used to place a unit just past a vision radius (or
  # just inside one) without hardcoding mesh-specific tile ids.
  defp tile_at_distance(w, start, depth) do
    ball = fn d ->
      {_frontier, seen} =
        Enum.reduce(1..d, {[start], MapSet.new([start])}, fn _, {frontier, seen} ->
          next =
            frontier
            |> Enum.flat_map(&Regions.adjacent_tiles(w, &1))
            |> Enum.uniq()
            |> Enum.reject(&MapSet.member?(seen, &1))

          {next, MapSet.union(seen, MapSet.new(next))}
        end)

      seen
    end

    MapSet.difference(ball.(depth), ball.(depth - 1)) |> Enum.at(0)
  end

  describe "new_contacts/2" do
    test "another player's unit newly within my vision is a new contact" do
      w = world()
      [neighbor | _] = Regions.adjacent_tiles(w, 0)

      s = state([unit(1, :p1, :lord, 0), unit(2, :p2, :lord, neighbor)])

      assert Discovery.new_contacts(s, MapSet.new()) == [{:p1, :p2}]
    end

    test "another player's city newly within my vision is a new contact" do
      w = world()
      [neighbor | _] = Regions.adjacent_tiles(w, 0)

      s = state([unit(1, :p1, :lord, 0)], cities: %{10 => %{id: 10, player_id: :p2, tile_id: neighbor}})

      assert Discovery.new_contacts(s, MapSet.new()) == [{:p1, :p2}]
    end

    test "no sighting at all yields no contacts" do
      w = world()
      far_tile = tile_at_distance(w, 0, 4)

      s = state([unit(1, :p1, :lord, 0), unit(2, :p2, :lord, far_tile)])

      assert Discovery.new_contacts(s, MapSet.new()) == []
    end

    test "a barbarian unit (player_id: nil) never triggers discovery" do
      w = world()
      [neighbor | _] = Regions.adjacent_tiles(w, 0)

      s = state([unit(1, :p1, :lord, 0), unit(2, nil, :barbarian_warrior, neighbor)])

      assert Discovery.new_contacts(s, MapSet.new()) == []
    end

    test "an already-known pair, in either direction, is never reported again" do
      w = world()
      [neighbor | _] = Regions.adjacent_tiles(w, 0)

      s = state([unit(1, :p1, :lord, 0), unit(2, :p2, :lord, neighbor)])

      assert Discovery.new_contacts(s, MapSet.new([{:p1, :p2}])) == []
      assert Discovery.new_contacts(s, MapSet.new([{:p2, :p1}])) == []
    end

    test "sighting is one-directional but the contact is reported once, in canonical (lowest id first) order" do
      w = world()
      # My lord (vision radius 3) sees the settler at distance 3, but a
      # settler's own vision radius (2) can never see back that far —
      # only ONE direction of sighting is true here.
      far_tile = tile_at_distance(w, 0, 3)

      s = state([unit(1, :p1, :lord, 0), unit(2, :p2, :settler, far_tile)])

      assert Discovery.new_contacts(s, MapSet.new()) == [{:p1, :p2}]
    end

    test "mutual, simultaneous sighting between two players is reported exactly once" do
      w = world()
      [neighbor | _] = Regions.adjacent_tiles(w, 0)

      # Both lords sit within each other's vision radius — both
      # directions of sighting are independently true this tick.
      s = state([unit(1, :p1, :lord, 0), unit(2, :p2, :lord, neighbor)])

      assert Discovery.new_contacts(s, MapSet.new()) == [{:p1, :p2}]
    end

    test "a third, unrelated player outside vision is never included" do
      w = world()
      [neighbor | _] = Regions.adjacent_tiles(w, 0)
      far_tile = tile_at_distance(w, 0, 4)

      s =
        state([unit(1, :p1, :lord, 0), unit(2, :p2, :lord, neighbor), unit(3, :p3, :lord, far_tile)])

      s = %{s | players: Map.put(s.players, :p3, %{id: :p3, user_id: 3, region_id: 2, gold: 50})}

      assert Discovery.new_contacts(s, MapSet.new()) == [{:p1, :p2}]
    end
  end
end
