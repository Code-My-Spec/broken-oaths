defmodule BrokenOaths.Game.QuickJoinTest do
  # async: false — quick_join boots Registry-addressed WorldServers.
  use BrokenOathsTest.DataCase, async: false

  alias BrokenOaths.Game
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures
  alias BrokenOaths.Worlds.World

  test "places a new player into an open world and returns the WORLD (not the player)" do
    world = WorldsFixtures.world_fixture(%{frequency: 8})
    user = UsersFixtures.user_fixture()

    # Regression: the join branch used to return join_world/2's {:ok, player}
    # payload, so the caller's `world.id` redirect blew up. quick_join must
    # always hand back the World struct.
    assert {:ok, %World{} = joined} = Game.quick_join(user)
    assert joined.id == world.id
    refute Game.claimed_region(world, user) == nil
  end

  test "resumes an existing membership instead of placing the player again" do
    world = WorldsFixtures.world_fixture(%{frequency: 8})
    user = UsersFixtures.user_fixture()

    assert {:ok, first} = Game.quick_join(user)
    assert {:ok, second} = Game.quick_join(user)

    assert first.id == world.id
    assert second.id == world.id
  end
end
