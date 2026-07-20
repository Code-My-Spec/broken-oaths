defmodule BrokenOaths.Game.PlayerStatsTest do
  # async: false — exercises a named, Registry-addressed WorldServer,
  # same status as `WorldServer.pause_ticks/1`'s own suite.
  use BrokenOathsTest.DataCase, async: false

  alias BrokenOaths.Game
  alias BrokenOaths.Combat.BarbarianAI
  alias BrokenOaths.Simulation.WorldServer
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.WorldsFixtures

  setup do
    world = WorldsFixtures.world_fixture(%{seed: 424_242})
    user = UsersFixtures.user_fixture()
    {:ok, _player} = Game.join_world(world, user)
    %{world: world, user: user}
  end

  describe "player_stats/2" do
    test "starts at zero kills and zero camps destroyed for a freshly joined player", %{
      world: world,
      user: user
    } do
      assert Game.player_stats(world, user) == %{barbarians_killed: 0, camps_destroyed: 0}
    end

    test "nil for a user who hasn't joined this world", %{world: world} do
      stranger = UsersFixtures.user_fixture()
      assert Game.player_stats(world, stranger) == nil
    end
  end

  describe "barbarians_killed" do
    test "a lethal attack bumps barbarians_killed, not camps_destroyed", %{
      world: world,
      user: user
    } do
      [lord | _] = for u <- Game.player_units(world, user), u.type == :lord, do: u
      target_tile = adjacent_land_tile(world, lord.tile_id)

      barbarian = Game.spawn_barbarian_for_test(world, target_tile)
      :ok = Game.set_unit_hp_for_test(world, barbarian.id, 1)
      gold_before = Game.gold(world, user)

      assert {:ok, %{damage_dealt: dealt}} = Game.attack(world, user, lord.id, barbarian.id)
      assert dealt >= 1

      assert Game.player_stats(world, user) == %{barbarians_killed: 1, camps_destroyed: 0}
      # Same event that already pays the bounty gold now also bumps the
      # career total — both should move together.
      assert Game.gold(world, user) == gold_before + BarbarianAI.bounty_gold()
    end

    test "a non-lethal attack leaves the total untouched", %{world: world, user: user} do
      [lord | _] = for u <- Game.player_units(world, user), u.type == :lord, do: u
      target_tile = adjacent_land_tile(world, lord.tile_id)

      barbarian = Game.spawn_barbarian_for_test(world, target_tile)

      assert {:ok, _result} = Game.attack(world, user, lord.id, barbarian.id)
      assert Game.player_stats(world, user).barbarians_killed == 0
    end

    test "successive kills accumulate onto the same running total", %{world: world, user: user} do
      [lord | _] = for u <- Game.player_units(world, user), u.type == :lord, do: u

      for _ <- 1..2 do
        target_tile = adjacent_land_tile(world, lord.tile_id)
        barbarian = Game.spawn_barbarian_for_test(world, target_tile)
        :ok = Game.set_unit_hp_for_test(world, barbarian.id, 1)
        :ok = Game.recharge_unit_for_test(world, lord.id)
        assert {:ok, _} = Game.attack(world, user, lord.id, barbarian.id)
      end

      assert Game.player_stats(world, user) == %{barbarians_killed: 2, camps_destroyed: 0}
    end

    test "survives a WorldServer restart", %{world: world, user: user} do
      [lord | _] = for u <- Game.player_units(world, user), u.type == :lord, do: u
      target_tile = adjacent_land_tile(world, lord.tile_id)

      barbarian = Game.spawn_barbarian_for_test(world, target_tile)
      :ok = Game.set_unit_hp_for_test(world, barbarian.id, 1)
      assert {:ok, _} = Game.attack(world, user, lord.id, barbarian.id)

      :ok = WorldServer.restart(world)

      assert Game.player_stats(world, user) == %{barbarians_killed: 1, camps_destroyed: 0}
    end
  end

  describe "camps_destroyed" do
    test "reducing a camp to 0 HP bumps camps_destroyed, not barbarians_killed", %{
      world: world,
      user: user
    } do
      lord = found_first_city_and_return_lord(world, user)
      [camp | _] = Game.list_camps(world)

      target_tile = adjacent_land_tile(world, camp.tile_id)
      clear_squatter(world, target_tile)
      :ok = Game.relocate_unit_for_test(world, lord.id, target_tile)

      destroy_camp(world, user, lord.id, camp.id)

      assert Game.player_stats(world, user) == %{barbarians_killed: 0, camps_destroyed: 1}
    end

    test "survives a WorldServer restart", %{world: world, user: user} do
      lord = found_first_city_and_return_lord(world, user)
      [camp | _] = Game.list_camps(world)

      target_tile = adjacent_land_tile(world, camp.tile_id)
      clear_squatter(world, target_tile)
      :ok = Game.relocate_unit_for_test(world, lord.id, target_tile)

      destroy_camp(world, user, lord.id, camp.id)

      :ok = WorldServer.restart(world)

      assert Game.player_stats(world, user) == %{barbarians_killed: 0, camps_destroyed: 1}
    end
  end

  # Barbarian camps (story 892) only spawn once a player has founded a
  # first city — nothing to destroy without one. Founds it with the
  # player's starting settler and returns their lord (untouched by
  # founding, still free to fight).
  defp found_first_city_and_return_lord(world, user) do
    [settler | _] = for u <- Game.player_units(world, user), u.type == :settler, do: u
    :ok = Game.found_city(world, user, settler.id)

    [lord | _] = for u <- Game.player_units(world, user), u.type == :lord, do: u
    lord
  end

  # An adjacent, workable land tile to `tile_id` — same idiom the story
  # 891/893/894 spex suites already use.
  defp adjacent_land_tile(world, tile_id) do
    [target | _] =
      world
      |> Regions.adjacent_tiles(tile_id)
      |> Enum.filter(&(Regions.tile_class(world, &1) == :land))

    target
  end

  # A real camp may already have spawned a warrior of its own onto the
  # exact tile a test needs to place something else on — relocate it
  # out of the way first. A no-op if `tile_id` is already clear (same
  # `clear_camp_squatter/2` idiom the 901/904 spex suites already use).
  defp clear_squatter(world, tile_id) do
    occupant =
      world
      |> Game.list_camps()
      |> Enum.flat_map(& &1.warriors)
      |> Enum.find(&(&1.tile_id == tile_id))

    if occupant do
      parking =
        world
        |> Regions.adjacent_tiles(tile_id)
        |> Enum.filter(&(Regions.tile_class(world, &1) == :land and &1 != tile_id))

      Enum.find_value(parking, fn t ->
        Game.relocate_unit_for_test(world, occupant.id, t) == :ok
      end)
    end

    :ok
  end

  # Attacks `camp_id` with `attacker_id` until it's destroyed,
  # recharging the attacker's movement between hits directly
  # (`recharge_unit_for_test/2`) rather than a real `advance_turn` —
  # same rationale story 894/901's own spex suites document: a live
  # tick exposes the attacker to a nearby camp's own spawn cadence.
  # Bounded at 12 attempts, comfortably above the ~9 real hits a
  # full-HP camp needs at the lord's own flat damage.
  defp destroy_camp(world, user, attacker_id, camp_id) do
    Enum.reduce_while(1..12, :ok, fn _, :ok ->
      camp = Enum.find(Game.list_camps(world), &(&1.id == camp_id))

      if camp && camp.hp > 0 do
        {:ok, _result} = Game.attack_camp(world, user, attacker_id, camp_id)
        :ok = Game.recharge_unit_for_test(world, attacker_id)
        {:cont, :ok}
      else
        {:halt, :ok}
      end
    end)
  end
end
