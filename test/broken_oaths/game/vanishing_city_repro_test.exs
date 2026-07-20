defmodule BrokenOaths.Game.VanishingCityReproTest do
  # Repro for issue 3e2b505c: a size-capped city building a settler can
  # vanish from Game.player_cities/2 during the completion tick.
  use BrokenOathsTest.DataCase, async: false

  alias BrokenOaths.Game
  alias BrokenOaths.Simulation.WorldServer
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures

  test "a size-4 city building a settler never vanishes from player_cities" do
    world = WorldsFixtures.world_fixture(%{seed: 424_242, frequency: 8})
    user = UsersFixtures.user_fixture()
    {:ok, _player} = Game.join_world(world, user)

    [settler] = for u <- Game.player_units(world, user), u.type == :settler, do: u
    :ok = Game.found_city(world, user, settler.id)

    [city] = Game.player_cities(world, user)

    # Drive the city to the size-4 cap purely by ticking (food accrues
    # from the center floor + worked tile).
    grow_until = fn grow_until, turns_left ->
      case Game.player_cities(world, user) do
        [%{size: 4}] ->
          :ok

        [_city] when turns_left > 0 ->
          :ok = Game.advance_turn(world)
          grow_until.(grow_until, turns_left - 1)

        [] ->
          flunk("city vanished while growing")

        _ ->
          flunk("city failed to reach size 4 in time")
      end
    end

    grow_until.(grow_until, 60)

    # Queue a settler at the cap and tick through its completion,
    # asserting the city survives every single boundary. 60 turns (not
    # 30): story 893's barbarian AI (this world's first founding seeds
    # real, roaming camps) can occasionally camp adjacent to an
    # undefended city for a while — production keeps banking regardless
    # and the tile frees up once the barbarian moves on, but a tight
    # turn budget makes that ordinary, transient interference look like
    # a spawn failure. The assertion itself (never vanishes, eventually
    # spawns) is unchanged — only the patience.
    :ok = Game.queue_production(world, user, city.id, "settler")

    Enum.each(1..60, fn turn ->
      :ok = Game.advance_turn(world)

      case Game.player_cities(world, user) do
        [c] ->
          assert c.id == city.id
          assert c.size in 1..4

        [] ->
          flunk("city VANISHED from player_cities on tick #{turn} after queueing the settler")
      end
    end)

    # And the settler eventually spawned.
    settlers = for u <- Game.player_units(world, user), u.type == :settler, do: u
    assert settlers != []

    WorldServer.restart(world)
  end
end
