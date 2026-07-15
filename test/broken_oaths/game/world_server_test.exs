defmodule BrokenOaths.Game.WorldServerTest do
  # async: false — exercises a named, Registry-addressed GenServer.
  use BrokenOathsTest.DataCase, async: false

  import Ecto.Query

  alias BrokenOaths.Game
  alias BrokenOaths.Game.WorldServer
  alias BrokenOaths.Repo
  alias BrokenOaths.Worlds.World
  alias BrokenOaths.WorldsFixtures

  # Regression for issue 07ee50d1: a second WorldServer instance for the
  # same world (a second BEAM node running a mix script) used to clobber
  # the live server's turn/turn_started_at row during catch-up. The turn
  # write is now optimistically guarded — a server whose in-memory turn
  # no longer matches the row loses the race and resyncs instead of
  # overwriting.
  test "a stale tick never clobbers an externally advanced turn" do
    world = WorldsFixtures.world_fixture(%{seed: 424_242, frequency: 8})

    # Boot the server and let it own the row at turn 0.
    assert Game.turn_number(world) == 0

    # Simulate the competing instance: advance the row out from under
    # the running server's in-memory state.
    Repo.update_all(from(w in World, where: w.id == ^world.id), set: [turn: 5])

    # The live server ticks from stale in-memory turn 0 → its write must
    # NOT land (turn 1 would rewind the world). It resyncs to turn 5.
    :ok = Game.advance_turn(world)

    assert Repo.one(from(w in World, where: w.id == ^world.id, select: w.turn)) == 5
    assert Game.turn_number(world) == 5

    # And the resynced server ticks normally afterward.
    :ok = Game.advance_turn(world)
    assert Repo.one(from(w in World, where: w.id == ^world.id, select: w.turn)) == 6

    WorldServer.restart(world)
  end
end
