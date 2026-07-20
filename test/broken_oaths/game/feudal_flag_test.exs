defmodule BrokenOaths.Game.FeudalFlagTest do
  @moduledoc """
  Proves the `config :broken_oaths, :feudal_enabled` shipping gate
  (main-is-deployable-with-feudal-dormant enabler): the in-progress
  feudal PvP batch (Siege player-city capture — story 906,
  Vassalization — story 907, Tribute — story 908, Gold Bank — story
  909, Feudal Stewardship — story 910) is built and wired into
  `WorldServer`, but still missing its first-class QA/balance pass, so
  it must stay unreachable wherever this flag reads `false` (prod's own
  default) and fully functional wherever it reads `true` (dev/test's
  own default — see `config/dev.exs`/`config/test.exs`).

  Toggles `Application.put_env/3` directly (mirrors `config/test.exs`'s
  own note that this is "mirrored" dev config, not itself a compile-time
  gate like `:dev_routes`) and restores the original value via
  `on_exit/1` so this test never leaks into any test that runs after
  it.
  """

  # async: false — spawns a real, Registry-addressed `WorldServer`
  # GenServer per world, same status every other WorldServer-level test
  # in this suite (`world_server_test.exs`) already carries.
  use BrokenOathsTest.DataCase, async: false

  alias BrokenOaths.Game
  alias BrokenOaths.Feudal.Bank
  alias BrokenOaths.Game.WorldServer
  alias BrokenOaths.Cities.Yields
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.WorldsFixtures

  setup do
    original = Application.get_env(:broken_oaths, :feudal_enabled)
    on_exit(fn -> Application.put_env(:broken_oaths, :feudal_enabled, original) end)
    :ok
  end

  # Two real players, each with their own founded city, and `lord`'s
  # own fresh Warrior already standing on a land tile adjacent to
  # `rival`'s city — spawned directly (`spawn_unit_for_test/4`) rather
  # than marched, since this test only needs ONE immediate "attack"
  # order, not a multi-turn grind (that's `SharedGivens.grind_city/6`'s
  # own job, already exercised by the 906/907/908 spex suites this
  # gate leaves untouched).
  defp lord_adjacent_to_rival_city(world) do
    lord = UsersFixtures.user_fixture()
    rival = UsersFixtures.user_fixture()

    {:ok, lord_player} = Game.join_world(world, lord)
    {:ok, _rival_player} = Game.join_world(world, rival)

    [lord_settler | _] = for u <- Game.player_units(world, lord), u.type == :settler, do: u
    [rival_settler | _] = for u <- Game.player_units(world, rival), u.type == :settler, do: u

    :ok = Game.found_city(world, lord, lord_settler.id)
    :ok = Game.found_city(world, rival, rival_settler.id)

    [rival_city] = Game.player_cities(world, rival)

    [attacker_tile | _] =
      world
      |> Regions.adjacent_tiles(rival_city.tile_id)
      |> Enum.filter(&(Regions.tile_class(world, &1) == :land))

    attacker = Game.spawn_unit_for_test(world, lord_player.id, :warrior, attacker_tile)

    %{lord: lord, rival: rival, rival_city: rival_city, attacker: attacker}
  end

  describe "feudal_enabled?/0" do
    test "reads the config flag, defaulting to false when unset" do
      Application.delete_env(:broken_oaths, :feudal_enabled)
      refute Game.feudal_enabled?()

      Application.put_env(:broken_oaths, :feudal_enabled, false)
      refute Game.feudal_enabled?()

      Application.put_env(:broken_oaths, :feudal_enabled, true)
      assert Game.feudal_enabled?()
    end
  end

  describe "attack_city/4 (the Siege entry point), with the flag OFF" do
    test "refuses PvP city assault outright — no capture, no vassalage, no tribute" do
      Application.put_env(:broken_oaths, :feudal_enabled, false)

      world = WorldsFixtures.world_fixture(%{seed: 424_242})

      %{lord: lord, rival: rival, rival_city: rival_city, attacker: attacker} =
        lord_adjacent_to_rival_city(world)

      # Restored, pre-906 "no Stone Age PvP" rejection — same reason
      # (and same player-facing copy, via `combat_error_message/1`)
      # unit-vs-unit combat already uses for two real players.
      assert Game.attack_city(world, lord, attacker.id, rival_city.id) == {:error, :not_hostile}

      # No damage landed, no capture.
      [unchanged] = for c <- Game.player_cities(world, rival), c.id == rival_city.id, do: c
      assert unchanged.hp == rival_city.hp
      assert Map.get(unchanged, :occupied_by_player_id) == nil

      # A turn boundary's own `apply_captures/1`/`apply_tribute/1`
      # hooks stay no-ops too — no vassalage, no tribute, even after a
      # real tick runs.
      :ok = Game.advance_turn(world)

      assert Game.vassals(world, lord) == []
      assert Game.vassal_status(world, rival) == nil

      WorldServer.restart(world)
    end
  end

  describe "attack_city/4 (the Siege entry point), with the flag ON" do
    test "the full feudal flow's own entry point works — the attack lands" do
      Application.put_env(:broken_oaths, :feudal_enabled, true)

      world = WorldsFixtures.world_fixture(%{seed: 424_242})

      %{lord: lord, rival_city: rival_city, attacker: attacker} =
        lord_adjacent_to_rival_city(world)

      assert {:ok, %{damage_dealt: dealt}} =
               Game.attack_city(world, lord, attacker.id, rival_city.id)

      assert dealt > 0

      WorldServer.restart(world)
    end
  end

  describe "Bank/Stewardship (stories 909/910), with the flag OFF" do
    test "no banking on the turn tick, no collect/upgrade/steward commands — gold stays exactly as it does today" do
      Application.put_env(:broken_oaths, :feudal_enabled, false)

      world = WorldsFixtures.world_fixture(%{seed: 424_242})

      lord = UsersFixtures.user_fixture()
      vassal = UsersFixtures.user_fixture()

      {:ok, _lord_player} = Game.join_world(world, lord)
      {:ok, _vassal_player} = Game.join_world(world, vassal)

      # Story 912: give the vassal a REAL, positive per-turn city gold
      # income (`Yields.city_gold_income/2`), not the test-only
      # `:set_player_gold_income_for_test` seam — `apply_bank/1` no
      # longer reads that seam at all (see its own moduledoc), so this
      # is the real regression guard the flag-off path needs now that
      # every founded city legitimately earns gold every turn: prod's
      # own gold economy must stay untouched regardless.
      [settler | _] = for u <- Game.player_units(world, vassal), u.type == :settler, do: u
      :ok = Game.found_city(world, vassal, settler.id)
      [vassal_city] = Game.player_cities(world, vassal)
      assert Yields.city_gold_income(vassal_city, world) > 0

      gold_before = Game.gold(world, vassal)

      # A real tick, with the vassal's own REAL positive gold income,
      # must move NOTHING — `apply_bank/1`'s own gate. Prod's own
      # barbarian/normal gold economy (bounty kills, camp-destroy
      # rewards — the only things that ever move `gold` today) is
      # unaffected either way.
      :ok = Game.advance_turn(world)

      assert Game.gold(world, vassal) == gold_before
      assert Game.bank(world, vassal) == %{gold: 0, cap: Bank.starting_cap()}

      # Every direct Bank/Stewardship command is refused outright too —
      # `ensure_feudal_enabled/0`/`fetch_steward_context/3`'s own gate.
      assert Game.collect_bank(world, vassal) == {:error, :feudal_disabled}
      assert Game.upgrade_bank(world, vassal) == {:error, :feudal_disabled}
      assert Game.steward_collect_bank(world, lord, vassal.id) == {:error, :feudal_disabled}

      assert Game.gold(world, vassal) == gold_before
      assert Game.honor(world, vassal) == 100
      assert Game.steward_log(world, vassal) == []

      WorldServer.restart(world)
    end
  end

  describe "Bank/Stewardship (stories 909/910), with the flag ON" do
    test "the turn tick banks offline earnings, and collect/upgrade actually work" do
      Application.put_env(:broken_oaths, :feudal_enabled, true)

      world = WorldsFixtures.world_fixture(%{seed: 424_242})

      player = UsersFixtures.user_fixture()
      {:ok, _player} = Game.join_world(world, player)

      # Story 912: a REAL founded city, taxed via its own REAL per-turn
      # gold income (`Yields.city_gold_income/2`) — `apply_bank/1` sums
      # this itself every boundary (`WorldServer.gold_income_by_player/1`)
      # and no longer reads the test-only `:set_player_gold_income_for_test`
      # seam this test used to declare an income through at all.
      [settler | _] = for u <- Game.player_units(world, player), u.type == :settler, do: u
      :ok = Game.found_city(world, player, settler.id)
      [city] = Game.player_cities(world, player)
      income = Yields.city_gold_income(city, world)
      assert income > 0

      # Never connected via `GameLive.Play` at all in this bare-`Game`-call
      # test, so `Presence.online?/2` reads false for this user the whole
      # time — the same "offline" signal `SharedGivens.go_offline/1`
      # gives a real LiveView connection.
      :ok = Game.advance_turn(world)

      assert Game.bank(world, player) == %{gold: income, cap: Bank.starting_cap()}

      gold_before = Game.gold(world, player)
      assert Game.collect_bank(world, player) == :ok
      assert Game.gold(world, player) == gold_before + income
      assert Game.bank(world, player) == %{gold: 0, cap: Bank.starting_cap()}

      WorldServer.restart(world)
    end
  end
end
