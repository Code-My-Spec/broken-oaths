defmodule BrokenOaths.Game.WorldServerTest do
  # async: false — exercises a named, Registry-addressed GenServer.
  use BrokenOathsTest.DataCase, async: false

  import Ecto.Query

  alias BrokenOaths.Game
  alias BrokenOaths.Game.PlayerResearch
  alias BrokenOaths.Game.Unit
  alias BrokenOaths.Game.WorldServer
  alias BrokenOaths.Repo
  alias BrokenOaths.UsersFixtures
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

  # -------------------------------------------------------------------
  # Dev-only QA control surface: pause/resume (see `BrokenOathsWeb.DevQaController`)
  # -------------------------------------------------------------------

  describe "pause_ticks/1" do
    test "stops the automatic :tick handler but advance_turn still steps, and persists across a restart" do
      world = WorldsFixtures.world_fixture()
      refute Game.paused?(world)
      assert Game.turn_number(world) == 0

      :ok = Game.pause_ticks(world)
      assert Game.paused?(world)
      assert Repo.one(from(w in World, where: w.id == ^world.id, select: w.paused))

      # A stray `:tick` — exactly what the real timer would send — must
      # be a no-op while paused. `send/2` is async, but the very next
      # `GenServer.call` (via `Game.turn_number/1`) only gets processed
      # after this mailbox message, so no sleep is needed to observe it.
      {:ok, pid} = WorldServer.ensure_started(world)
      send(pid, :tick)
      assert Game.turn_number(world) == 0

      # The manual step (`:advance_turn`) is a SEPARATE handler and
      # still works while paused.
      :ok = Game.advance_turn(world)
      assert Game.turn_number(world) == 1

      # Persists across a restart — a paused QA world stays frozen.
      WorldServer.restart(world)
      assert Game.paused?(world)
      assert Game.turn_number(world) == 1

      WorldServer.restart(world)
    end
  end

  describe "resume_ticks/1" do
    test "clears paused and the :tick handler advances turns again" do
      world = WorldsFixtures.world_fixture()
      :ok = Game.pause_ticks(world)
      assert Game.paused?(world)

      :ok = Game.resume_ticks(world)
      refute Game.paused?(world)
      refute Repo.one(from(w in World, where: w.id == ^world.id, select: w.paused))

      {:ok, pid} = WorldServer.ensure_started(world)
      send(pid, :tick)
      assert Game.turn_number(world) == 1

      WorldServer.restart(world)
    end

    test "resets turn_started_at so resuming never owes a catch-up" do
      world = WorldsFixtures.world_fixture(%{turn_seconds: 100})
      :ok = Game.pause_ticks(world)

      # Backdate turn_started_at, simulating a long pause.
      Repo.update_all(from(w in World, where: w.id == ^world.id),
        set: [turn_started_at: DateTime.add(DateTime.utc_now(), -10_000, :second)]
      )

      :ok = Game.resume_ticks(world)

      ends_at = Game.turn_ends_at(world)
      seconds_left = DateTime.diff(ends_at, DateTime.utc_now(), :second)
      # A fresh 100s window, not "already overdue by 9900s".
      assert seconds_left in 90..100

      WorldServer.restart(world)
    end
  end

  describe "boot-time dormancy catch-up" do
    test "never replays missed turns for a paused world" do
      # `catch_up/1`'s dormancy replay only fires when `game_auto_tick`
      # is on — `config/test.exs` turns it off so ordinary specs drive
      # turns deterministically via `advance_turn/1` instead of a real
      # wall-clock timer. Briefly flip it on here, for exactly the
      # width of this test, to exercise the REAL boot path a live
      # (non-test) server takes — restored in `on_exit` even if an
      # assertion below fails.
      Application.put_env(:broken_oaths, :game_auto_tick, true)
      on_exit(fn -> Application.put_env(:broken_oaths, :game_auto_tick, false) end)

      stale_started_at =
        DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-1000, :second)

      paused_world = WorldsFixtures.world_fixture(%{turn_seconds: 60})
      running_world = WorldsFixtures.world_fixture(%{turn_seconds: 60})

      Repo.update_all(from(w in World, where: w.id == ^paused_world.id),
        set: [turn_started_at: stale_started_at, paused: true]
      )

      Repo.update_all(from(w in World, where: w.id == ^running_world.id),
        set: [turn_started_at: stale_started_at]
      )

      # Control: an equally-stale, NOT paused world DOES replay its
      # missed turns on boot — proves the staleness fixture is real,
      # not that catch-up is simply disabled altogether.
      assert Game.turn_number(running_world) > 0

      # The paused world, exactly as stale, replays nothing.
      assert Game.turn_number(paused_world) == 0
      assert Game.paused?(paused_world)

      # Disarm whatever real tick timers booting under
      # `game_auto_tick: true` just armed, before restoring the
      # ordinary test config — a live 60s timer firing well after this
      # test (and its DB sandbox connection) ends would otherwise crash
      # in the background.
      :ok = Game.pause_ticks(running_world)
      :ok = Game.pause_ticks(paused_world)

      Application.put_env(:broken_oaths, :game_auto_tick, false)
      WorldServer.restart(paused_world)
      WorldServer.restart(running_world)
    end
  end

  # -------------------------------------------------------------------
  # Dev-only QA control surface: unit/camp fixtures
  # -------------------------------------------------------------------

  describe "spawn_unit_for_test/4" do
    test "places a real player-owned unit with that type's starting stats" do
      world = WorldsFixtures.world_fixture()
      user = UsersFixtures.user_fixture()
      {:ok, player} = Game.join_world(world, user)

      unit = Game.spawn_unit_for_test(world, player.id, :warrior, 42)

      assert unit.type == :warrior
      assert unit.tile_id == 42
      assert unit.hp == 100
      assert unit.max_hp == 100
      assert unit.movement == 1
      assert Enum.any?(Game.player_units(world, user), &(&1.id == unit.id))

      WorldServer.restart(world)
    end
  end

  describe "remove_unit_for_test/2" do
    test "hard-deletes a unit" do
      world = WorldsFixtures.world_fixture()
      unit = Game.spawn_barbarian_for_test(world, 10)

      :ok = Game.remove_unit_for_test(world, unit.id)

      assert Repo.get(Unit, unit.id) == nil

      refute Enum.any?(Game.list_camps(world), fn camp ->
               unit.id in Enum.map(camp.warriors, & &1.id)
             end)

      WorldServer.restart(world)
    end
  end

  describe "set_camp_hp_for_test/3" do
    test "sets a camp's HP directly, bypassing combat" do
      world = WorldsFixtures.world_fixture(%{frequency: 8})
      user = UsersFixtures.user_fixture()
      {:ok, _player} = Game.join_world(world, user)

      [settler] = for u <- Game.player_units(world, user), u.type == :settler, do: u
      :ok = Game.found_city(world, user, settler.id)

      [camp | _] = Game.list_camps(world)

      :ok = Game.set_camp_hp_for_test(world, camp.id, 1)

      assert Enum.find(Game.list_camps(world), &(&1.id == camp.id)).hp == 1

      WorldServer.restart(world)
    end
  end

  # -------------------------------------------------------------------
  # Research (story 902)
  # -------------------------------------------------------------------

  describe "player_research/2" do
    test "joining a world creates a fresh, empty research row" do
      world = WorldsFixtures.world_fixture()
      user = UsersFixtures.user_fixture()
      {:ok, _player} = Game.join_world(world, user)

      assert Game.player_research(world, user) == %{
               completed_techs: [],
               current_research: nil,
               banked_science: %{},
               progress: nil,
               science_per_turn: 0
             }

      WorldServer.restart(world)
    end

    test "nil for a user who hasn't joined" do
      world = WorldsFixtures.world_fixture()
      stranger = UsersFixtures.user_fixture()

      assert Game.player_research(world, stranger) == nil

      WorldServer.restart(world)
    end

    test "science_per_turn reflects the population of the player's own cities" do
      world = WorldsFixtures.world_fixture(%{frequency: 8})
      user = UsersFixtures.user_fixture()
      {:ok, _player} = Game.join_world(world, user)

      [settler] = for u <- Game.player_units(world, user), u.type == :settler, do: u
      :ok = Game.found_city(world, user, settler.id)

      # A freshly founded city is size 1 → 2 science/turn.
      assert Game.player_research(world, user).science_per_turn == 2

      WorldServer.restart(world)
    end
  end

  describe "set_research/3" do
    test "selects current_research, retrievable via player_research/2" do
      world = WorldsFixtures.world_fixture()
      user = UsersFixtures.user_fixture()
      {:ok, _player} = Game.join_world(world, user)

      :ok = Game.set_research(world, user, :pottery)

      assert Game.player_research(world, user).current_research == :pottery
      assert Game.player_research(world, user).progress == %{tech: :pottery, banked: 0, cost: 50}

      WorldServer.restart(world)
    end

    test "refuses an unknown tech" do
      world = WorldsFixtures.world_fixture()
      user = UsersFixtures.user_fixture()
      {:ok, _player} = Game.join_world(world, user)

      assert Game.set_research(world, user, :writing) == {:error, :invalid_tech}

      WorldServer.restart(world)
    end

    test "refuses a user who hasn't joined" do
      world = WorldsFixtures.world_fixture()
      stranger = UsersFixtures.user_fixture()

      assert Game.set_research(world, stranger, :pottery) == {:error, :not_a_player}

      WorldServer.restart(world)
    end

    test "switching research retains banked progress per tech (persisted across a restart)" do
      world = WorldsFixtures.world_fixture(%{frequency: 8})
      user = UsersFixtures.user_fixture()
      {:ok, _player} = Game.join_world(world, user)

      [settler] = for u <- Game.player_units(world, user), u.type == :settler, do: u
      :ok = Game.found_city(world, user, settler.id)

      :ok = Game.set_research(world, user, :pottery)
      :ok = Game.advance_turn(world)
      :ok = Game.advance_turn(world)

      # size 1 city * 2 science/pop * 2 turns = 4 banked toward pottery.
      assert Game.player_research(world, user).banked_science == %{pottery: 4}

      :ok = Game.set_research(world, user, :mining)
      assert Game.player_research(world, user).current_research == :mining
      assert Game.player_research(world, user).banked_science == %{pottery: 4}

      WorldServer.restart(world)

      # Restarting rehydrates from the DB — banked science and the
      # current selection both survive, same guarantee `pause_ticks/1`'s
      # own restart test already exercises for the turn clock.
      assert Game.player_research(world, user).current_research == :mining
      assert Game.player_research(world, user).banked_science == %{pottery: 4}

      WorldServer.restart(world)
    end
  end

  # -------------------------------------------------------------------
  # Regression for QA issue 957f4e55: a `game_player_research` row is
  # only ever created at join (`persist_join!/3`) or backfilled at boot
  # (`backfill_player_research/3`) — these simulate a player who joined
  # BEFORE story 902 shipped by deleting their row out from under a
  # live WorldServer, then exercising each write path that used to
  # silently `update_all` against nothing.
  # -------------------------------------------------------------------

  describe "research persistence for a player with a missing PlayerResearch row" do
    test "set_research upserts a missing row and it survives a restart" do
      world = WorldsFixtures.world_fixture()
      user = UsersFixtures.user_fixture()
      {:ok, player} = Game.join_world(world, user)

      Repo.delete_all(from(r in PlayerResearch, where: r.player_id == ^player.id))
      refute Repo.get_by(PlayerResearch, player_id: player.id)

      :ok = Game.set_research(world, user, :pottery)

      row = Repo.get_by(PlayerResearch, player_id: player.id)
      assert row.current_research == :pottery
      assert Game.player_research(world, user).current_research == :pottery

      WorldServer.restart(world)

      assert Game.player_research(world, user).current_research == :pottery

      WorldServer.restart(world)
    end

    test "the tick's science-accrual persist upserts a missing row and banked science survives a restart" do
      world = WorldsFixtures.world_fixture(%{frequency: 8})
      user = UsersFixtures.user_fixture()
      {:ok, player} = Game.join_world(world, user)

      [settler] = for u <- Game.player_units(world, user), u.type == :settler, do: u
      :ok = Game.found_city(world, user, settler.id)
      :ok = Game.set_research(world, user, :pottery)

      # Delete the row again after `set_research` re-created it, so the
      # NEXT write (the tick's own science-accrual persist) is the one
      # that hits a missing row.
      Repo.delete_all(from(r in PlayerResearch, where: r.player_id == ^player.id))
      refute Repo.get_by(PlayerResearch, player_id: player.id)

      :ok = Game.advance_turn(world)
      :ok = Game.advance_turn(world)

      # size 1 city * 2 science/pop * 2 turns = 4 banked toward pottery.
      row = Repo.get_by(PlayerResearch, player_id: player.id)
      assert row.banked_science == %{"pottery" => 4}
      assert Game.player_research(world, user).banked_science == %{pottery: 4}

      WorldServer.restart(world)

      assert Game.player_research(world, user).banked_science == %{pottery: 4}

      WorldServer.restart(world)
    end

    test "a restart backfills a missing row with a fresh, empty research state" do
      world = WorldsFixtures.world_fixture()
      user = UsersFixtures.user_fixture()
      {:ok, player} = Game.join_world(world, user)

      Repo.delete_all(from(r in PlayerResearch, where: r.player_id == ^player.id))
      refute Repo.get_by(PlayerResearch, player_id: player.id)

      WorldServer.restart(world)

      assert Game.player_research(world, user) == %{
               completed_techs: [],
               current_research: nil,
               banked_science: %{},
               progress: nil,
               science_per_turn: 0
             }

      assert Repo.get_by(PlayerResearch, player_id: player.id)

      WorldServer.restart(world)
    end
  end

  # -------------------------------------------------------------------
  # Mining's 3-turn mine duration (story 902, criterion 7628) — the
  # end-to-end version of what `Research.mine_duration/1`'s own unit
  # tests already cover in isolation: the actual duration a build
  # resolves to, driven through `start_improvement/4` for real.
  # -------------------------------------------------------------------

  describe "start_improvement/4 resolves mine duration from the worker's owner's research" do
    test "a mine takes the base 5 turns without Mining researched" do
      world = WorldsFixtures.world_fixture(%{seed: 33, frequency: 8})
      user = UsersFixtures.user_fixture()
      {:ok, player} = Game.join_world(world, user)

      [settler] = for u <- Game.player_units(world, user), u.type == :settler, do: u
      :ok = Game.found_city(world, user, settler.id)

      hills_tile = hills_tile(world)
      worker = Game.spawn_unit_for_test(world, player.id, :worker, hills_tile)
      :ok = Game.start_improvement(world, user, worker.id, "mine")

      for _ <- 1..4, do: :ok = Game.advance_turn(world)
      refute improvement_complete?(world, user, hills_tile)

      :ok = Game.advance_turn(world)
      assert improvement_complete?(world, user, hills_tile)

      WorldServer.restart(world)
    end

    test "a mine takes 3 turns once the building worker's owner has completed Mining" do
      world = WorldsFixtures.world_fixture(%{seed: 33, frequency: 8})
      user = UsersFixtures.user_fixture()
      {:ok, player} = Game.join_world(world, user)

      [settler] = for u <- Game.player_units(world, user), u.type == :settler, do: u
      :ok = Game.found_city(world, user, settler.id)

      :ok = Game.set_research(world, user, :mining)
      complete_current_research(world, user)
      assert :mining in Game.player_research(world, user).completed_techs

      hills_tile = hills_tile(world)
      worker = Game.spawn_unit_for_test(world, player.id, :worker, hills_tile)
      :ok = Game.start_improvement(world, user, worker.id, "mine")

      for _ <- 1..2, do: :ok = Game.advance_turn(world)
      refute improvement_complete?(world, user, hills_tile)

      :ok = Game.advance_turn(world)
      assert improvement_complete?(world, user, hills_tile)

      WorldServer.restart(world)
    end
  end

  defp hills_tile(world) do
    land? = fn t -> BrokenOaths.Worlds.Regions.tile_class(world, t) == :land end

    Enum.find(0..641, fn t ->
      land?.(t) and BrokenOaths.Worlds.Regions.terrain(world, t).relief == :hills
    end)
  end

  defp improvement_complete?(world, user, tile_id) do
    Enum.any?(Game.improvements_visible_to(world, user), &(&1.tile_id == tile_id and &1.status == :complete))
  end

  defp complete_current_research(world, user) do
    Enum.reduce_while(1..60, :ok, fn _, :ok ->
      if Game.player_research(world, user).current_research == nil do
        {:halt, :ok}
      else
        :ok = Game.advance_turn(world)
        {:cont, :ok}
      end
    end)
  end
end
