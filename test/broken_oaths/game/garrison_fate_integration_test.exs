defmodule BrokenOaths.Game.GarrisonFateIntegrationTest do
  @moduledoc """
  End-to-end (real `WorldServer`, real DB) coverage for two QA issues
  in the same feature: `resolve_garrison_fate/4`'s own ownership bug
  (94885d5e — "execute" deleted the CONQUEROR's own unit) and the
  missing Honor consequence (ed1ff4c0). `BrokenOaths.Game.SiegeTest`
  covers the same ownership fix as a pure unit test against
  `Siege.fallen_garrison/2`/`resolve_garrison_fate/3` directly; this
  file proves the full stack (real siege, real capture, real
  `Game.resolve_garrison_fate/4` call, real persisted Honor) agrees.
  """

  # async: false — exercises a named, Registry-addressed GenServer,
  # same status `WorldServerTest` itself already carries.
  use BrokenOathsTest.DataCase, async: false

  alias BrokenOaths.Game
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.WorldsFixtures

  setup do
    original = Application.get_env(:broken_oaths, :feudal_enabled)
    Application.put_env(:broken_oaths, :feudal_enabled, true)
    on_exit(fn -> Application.put_env(:broken_oaths, :feudal_enabled, original) end)
    :ok
  end

  # Sieges `defender_user`'s single city down to 0 HP with `attacker`'s
  # own unit (already adjacent), then walks `attacker` onto the broken
  # city's own tile — mirrors `BrokenOathsSpex.SharedGivens.
  # capture_city/6`'s own real-siege flow, just driven through bare
  # `Game` calls (no LiveView) since this file is a `DataCase`, not a
  # `ConnCase`.
  defp siege_and_capture(world, attacker_user, attacker, defender_user, city) do
    broken_city =
      Enum.reduce_while(1..40, city, fn _, current ->
        if current.hp <= 0 do
          {:halt, current}
        else
          Game.attack_city(world, attacker_user, attacker.id, current.id)
          Game.advance_turn(world)
          [refreshed] = for c <- Game.player_cities(world, defender_user), c.id == current.id, do: c
          {:cont, refreshed}
        end
      end)

    assert broken_city.hp == 0

    {:ok, _} = Game.queue_move(world, attacker_user, attacker.id, city.tile_id)
    Game.advance_turn(world)

    [moved_attacker] = for u <- Game.player_units(world, attacker_user), u.id == attacker.id, do: u
    assert moved_attacker.tile_id == city.tile_id

    moved_attacker
  end

  defp adjacent_land_tile(world, target_tile_id) do
    [tile | _] =
      world
      |> Regions.adjacent_tiles(target_tile_id)
      |> Enum.filter(&(Regions.tile_class(world, &1) == :land))

    tile
  end

  describe "resolve_garrison_fate/4 — execute (QA issues 94885d5e/ed1ff4c0)" do
    test "removes only the defeated garrison, leaves the conqueror's own unit intact, and costs Honor" do
      world = WorldsFixtures.world_fixture(%{seed: 424_242, frequency: 8})
      attacker_user = UsersFixtures.user_fixture()
      defender_user = UsersFixtures.user_fixture()

      {:ok, attacker_player} = Game.join_world(world, attacker_user)
      {:ok, defender_player} = Game.join_world(world, defender_user)

      [defender_settler | _] =
        for u <- Game.player_units(world, defender_user), u.type == :settler, do: u

      :ok = Game.found_city(world, defender_user, defender_settler.id)
      [city] = Game.player_cities(world, defender_user)

      attack_tile = adjacent_land_tile(world, city.tile_id)
      attacker = Game.spawn_unit_for_test(world, attacker_player.id, :warrior, attack_tile)

      moved_attacker = siege_and_capture(world, attacker_user, attacker, defender_user, city)

      # The defeated owner's own fallen garrison, placed directly onto
      # the SAME tile the conqueror's unit already occupies — exactly
      # the co-location that made the ownership-blind, tile-only filter
      # (the bug) match the conqueror's own unit too.
      garrison = Game.spawn_unit_for_test(world, defender_player.id, :warrior, city.tile_id)

      assert Game.honor(world, attacker_user) == 100

      :ok = Game.resolve_garrison_fate(world, attacker_user, city.id, :execute)

      attacker_units = Game.player_units(world, attacker_user)
      assert Enum.any?(attacker_units, &(&1.id == moved_attacker.id))

      defender_units = Game.player_units(world, defender_user)
      refute Enum.any?(defender_units, &(&1.id == garrison.id))

      assert Game.honor(world, attacker_user) == 98
    end
  end

  describe "resolve_garrison_fate/4 — release (QA issue ed1ff4c0)" do
    test "leaves both the conqueror's unit and the garrison intact, with no Honor change" do
      world = WorldsFixtures.world_fixture(%{seed: 424_242, frequency: 8})
      attacker_user = UsersFixtures.user_fixture()
      defender_user = UsersFixtures.user_fixture()

      {:ok, attacker_player} = Game.join_world(world, attacker_user)
      {:ok, defender_player} = Game.join_world(world, defender_user)

      [defender_settler | _] =
        for u <- Game.player_units(world, defender_user), u.type == :settler, do: u

      :ok = Game.found_city(world, defender_user, defender_settler.id)
      [city] = Game.player_cities(world, defender_user)

      attack_tile = adjacent_land_tile(world, city.tile_id)
      attacker = Game.spawn_unit_for_test(world, attacker_player.id, :warrior, attack_tile)

      moved_attacker = siege_and_capture(world, attacker_user, attacker, defender_user, city)
      garrison = Game.spawn_unit_for_test(world, defender_player.id, :warrior, city.tile_id)

      :ok = Game.resolve_garrison_fate(world, attacker_user, city.id, :release)

      attacker_units = Game.player_units(world, attacker_user)
      assert Enum.any?(attacker_units, &(&1.id == moved_attacker.id))

      defender_units = Game.player_units(world, defender_user)
      assert Enum.any?(defender_units, &(&1.id == garrison.id))

      assert Game.honor(world, attacker_user) == 100
    end
  end
end
