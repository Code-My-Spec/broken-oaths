defmodule BrokenOaths.Game.WorldServerTest do
  # async: false — exercises a named, Registry-addressed GenServer.
  use BrokenOathsTest.DataCase, async: false

  import Ecto.Query

  alias BrokenOaths.Game
  alias BrokenOaths.Game.Improvement
  alias BrokenOaths.Game.PlayerResearch
  alias BrokenOaths.Game.Unit
  alias BrokenOaths.Game.WorldServer
  alias BrokenOaths.Repo
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.World
  alias BrokenOaths.WorldsFixtures
  alias BrokenOaths.Game.Yields

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
  # Worked tiles — population-cap exploit (QA issue 7509c453)
  # -------------------------------------------------------------------
  #
  # `do_assign_worked_tile/5` persists via a raw `Repo.update_all`, which
  # bypasses `City.changeset/2`'s own `validate_worked_tiles_within_size/1`
  # guard entirely — so `validate_assign/4` has to enforce the "never
  # exceed size" invariant itself for a `to_tile` with no paired
  # `from_tile` (a pure reassignment, `from_tile` supplied, never grows
  # the count and stays allowed even at the cap).

  describe "assign_worked_tile/5 population cap (issue 7509c453)" do
    test "rejects an unpaired assign once the city already works as many tiles as its size" do
      world = WorldsFixtures.world_fixture(%{frequency: 8})
      user = UsersFixtures.user_fixture()
      {:ok, _player} = Game.join_world(world, user)

      [settler] = for u <- Game.player_units(world, user), u.type == :settler, do: u
      :ok = Game.found_city(world, user, settler.id)

      [city] = Game.player_cities(world, user)
      # A freshly founded (size-1) city already auto-assigns its founding
      # pop's one worked tile (story 880, criterion 7476) — already at cap.
      assert length(city.worked_tiles) == city.size

      spare = spare_workable_tile(world, city)

      refute is_nil(spare),
             "expected a second workable, unworked territory tile to attempt the exploit on"

      assert Game.assign_worked_tile(world, user, city.id, nil, spare) == {:error, :size_exceeded}

      [unchanged] = Game.player_cities(world, user)
      assert unchanged.worked_tiles == city.worked_tiles
      assert length(unchanged.worked_tiles) == unchanged.size

      WorldServer.restart(world)
    end

    test "a paired swap (from_tile + to_tile) still works at the population cap" do
      world = WorldsFixtures.world_fixture(%{frequency: 8})
      user = UsersFixtures.user_fixture()
      {:ok, _player} = Game.join_world(world, user)

      [settler] = for u <- Game.player_units(world, user), u.type == :settler, do: u
      :ok = Game.found_city(world, user, settler.id)

      [city] = Game.player_cities(world, user)
      assert length(city.worked_tiles) == city.size

      [old_tile | _] = city.worked_tiles
      spare = spare_workable_tile(world, city)
      refute is_nil(spare)

      assert Game.assign_worked_tile(world, user, city.id, old_tile, spare) == :ok

      [updated] = Game.player_cities(world, user)
      assert length(updated.worked_tiles) == city.size
      assert spare in updated.worked_tiles
      refute old_tile in updated.worked_tiles

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

      assert Game.set_research(world, user, :astronomy) == {:error, :invalid_tech}

      WorldServer.restart(world)
    end

    test "refuses a tech whose prerequisite isn't completed yet (Bronze Working needs Mining)" do
      world = WorldsFixtures.world_fixture()
      user = UsersFixtures.user_fixture()
      {:ok, _player} = Game.join_world(world, user)

      assert Game.set_research(world, user, :bronze_working) == {:error, :prereqs_not_met}
      assert Game.set_research(world, user, :writing) == {:error, :prereqs_not_met}

      WorldServer.restart(world)
    end

    test "selects Bronze Working once Mining is completed" do
      world = WorldsFixtures.world_fixture(%{frequency: 8})
      user = UsersFixtures.user_fixture()
      {:ok, _player} = Game.join_world(world, user)

      [settler] = for u <- Game.player_units(world, user), u.type == :settler, do: u
      :ok = Game.found_city(world, user, settler.id)

      :ok = Game.set_research(world, user, :mining)

      Enum.reduce_while(1..60, :ok, fn _, :ok ->
        if :mining in Game.player_research(world, user).completed_techs do
          {:halt, :ok}
        else
          :ok = Game.advance_turn(world)
          {:cont, :ok}
        end
      end)

      assert :mining in Game.player_research(world, user).completed_techs
      assert :ok = Game.set_research(world, user, :bronze_working)
      assert Game.player_research(world, user).current_research == :bronze_working

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
    # `hills_tile/1` picks the lowest-id land+hills tile in the whole
    # mesh — independent of where this player's own city/camps landed,
    # so it can end up within an ordinary wilderness camp's roam/hunt
    # reach (story 892/893) purely by chance. Neither test here ever
    # moves or defends the worker it plants there, so a roaming
    # barbarian killing it mid-build (measured: it does, intermittently)
    # fails the assertion for a reason that has nothing to do with
    # mine-duration math — the same class of incidental interference
    # `BrokenOathsSpex.SharedGivens.clear_all_camps/1` and this story's
    # own spex (`Fixtures.isolate_camp/2`) already guard against.
    # `Game.isolate_camp_for_test/2` with an id no real camp can match
    # tears every camp down the same way.
    test "a mine takes the base 5 turns without Mining researched" do
      world = WorldsFixtures.world_fixture(%{seed: 33, frequency: 8})
      user = UsersFixtures.user_fixture()
      {:ok, player} = Game.join_world(world, user)

      [settler] = for u <- Game.player_units(world, user), u.type == :settler, do: u
      :ok = Game.found_city(world, user, settler.id)
      :ok = Game.isolate_camp_for_test(world, -1)

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
      :ok = Game.isolate_camp_for_test(world, -1)

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

  # QA issue 1c47edff "Granary confusion" — `has_granary` never reached
  # `Game.player_cities/2`'s map at all, so the built Granary had no way
  # to surface anywhere in the UI even though it was already banking its
  # food bonus (`Yields.accrue_food/3` reads the flag straight off the
  # DB-backed city, never through this map).
  describe "player_cities/2 surfaces a completed Granary" do
    test "has_granary: true reaches the city map once the Granary finishes building" do
      world = WorldsFixtures.world_fixture(%{seed: 33, frequency: 8})
      user = UsersFixtures.user_fixture()
      {:ok, _player} = Game.join_world(world, user)

      [settler] = for u <- Game.player_units(world, user), u.type == :settler, do: u
      :ok = Game.found_city(world, user, settler.id)
      [city] = Game.player_cities(world, user)
      refute city.has_granary

      :ok = Game.set_research(world, user, :pottery)
      complete_current_research(world, user)
      assert :pottery in Game.player_research(world, user).completed_techs

      :ok = Game.queue_production(world, user, city.id, "granary")

      Enum.reduce_while(1..120, :ok, fn _, :ok ->
        [c] = for c <- Game.player_cities(world, user), c.id == city.id, do: c

        if c.has_granary do
          {:halt, :ok}
        else
          :ok = Game.advance_turn(world)
          {:cont, :ok}
        end
      end)

      [built_city] = for c <- Game.player_cities(world, user), c.id == city.id, do: c
      assert built_city.has_granary

      WorldServer.restart(world)
    end
  end

  # QA issue 2ff5bd1a "roads not visible on map" — the fix lives
  # entirely in the client's sprite manifest (`assets/js/globe_render.js`,
  # see `SpriteManifestTest`); this confirms the server-side data path a
  # completed road relies on already carries `kind: :road` through to
  # `improvements_visible_to/2`, the exact field the board's improvement
  # billboard loop keys its sprite lookup off.
  describe "a completed road" do
    test "reaches :complete and is visible with kind: :road" do
      world = WorldsFixtures.world_fixture(%{seed: 33, frequency: 8})
      user = UsersFixtures.user_fixture()
      {:ok, player} = Game.join_world(world, user)

      [settler] = for u <- Game.player_units(world, user), u.type == :settler, do: u
      :ok = Game.found_city(world, user, settler.id)

      hills_tile = hills_tile(world)
      worker = Game.spawn_unit_for_test(world, player.id, :worker, hills_tile)
      :ok = Game.start_improvement(world, user, worker.id, "road")

      for _ <- 1..Improvement.duration(:road), do: :ok = Game.advance_turn(world)

      assert Enum.any?(
               Game.improvements_visible_to(world, user),
               &(&1.tile_id == hills_tile and &1.kind == :road and &1.status == :complete)
             )

      WorldServer.restart(world)
    end
  end

  # QA issue 8aa2c571 — a worker mid-dig had no way to back out of it.
  describe "cancel_improvement/3" do
    test "deletes the in-progress build outright, freeing the tile for a different kind" do
      world = WorldsFixtures.world_fixture(%{seed: 33, frequency: 8})
      user = UsersFixtures.user_fixture()
      {:ok, player} = Game.join_world(world, user)

      [settler] = for u <- Game.player_units(world, user), u.type == :settler, do: u
      :ok = Game.found_city(world, user, settler.id)

      hills_tile = hills_tile(world)
      worker = Game.spawn_unit_for_test(world, player.id, :worker, hills_tile)
      :ok = Game.start_improvement(world, user, worker.id, "mine")
      :ok = Game.advance_turn(world)

      assert Enum.any?(
               Game.improvements_visible_to(world, user),
               &(&1.tile_id == hills_tile and &1.status == :building and &1.kind == :mine)
             )

      :ok = Game.cancel_improvement(world, user, worker.id)

      refute Enum.any?(Game.improvements_visible_to(world, user), &(&1.tile_id == hills_tile))

      # Free for a DIFFERENT kind entirely on the very next call — proof
      # the row was deleted, not merely paused the way walking away
      # already freezes it (`validate_improvement_slot/3` would have
      # refused a mismatched kind on a merely-paused `:building` row).
      :ok = Game.start_improvement(world, user, worker.id, "road")

      assert Enum.any?(
               Game.improvements_visible_to(world, user),
               &(&1.tile_id == hills_tile and &1.kind == :road)
             )

      WorldServer.restart(world)
    end

    test "refuses when the worker's tile has no build in progress" do
      world = WorldsFixtures.world_fixture(%{seed: 33, frequency: 8})
      user = UsersFixtures.user_fixture()
      {:ok, player} = Game.join_world(world, user)

      [settler] = for u <- Game.player_units(world, user), u.type == :settler, do: u
      :ok = Game.found_city(world, user, settler.id)

      hills_tile = hills_tile(world)
      worker = Game.spawn_unit_for_test(world, player.id, :worker, hills_tile)

      assert {:error, :no_active_build} = Game.cancel_improvement(world, user, worker.id)

      WorldServer.restart(world)
    end

    test "refuses a unit the caller doesn't own" do
      world = WorldsFixtures.world_fixture(%{seed: 33, frequency: 8})
      user = UsersFixtures.user_fixture()
      other_user = UsersFixtures.user_fixture()
      {:ok, player} = Game.join_world(world, user)
      {:ok, _other_player} = Game.join_world(world, other_user)

      [settler] = for u <- Game.player_units(world, user), u.type == :settler, do: u
      :ok = Game.found_city(world, user, settler.id)

      hills_tile = hills_tile(world)
      worker = Game.spawn_unit_for_test(world, player.id, :worker, hills_tile)
      :ok = Game.start_improvement(world, user, worker.id, "mine")

      assert {:error, :not_owner} = Game.cancel_improvement(world, other_user, worker.id)

      WorldServer.restart(world)
    end
  end

  # Story 882 playtest update (issue 1caa87e9 — worker build charges):
  # a worker is created with 3 build charges, spends one per completed
  # Farm/Mine, is expended on its last one, and Roads are charge-exempt.
  # The end-to-end version of what `Turn`'s own unit tests already cover
  # in isolation — driven through `start_improvement/4`/`advance_turn/1`
  # for real, same style as the mine-duration describe block above.
  describe "worker build charges (issue 1caa87e9)" do
    test "a worker with 3 charges builds three Farms then is expended" do
      world = WorldsFixtures.world_fixture(%{seed: 33, frequency: 8})
      user = UsersFixtures.user_fixture()
      {:ok, player} = Game.join_world(world, user)

      [settler] = for u <- Game.player_units(world, user), u.type == :settler, do: u
      :ok = Game.found_city(world, user, settler.id)
      :ok = Game.isolate_camp_for_test(world, -1)

      [tile_a, tile_b, tile_c] = farmable_tiles(world, 3)

      worker = Game.spawn_unit_for_test(world, player.id, :worker, tile_a)
      assert worker.charges == 3

      :ok = Game.start_improvement(world, user, worker.id, "farm")
      for _ <- 1..Improvement.duration(:farm), do: :ok = Game.advance_turn(world)
      assert improvement_complete?(world, user, tile_a)
      assert fetch_charges(world, user, worker.id) == 2

      :ok = Game.relocate_unit_for_test(world, worker.id, tile_b)
      :ok = Game.start_improvement(world, user, worker.id, "farm")
      for _ <- 1..Improvement.duration(:farm), do: :ok = Game.advance_turn(world)
      assert improvement_complete?(world, user, tile_b)
      assert fetch_charges(world, user, worker.id) == 1

      :ok = Game.relocate_unit_for_test(world, worker.id, tile_c)
      :ok = Game.start_improvement(world, user, worker.id, "farm")
      for _ <- 1..Improvement.duration(:farm), do: :ok = Game.advance_turn(world)
      assert improvement_complete?(world, user, tile_c)

      # Expended: gone from the live roster AND swept from the DB, the
      # same removal path a combat death already takes.
      refute Enum.any?(Game.player_units(world, user), &(&1.id == worker.id))
      refute Repo.get(Unit, worker.id)

      # All three Farms remain and still feed the city's yields — the
      # worker's own expiry never un-does the improvements it built.
      assert improvement_complete?(world, user, tile_a)
      assert improvement_complete?(world, user, tile_b)
      assert improvement_complete?(world, user, tile_c)

      WorldServer.restart(world)
    end

    test "Roads never spend a build charge" do
      world = WorldsFixtures.world_fixture(%{seed: 33, frequency: 8})
      user = UsersFixtures.user_fixture()
      {:ok, player} = Game.join_world(world, user)

      [settler] = for u <- Game.player_units(world, user), u.type == :settler, do: u
      :ok = Game.found_city(world, user, settler.id)
      :ok = Game.isolate_camp_for_test(world, -1)

      hills_tile = hills_tile(world)
      worker = Game.spawn_unit_for_test(world, player.id, :worker, hills_tile)
      :ok = Game.start_improvement(world, user, worker.id, "road")

      for _ <- 1..Improvement.duration(:road), do: :ok = Game.advance_turn(world)

      assert improvement_complete?(world, user, hills_tile)
      assert fetch_charges(world, user, worker.id) == 3
      assert Enum.any?(Game.player_units(world, user), &(&1.id == worker.id))

      WorldServer.restart(world)
    end

    test "an abandoned dig costs no charge" do
      world = WorldsFixtures.world_fixture(%{seed: 33, frequency: 8})
      user = UsersFixtures.user_fixture()
      {:ok, player} = Game.join_world(world, user)

      [settler] = for u <- Game.player_units(world, user), u.type == :settler, do: u
      :ok = Game.found_city(world, user, settler.id)
      :ok = Game.isolate_camp_for_test(world, -1)

      hills_tile = hills_tile(world)
      worker = Game.spawn_unit_for_test(world, player.id, :worker, hills_tile)
      :ok = Game.start_improvement(world, user, worker.id, "mine")
      :ok = Game.advance_turn(world)

      :ok = Game.cancel_improvement(world, user, worker.id)

      assert fetch_charges(world, user, worker.id) == 3
      assert Enum.any?(Game.player_units(world, user), &(&1.id == worker.id))

      WorldServer.restart(world)
    end
  end

  defp hills_tile(world) do
    land? = fn t -> BrokenOaths.Worlds.Regions.tile_class(world, t) == :land end

    Enum.find(0..641, fn t ->
      land?.(t) and BrokenOaths.Worlds.Regions.terrain(world, t).relief == :hills
    end)
  end

  # `count` distinct flat, featureless grassland/plains tiles — legal
  # Farm ground (`Improvement.allowed?/2`) — for scenarios that need to
  # walk a worker between more than one build site.
  defp farmable_tiles(world, count) do
    land? = fn t -> BrokenOaths.Worlds.Regions.tile_class(world, t) == :land end

    0..641
    |> Enum.filter(fn t ->
      land?.(t) and Improvement.allowed?(:farm, BrokenOaths.Worlds.Regions.terrain(world, t))
    end)
    |> Enum.take(count)
  end

  defp fetch_charges(world, user, unit_id) do
    %{charges: charges} = Enum.find(Game.player_units(world, user), &(&1.id == unit_id))
    charges
  end

  # A territory tile that isn't the city center, isn't already worked,
  # and is legal to work — the same "assignable" gate
  # `BrokenOathsWeb.GameLive.Play`'s own `assign_worked_tile` handler
  # relies on (it never checks remaining population itself; that's
  # `validate_assign/4`'s job, per issue 7509c453).
  defp spare_workable_tile(world, city) do
    Enum.find(city.territory -- [city.tile_id | city.worked_tiles], fn tile_id ->
      Yields.workable?(Regions.terrain(world, tile_id))
    end)
  end

  defp improvement_complete?(world, user, tile_id) do
    Enum.any?(
      Game.improvements_visible_to(world, user),
      &(&1.tile_id == tile_id and &1.status == :complete)
    )
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
