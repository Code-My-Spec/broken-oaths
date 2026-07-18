defmodule BrokenOaths.Game.SiegeTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Game.CityDefense
  alias BrokenOaths.Game.Siege

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

  defp city(id, opts) do
    %{
      id: id,
      player_id: Keyword.get(opts, :player_id, 1),
      name: Keyword.get(opts, :name, "Test City"),
      tile_id: Keyword.fetch!(opts, :tile),
      size: Keyword.get(opts, :size, 1),
      hp: Keyword.get(opts, :hp, CityDefense.max_hp()),
      worked_tiles: Keyword.get(opts, :worked_tiles, []),
      production_halted_until: Keyword.get(opts, :production_halted_until),
      occupied_by_player_id: Keyword.get(opts, :occupied_by_player_id)
    }
  end

  describe "validate_siege/3" do
    test "refuses a civilian besieger outright" do
      settler = unit(1, type: :settler, tile: 1)
      target = city(1, tile: 2, player_id: 2)

      assert Siege.validate_siege(settler, target, [2]) == {:error, :not_military}
    end

    test "allows a military besieger meeting every CityDefense.validate_attack/3 rule" do
      warrior = unit(1, type: :warrior, tile: 1)
      target = city(1, tile: 2, player_id: 2)

      assert Siege.validate_siege(warrior, target, [2]) == :ok
    end

    test "still refuses a non-adjacent military besieger" do
      warrior = unit(1, type: :warrior, tile: 1)
      target = city(1, tile: 99, player_id: 2)

      assert Siege.validate_siege(warrior, target, [2]) == {:error, :not_adjacent}
    end

    test "still refuses attacking your own city" do
      warrior = unit(1, type: :warrior, tile: 1, player_id: 1)
      target = city(1, tile: 2, player_id: 1)

      assert Siege.validate_siege(warrior, target, [2]) == {:error, :own_city}
    end

    test "still refuses a besieger with no movement left" do
      warrior = unit(1, type: :warrior, tile: 1, movement: 0)
      target = city(1, tile: 2, player_id: 2)

      assert Siege.validate_siege(warrior, target, [2]) == {:error, :out_of_movement}
    end
  end

  describe "take_damage/2" do
    test "subtracts damage without pillaging" do
      c = city(1, tile: 1, hp: 30)
      broken = Siege.take_damage(c, 30)

      assert broken.hp == 0
      assert broken.size == 1
      assert broken.worked_tiles == []
    end

    test "never drives HP below zero" do
      c = city(1, tile: 1, hp: 10)
      broken = Siege.take_damage(c, 999)
      assert broken.hp == 0
    end

    test "a partial hit just lowers HP" do
      c = city(1, tile: 1, hp: 100)
      hit = Siege.take_damage(c, 40)
      assert hit.hp == 60
    end
  end

  describe "status/1, free?/1, broken?/1, occupied?/1" do
    test "a healthy, unoccupied city is free" do
      c = city(1, tile: 1, hp: 100)
      assert Siege.status(c) == :free
      assert Siege.free?(c)
      refute Siege.broken?(c)
      refute Siege.occupied?(c)
    end

    test "a 0 HP, unoccupied city is broken — and still \"free\" (nobody occupies it yet)" do
      c = city(1, tile: 1, hp: 0)
      assert Siege.status(c) == :broken
      assert Siege.broken?(c)
      assert Siege.free?(c)
      refute Siege.occupied?(c)
    end

    test "a city with occupied_by_player_id set is occupied, regardless of HP" do
      c = city(1, tile: 1, hp: 0, occupied_by_player_id: 2)
      assert Siege.status(c) == :occupied
      assert Siege.occupied?(c)
      refute Siege.free?(c)
      refute Siege.broken?(c)
    end
  end

  describe "enterable_despite_garrison?/2" do
    test "true for another player against a broken city" do
      c = city(1, tile: 1, hp: 0, player_id: 2)
      assert Siege.enterable_despite_garrison?(c, 1)
    end

    test "false for a healthy city, even another player's" do
      c = city(1, tile: 1, hp: 100, player_id: 2)
      refute Siege.enterable_despite_garrison?(c, 1)
    end

    test "false for the city's own owner (their own regarrison march is a different rule)" do
      c = city(1, tile: 1, hp: 0, player_id: 2)
      refute Siege.enterable_despite_garrison?(c, 2)
    end

    test "false once already occupied (a fresh captor still needs a fresh capture, not this exception)" do
      c = city(1, tile: 1, hp: 0, player_id: 2, occupied_by_player_id: 3)
      refute Siege.enterable_despite_garrison?(c, 1)
    end
  end

  describe "materialize_captures/2" do
    test "captures a broken, ungarrisoned city entered by a foreign unit" do
      c = city(1, tile: 5, hp: 0, player_id: 2)
      besieger = unit(10, tile: 5, player_id: 1)

      {cities, events} = Siege.materialize_captures(%{1 => c}, %{10 => besieger})

      assert cities[1].occupied_by_player_id == 1
      assert events == [%{city_id: 1, captor_player_id: 1, defeated_player_id: 2}]
    end

    test "does not capture a broken city nobody hostile stands on" do
      c = city(1, tile: 5, hp: 0, player_id: 2)
      elsewhere = unit(10, tile: 6, player_id: 1)

      {cities, events} = Siege.materialize_captures(%{1 => c}, %{10 => elsewhere})

      assert cities[1].occupied_by_player_id == nil
      assert events == []
    end

    test "does not capture a healthy city even with a foreign unit standing on it" do
      c = city(1, tile: 5, hp: 100, player_id: 2)
      foreigner = unit(10, tile: 5, player_id: 1)

      {cities, events} = Siege.materialize_captures(%{1 => c}, %{10 => foreigner})

      assert cities[1].occupied_by_player_id == nil
      assert events == []
    end

    test "the owner's own unit standing on their own broken city never captures it" do
      c = city(1, tile: 5, hp: 0, player_id: 2)
      defender = unit(10, tile: 5, player_id: 2)

      {cities, events} = Siege.materialize_captures(%{1 => c}, %{10 => defender})

      assert cities[1].occupied_by_player_id == nil
      assert events == []
    end

    test "is idempotent — a second pass never re-reports an already-captured city" do
      c = city(1, tile: 5, hp: 0, player_id: 2)
      besieger = unit(10, tile: 5, player_id: 1)

      {cities, _events} = Siege.materialize_captures(%{1 => c}, %{10 => besieger})
      {cities_again, events_again} = Siege.materialize_captures(cities, %{10 => besieger})

      assert cities_again == cities
      assert events_again == []
    end

    test "with several hostile units on the same tile, the lowest unit id wins the capture" do
      c = city(1, tile: 5, hp: 0, player_id: 3)
      first = unit(10, tile: 5, player_id: 1)
      second = unit(5, tile: 5, player_id: 2)

      {cities, events} = Siege.materialize_captures(%{1 => c}, %{10 => first, 5 => second})

      assert cities[1].occupied_by_player_id == 2
      assert [%{captor_player_id: 2}] = events
    end

    test "several independent broken cities each capture in the same pass" do
      city_a = city(1, tile: 5, hp: 0, player_id: 3)
      city_b = city(2, tile: 6, hp: 0, player_id: 4)
      besieger_a = unit(10, tile: 5, player_id: 1)
      besieger_b = unit(11, tile: 6, player_id: 1)

      {cities, events} =
        Siege.materialize_captures(%{1 => city_a, 2 => city_b}, %{10 => besieger_a, 11 => besieger_b})

      assert cities[1].occupied_by_player_id == 1
      assert cities[2].occupied_by_player_id == 1
      assert length(events) == 2
    end
  end

  describe "no_free_cities?/2" do
    test "false while at least one city is free" do
      cities = [
        city(1, tile: 1, player_id: 2, occupied_by_player_id: 1),
        city(2, tile: 2, player_id: 2)
      ]

      refute Siege.no_free_cities?(cities, 2)
    end

    test "true once every one of the player's cities is occupied" do
      cities = [
        city(1, tile: 1, player_id: 2, occupied_by_player_id: 1),
        city(2, tile: 2, player_id: 2, occupied_by_player_id: 1)
      ]

      assert Siege.no_free_cities?(cities, 2)
    end

    test "true for a single-city player whose only city just fell" do
      cities = [city(1, tile: 1, player_id: 2, occupied_by_player_id: 1)]
      assert Siege.no_free_cities?(cities, 2)
    end

    test "another player's cities never affect this player's own free-city count" do
      cities = [
        city(1, tile: 1, player_id: 2),
        city(2, tile: 2, player_id: 5, occupied_by_player_id: 1)
      ]

      refute Siege.no_free_cities?(cities, 2)
    end
  end

  describe "fallen_garrison/2 and resolve_garrison_fate/3" do
    test "fallen_garrison/2 finds the living military defenders on the city's own tile" do
      c = city(1, tile: 5, player_id: 2)
      defender = unit(1, type: :warrior, tile: 5, player_id: 2)
      dead_defender = unit(2, type: :warrior, tile: 5, player_id: 2, hp: 0)
      civilian = unit(3, type: :worker, tile: 5, player_id: 2)

      assert Siege.fallen_garrison(c, [defender, dead_defender, civilian]) == [defender]
    end

    test "resolve_garrison_fate/3 with :release reports nothing to remove" do
      c = city(1, tile: 5, player_id: 2)
      defender = unit(1, type: :warrior, tile: 5, player_id: 2)

      assert Siege.resolve_garrison_fate(:release, c, [defender]) == []
    end

    test "resolve_garrison_fate/3 with :execute reports every fallen garrison unit id" do
      c = city(1, tile: 5, player_id: 2)
      defender_a = unit(1, type: :warrior, tile: 5, player_id: 2)
      defender_b = unit(4, type: :lord, tile: 5, player_id: 2)

      assert Siege.resolve_garrison_fate(:execute, c, [defender_a, defender_b]) |> Enum.sort() == [
               1,
               4
             ]
    end

    test "resolve_garrison_fate/3 with :execute never reports a civilian sheltering on the tile" do
      c = city(1, tile: 5, player_id: 2)
      defender = unit(1, type: :warrior, tile: 5, player_id: 2)
      civilian = unit(2, type: :worker, tile: 5, player_id: 2)

      assert Siege.resolve_garrison_fate(:execute, c, [defender, civilian]) == [1]
    end
  end
end
