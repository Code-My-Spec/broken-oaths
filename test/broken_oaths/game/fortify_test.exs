defmodule BrokenOaths.Game.FortifyTest do
  # async: false — exercises a named, Registry-addressed WorldServer,
  # same status as `PlayerStatsTest`'s own suite.
  use BrokenOathsTest.DataCase, async: false

  alias BrokenOaths.Game
  alias BrokenOaths.Simulation.WorldServer
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.WorldsFixtures

  setup do
    world = WorldsFixtures.world_fixture(%{seed: 424_242})
    user = UsersFixtures.user_fixture()
    {:ok, player} = Game.join_world(world, user)
    %{world: world, user: user, player: player}
  end

  defp lord_of(world, user) do
    [lord | _] = for u <- Game.player_units(world, user), u.type == :lord, do: u
    lord
  end

  defp adjacent_land_tile(world, tile_id) do
    [target | _] =
      world
      |> Regions.adjacent_tiles(tile_id)
      |> Enum.filter(&(Regions.tile_class(world, &1) == :land))

    target
  end

  defp unit_by_id(world, user, unit_id) do
    Enum.find(Game.player_units(world, user), &(&1.id == unit_id))
  end

  describe "fortify/3" do
    test "sets the flag on the caller's own defend-capable unit", %{world: world, user: user} do
      lord = lord_of(world, user)
      refute lord.fortified

      assert Game.fortify(world, user, lord.id) == :ok
      assert unit_by_id(world, user, lord.id).fortified
    end

    test "is idempotent — fortifying an already-fortified unit stays :ok", %{
      world: world,
      user: user
    } do
      lord = lord_of(world, user)
      assert Game.fortify(world, user, lord.id) == :ok
      assert Game.fortify(world, user, lord.id) == :ok
      assert unit_by_id(world, user, lord.id).fortified
    end

    test "refuses a unit_id the caller doesn't own", %{world: world, user: user} do
      lord = lord_of(world, user)
      stranger = UsersFixtures.user_fixture()
      {:ok, _player} = Game.join_world(world, stranger)

      assert Game.fortify(world, stranger, lord.id) == {:error, :not_owner}
    end

    # A REAL barbarian (`player_id: nil`) hits `:not_owner` first — no
    # session ever owns one. To reach `:not_fortifiable` at all needs a
    # unit that's both player-owned AND of a type `Units.Actions.
    # available/1` never gives `:defend` to — `spawn_unit_for_test/4`
    # can build exactly that synthetic combination (a
    # `:barbarian_warrior` with a real `player_id`), even though normal
    # play never produces one.
    test "refuses a player-owned unit of a type that never carries :defend", %{
      world: world,
      user: user,
      player: player
    } do
      lord = lord_of(world, user)

      player_owned_barbarian =
        Game.spawn_unit_for_test(world, player.id, :barbarian_warrior, lord.tile_id + 1)

      assert Game.fortify(world, user, player_owned_barbarian.id) == {:error, :not_fortifiable}
    end

    test "survives a WorldServer restart", %{world: world, user: user} do
      lord = lord_of(world, user)
      assert Game.fortify(world, user, lord.id) == :ok

      :ok = WorldServer.restart(world)

      assert unit_by_id(world, user, lord.id).fortified
    end
  end

  describe "fortify/3 clears on the unit's own next act (story 920)" do
    test "moving the unit drops its own fortify", %{world: world, user: user} do
      lord = lord_of(world, user)
      assert Game.fortify(world, user, lord.id) == :ok
      assert unit_by_id(world, user, lord.id).fortified

      target_tile = adjacent_land_tile(world, lord.tile_id)
      assert {:ok, _result} = Game.queue_move(world, user, lord.id, target_tile)

      moved = unit_by_id(world, user, lord.id)
      assert moved.tile_id == target_tile
      refute moved.fortified
    end

    test "attacking drops the attacker's own fortify", %{world: world, user: user} do
      lord = lord_of(world, user)
      assert Game.fortify(world, user, lord.id) == :ok

      target_tile = adjacent_land_tile(world, lord.tile_id)
      barbarian = Game.spawn_barbarian_for_test(world, target_tile)

      assert {:ok, _result} = Game.attack(world, user, lord.id, barbarian.id)

      refute unit_by_id(world, user, lord.id).fortified
    end
  end
end
