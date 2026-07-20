defmodule BrokenOathsWeb.GameLive.FeudalCaptureUITest do
  @moduledoc """
  Real client-facing UI coverage for the "the backend is fine, nothing
  reaches it" QA batch:

    * 56ee521a — no UI to attack an enemy city (`game:cities` now
      carries fog-filtered hostile cities; `UnitPanel` renders a real
      "Attack" button per adjacent one).
    * 34d30fca — vassalization unreachable (a consequence of 56ee521a;
      this file drives a REAL capture through the new Attack button and
      confirms the Oath screen renders on the defeated side).
    * ffa66192 — no UI for the execute/release garrison-fate choice
      (the new "Captured Cities" dropdown).
    * ed1ff4c0 — execute/release applies no Honor delta (confirmed via
      the real UI button, complementing `BrokenOaths.Game.
      GarrisonFateIntegrationTest`'s own direct-`Game`-call coverage).
    * dae2e65d — no UI to issue/answer/refuse a call to arms (the
      vassals panel's new "Call to Arms" form and the vassal's own
      Answer/Refuse buttons).

  Every check against a LiveView's OWN rendered state re-mounts a fresh
  connection right before reading it (`live/2`, not a stale handle) —
  a fresh mount's own `mount/3` synchronously calls `refresh_board/1`
  before it ever replies, so its FIRST render is guaranteed current.
  Reading straight off `BrokenOaths.Game` (raw backend state) is
  preferred wherever it's just as good a signal — the same "don't
  trust a live socket's own timing, read the ground truth" posture
  `BrokenOathsSpex.SharedGivens.march_to/6` already established.

  `BrokenOathsWeb.GameLive.FeudalFlagTest` already covers the
  flag-off/flag-on gate itself; every test here runs with the flag ON.
  """

  # async: false — mounts several real `GameLive.Play` LiveViews
  # sharing one `WorldServer`, same status `FeudalFlagTest`/`PlayTest`
  # already carry.
  use BrokenOathsTest.ConnCase, async: false

  import Phoenix.LiveViewTest
  import BrokenOaths.WorldsFixtures

  alias BrokenOaths.Game
  alias BrokenOaths.Feudal.Tribute
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.Worlds.Regions

  setup :register_and_log_in_user

  setup %{conn: conn} do
    other_user = UsersFixtures.user_fixture()
    other_conn = log_in_user(build_conn(), other_user)

    original = Application.get_env(:broken_oaths, :feudal_enabled)
    Application.put_env(:broken_oaths, :feudal_enabled, true)
    on_exit(fn -> Application.put_env(:broken_oaths, :feudal_enabled, original) end)

    {:ok,
     conn: conn,
     world: world_fixture(%{seed: 424_242, frequency: 8}),
     other_user: other_user,
     other_conn: other_conn}
  end

  defp join_and_mount(conn, world) do
    {:ok, join_live, _html} = live(conn, ~p"/play")

    join_live
    |> element("[data-test='join-world-#{world.id}']")
    |> render_click()

    {:ok, play_live, _html} = live(conn, ~p"/play/#{world.id}")
    play_live
  end

  defp found_city(play_live, world, user) do
    [settler | _] = for u <- Game.player_units(world, user), u.type == :settler, do: u
    render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
    [city] = Game.player_cities(world, user)
    city
  end

  defp adjacent_land_tile(world, target_tile_id) do
    [tile | _] =
      world
      |> Regions.adjacent_tiles(target_tile_id)
      |> Enum.filter(&(Regions.tile_class(world, &1) == :land))

    tile
  end

  # A fresh warrior for `owner`, placed directly adjacent to
  # `rival_city` — mirrors `FeudalFlagTest`'s own `lord_warrior_adjacent_to/3`.
  defp warrior_adjacent_to(world, owner, rival_city) do
    {:ok, owner_player} = Game.join_world(world, owner)
    tile = adjacent_land_tile(world, rival_city.tile_id)
    Game.spawn_unit_for_test(world, owner_player.id, :warrior, tile)
  end

  # Repeatedly re-mounts `conn`'s own board (see this module's own
  # moduledoc for why: a fresh mount's `attackable_cities` is always
  # current, sidestepping any live-socket broadcast-ordering race) and
  # clicks the REAL "Attack <city>" button `UnitPanel` now renders,
  # advancing a real turn boundary between swings — same cadence
  # `BrokenOathsSpex.SharedGivens.grind_city/6` already establishes for
  # the direct-hook version. Returns the freshest city row once broken
  # (or after `max_attacks` swings).
  defp grind_via_attack_button(conn, world, attacker, defender_user, city, max_attacks \\ 40) do
    Enum.reduce_while(1..max_attacks, city, fn _, current ->
      if current.hp <= 0 do
        {:halt, current}
      else
        {:ok, play_live, _html} = live(conn, ~p"/play/#{world.id}")
        render_hook(play_live, "select_unit", %{"unit_id" => to_string(attacker.id)})

        play_live
        |> element("[data-test='attack-city-#{current.id}']")
        |> render_click()

        Game.advance_turn(world)
        [refreshed] = for c <- Game.player_cities(world, defender_user), c.id == current.id, do: c
        {:cont, refreshed}
      end
    end)
  end

  describe "game:cities (QA issue 56ee521a)" do
    test "a hostile enemy city is included, fog-filtered, once the attacker can see it", %{
      conn: conn,
      user: user,
      other_conn: other_conn,
      other_user: other_user,
      world: world
    } do
      other_play_live = join_and_mount(other_conn, world)
      play_live = join_and_mount(conn, world)

      rival_city = found_city(other_play_live, world, other_user)
      _my_city = found_city(play_live, world, user)

      # QA batch tests: a real, many-turn siege (`grind_via_attack_button/6`)
      # plus the levy tests' own discovery-scouting boundary are both
      # exposed to story 892/893's real barbarian AI for many real turn
      # boundaries — the same "no camps at all" interference `Shared
      # Givens.clear_all_camps/1` already guards feudal spex scenarios
      # against (a roaming barbarian killing an untracked unit, like the
      # third player's own starting Settler, would fail this test for a
      # reason that has nothing to do with the UI under test).
      :ok = Game.isolate_camp_for_test(world, -1)

      # Before the attacker's own region/exploration ever reaches the
      # rival city's tile, it must never appear — own cities only.
      {:ok, fresh_before, _html} = live(conn, ~p"/play/#{world.id}")
      assert_push_event(fresh_before, "game:cities", %{cities: cities_before}, 500)
      refute Enum.any?(cities_before, &(&1.id == rival_city.id))

      _attacker = warrior_adjacent_to(world, user, rival_city)
      Game.advance_turn(world)

      {:ok, fresh_after, _html} = live(conn, ~p"/play/#{world.id}")
      assert_push_event(fresh_after, "game:cities", %{cities: cities_after}, 500)
      hostile = Enum.find(cities_after, &(&1.id == rival_city.id))

      assert hostile
      assert hostile.hostile == true
      assert hostile.tile_id == rival_city.tile_id

      # And it never appears on the DEFENDER's own board as hostile —
      # `game:cities` still reports their OWN city as `hostile: false`.
      {:ok, fresh_other, _html} = live(other_conn, ~p"/play/#{world.id}")
      assert_push_event(fresh_other, "game:cities", %{cities: own_cities}, 500)
      own = Enum.find(own_cities, &(&1.id == rival_city.id))
      assert own.hostile == false
    end
  end

  describe "the Attack button + capture reaches vassalization (QA issues 56ee521a, 34d30fca)" do
    test "clicking the Attack button breaks and captures a rival's only city, and the Oath screen renders",
         %{
           conn: conn,
           user: user,
           other_conn: other_conn,
           other_user: other_user,
           world: world
         } do
      other_play_live = join_and_mount(other_conn, world)
      play_live = join_and_mount(conn, world)

      rival_city = found_city(other_play_live, world, other_user)
      _my_city = found_city(play_live, world, user)

      # QA batch tests: a real, many-turn siege (`grind_via_attack_button/6`)
      # plus the levy tests' own discovery-scouting boundary are both
      # exposed to story 892/893's real barbarian AI for many real turn
      # boundaries — the same "no camps at all" interference `Shared
      # Givens.clear_all_camps/1` already guards feudal spex scenarios
      # against (a roaming barbarian killing an untracked unit, like the
      # third player's own starting Settler, would fail this test for a
      # reason that has nothing to do with the UI under test).
      :ok = Game.isolate_camp_for_test(world, -1)

      attacker = warrior_adjacent_to(world, user, rival_city)
      Game.advance_turn(world)

      {:ok, fresh_play_live, _html} = live(conn, ~p"/play/#{world.id}")
      render_hook(fresh_play_live, "select_unit", %{"unit_id" => to_string(attacker.id)})

      html = render(fresh_play_live)
      assert html =~ ~s(data-test="attack-city-#{rival_city.id}")
      assert html =~ "Attack #{rival_city.name}"

      broken_city = grind_via_attack_button(conn, world, attacker, other_user, rival_city)
      assert broken_city.hp == 0

      {:ok, march_live, _html} = live(conn, ~p"/play/#{world.id}")

      render_hook(march_live, "queue_move", %{
        "unit_id" => to_string(attacker.id),
        "to_tile" => rival_city.tile_id
      })

      Game.advance_turn(world)

      [moved_attacker] = for u <- Game.player_units(world, user), u.id == attacker.id, do: u
      assert moved_attacker.tile_id == rival_city.tile_id

      # The Captured Cities dropdown shows it, secured (no garrison was
      # ever left standing — the attacker walked into an EMPTY tile).
      {:ok, captured_view, _html} = live(conn, ~p"/play/#{world.id}")
      html = render(captured_view)
      assert html =~ ~s(data-test="captured-cities-panel")
      assert html =~ ~s(data-test="captured-city-#{rival_city.id}")
      refute html =~ ~s(data-test="execute-garrison-#{rival_city.id}")

      # QA issue 34d30fca — the defender's ONLY city just fell: the
      # Oath screen must render on THEIR own board, reached entirely
      # through the new Attack button + the pre-existing queue_move,
      # never `attempt_event`.
      {:ok, fresh_other_live, _html} = live(other_conn, ~p"/play/#{world.id}")
      assert has_element?(fresh_other_live, "[data-test='oath-screen']")
    end
  end

  describe "broken city -> Move In captures it, through real UI controls (QA issue 7f91cff2)" do
    test "once a hostile city is broken, the panel swaps Attack for Move In, and clicking it occupies the tile",
         %{
           conn: conn,
           user: user,
           other_conn: other_conn,
           other_user: other_user,
           world: world
         } do
      other_play_live = join_and_mount(other_conn, world)
      play_live = join_and_mount(conn, world)

      rival_city = found_city(other_play_live, world, other_user)
      _my_city = found_city(play_live, world, user)

      # Same barbarian-interference guard the sibling capture test above
      # uses (`Shared Givens.clear_all_camps/1`'s own rationale).
      :ok = Game.isolate_camp_for_test(world, -1)

      attacker = warrior_adjacent_to(world, user, rival_city)
      Game.advance_turn(world)

      broken_city = grind_via_attack_button(conn, world, attacker, other_user, rival_city)
      assert broken_city.hp == 0

      # QA issue 7f91cff2 — `game:cities` now carries the broken state,
      # and a fresh mount's own board push reflects it immediately.
      {:ok, board_check, _html} = live(conn, ~p"/play/#{world.id}")
      assert_push_event(board_check, "game:cities", %{cities: cities}, 500)
      hostile = Enum.find(cities, &(&1.id == rival_city.id))
      assert hostile.hostile == true
      assert hostile.broken == true
      assert hostile.hp == 0

      # The discoverable button itself: once broken, "Attack" is gone
      # and "Move In" takes its place — the real client-facing
      # affordance this issue was filed over never existing.
      {:ok, fresh_play_live, _html} = live(conn, ~p"/play/#{world.id}")
      render_hook(fresh_play_live, "select_unit", %{"unit_id" => to_string(attacker.id)})

      html = render(fresh_play_live)
      refute html =~ ~s(data-test="attack-city-#{rival_city.id}")
      assert html =~ ~s(data-test="move-in-city-#{rival_city.id}")
      assert html =~ "Move In #{rival_city.name}"

      # Click it for real — no raw `queue_move`/`to_tile` render_hook
      # workaround, exactly the button a genuine player would reach.
      fresh_play_live
      |> element("[data-test='move-in-city-#{rival_city.id}']")
      |> render_click()

      Game.advance_turn(world)

      [moved_attacker] = for u <- Game.player_units(world, user), u.id == attacker.id, do: u
      assert moved_attacker.tile_id == rival_city.tile_id

      captured = Game.captured_cities_visible_to(world, user)
      assert Enum.any?(captured, &(&1.id == rival_city.id))
    end
  end

  describe "Captured Cities panel — Execute/Release (QA issues ffa66192, ed1ff4c0)" do
    test "presents Execute/Release for a fallen garrison, and Execute costs Honor via the real button",
         %{
           conn: conn,
           user: user,
           other_conn: other_conn,
           other_user: other_user,
           world: world
         } do
      other_play_live = join_and_mount(other_conn, world)
      play_live = join_and_mount(conn, world)

      rival_city = found_city(other_play_live, world, other_user)
      _my_city = found_city(play_live, world, user)

      # QA batch tests: a real, many-turn siege (`grind_via_attack_button/6`)
      # plus the levy tests' own discovery-scouting boundary are both
      # exposed to story 892/893's real barbarian AI for many real turn
      # boundaries — the same "no camps at all" interference `Shared
      # Givens.clear_all_camps/1` already guards feudal spex scenarios
      # against (a roaming barbarian killing an untracked unit, like the
      # third player's own starting Settler, would fail this test for a
      # reason that has nothing to do with the UI under test).
      :ok = Game.isolate_camp_for_test(world, -1)

      attacker = warrior_adjacent_to(world, user, rival_city)
      Game.advance_turn(world)

      broken_city = grind_via_attack_button(conn, world, attacker, other_user, rival_city)
      assert broken_city.hp == 0

      {:ok, march_live, _html} = live(conn, ~p"/play/#{world.id}")

      render_hook(march_live, "queue_move", %{
        "unit_id" => to_string(attacker.id),
        "to_tile" => rival_city.tile_id
      })

      Game.advance_turn(world)

      {:ok, other_player} = Game.join_world(world, other_user)
      garrison = Game.spawn_unit_for_test(world, other_player.id, :warrior, rival_city.tile_id)

      {:ok, play_live, _html} = live(conn, ~p"/play/#{world.id}")

      assert has_element?(play_live, "[data-test='captured-city-#{rival_city.id}']")
      assert has_element?(play_live, "[data-test='fallen-garrison-choice']")

      assert Game.honor(world, user) == 100

      play_live
      |> element("[data-test='execute-garrison-#{rival_city.id}']")
      |> render_click()

      attacker_units = Game.player_units(world, user)
      assert Enum.any?(attacker_units, &(&1.id == attacker.id))

      defender_units = Game.player_units(world, other_user)
      refute Enum.any?(defender_units, &(&1.id == garrison.id))

      assert Game.honor(world, user) == 98

      # Real client feedback: the fallen-garrison choice disappears once
      # resolved (a fresh mount's own `captured_cities_visible_to/2`
      # re-read reflects the already-persisted removal).
      {:ok, resolved_view, _html} = live(conn, ~p"/play/#{world.id}")
      refute has_element?(resolved_view, "[data-test='fallen-garrison-choice']")
    end
  end

  describe "Call to Arms — issue/answer/refuse (QA issue dae2e65d)" do
    # Frequency 9/seed 1 is the same 3-spawnable-region combination
    # `BrokenOathsSpex.Story908.Criterion7678Spex` already uses for its
    # own third, independently-joined target player — the default
    # `world` fixture (seed 424242/frequency 8) only ever carves out 2
    # spawnable regions (`world_full?` refuses a 3rd join against it).
    setup %{conn: conn, other_conn: other_conn, other_user: other_user, user: user} do
      world = world_fixture(%{seed: 1, frequency: 9})
      third_user = UsersFixtures.user_fixture()
      third_conn = log_in_user(build_conn(), third_user)

      {:ok, join_live, _html} = live(third_conn, ~p"/play")

      join_live
      |> element("[data-test='join-world-#{world.id}']")
      |> render_click()

      {:ok, _third_play_live, _html} = live(third_conn, ~p"/play/#{world.id}")

      other_play_live = join_and_mount(other_conn, world)
      play_live = join_and_mount(conn, world)

      rival_city = found_city(other_play_live, world, other_user)
      _my_city = found_city(play_live, world, user)

      # QA batch tests: a real, many-turn siege (`grind_via_attack_button/6`)
      # plus the levy tests' own discovery-scouting boundary are both
      # exposed to story 892/893's real barbarian AI for many real turn
      # boundaries — the same "no camps at all" interference `Shared
      # Givens.clear_all_camps/1` already guards feudal spex scenarios
      # against (a roaming barbarian killing an untracked unit, like the
      # third player's own starting Settler, would fail this test for a
      # reason that has nothing to do with the UI under test).
      :ok = Game.isolate_camp_for_test(world, -1)

      attacker = warrior_adjacent_to(world, user, rival_city)
      Game.advance_turn(world)

      broken_city = grind_via_attack_button(conn, world, attacker, other_user, rival_city)
      assert broken_city.hp == 0

      {:ok, march_live, _html} = live(conn, ~p"/play/#{world.id}")

      render_hook(march_live, "queue_move", %{
        "unit_id" => to_string(attacker.id),
        "to_tile" => rival_city.tile_id
      })

      Game.advance_turn(world)

      # `known_players/2` (story 899) gates the target dropdown, same
      # convention `AlliancePanel` already established — a fresh scout
      # unit marches straight onto the third player's own starting
      # tile so the mutual-discovery tick boundary fires for real,
      # then is cleaned up (its own presence isn't otherwise relevant).
      {:ok, lord_player} = Game.join_world(world, user)
      [third_start | _] = Game.player_units(world, third_user)
      scout = Game.spawn_unit_for_test(world, lord_player.id, :warrior, third_start.tile_id)
      Game.advance_turn(world)
      :ok = Game.remove_unit_for_test(world, scout.id)

      assert Enum.any?(Game.known_players(world, user), &(&1.user_id == third_user.id))

      {:ok, world: world, third_user: third_user}
    end

    test "the lord issues a call to arms, the vassal sees it and answers it, through real UI controls",
         %{conn: conn, other_conn: other_conn, other_user: other_user, world: world, third_user: third_user} do
      {:ok, lord_live, _html} = live(conn, ~p"/play/#{world.id}")

      html = render(lord_live)
      assert html =~ ~s(data-test="issue-levy-form-#{other_user.id}")

      lord_live
      |> element("[data-test='issue-levy-form-#{other_user.id}']")
      |> render_submit(%{"target_user_id" => to_string(third_user.id), "share" => "0.5"})

      {:ok, vassal_live, _html} = live(other_conn, ~p"/play/#{world.id}")
      html = render(vassal_live)

      assert html =~ ~s(data-test="vassal-status")
      assert html =~ ~s(data-test="answer-levy")
      assert html =~ ~s(data-test="refuse-levy")

      vassal_live
      |> element("[data-test='answer-levy']")
      |> render_click()

      html = render(vassal_live)
      refute html =~ ~s(data-test="answer-levy")
      refute html =~ ~s(data-test="refuse-levy")

      status = Game.vassal_status(world, other_user)
      assert status.levy_status == :answered
    end

    test "refusing a call to arms through the real Refuse button spikes Oath Strain and dings Honor",
         %{
           conn: conn,
           other_conn: other_conn,
           user: user,
           other_user: other_user,
           world: world,
           third_user: third_user
         } do
      {:ok, lord_live, _html} = live(conn, ~p"/play/#{world.id}")

      lord_live
      |> element("[data-test='issue-levy-form-#{other_user.id}']")
      |> render_submit(%{"target_user_id" => to_string(third_user.id), "share" => "0.5"})

      {:ok, vassal_live, _html} = live(other_conn, ~p"/play/#{world.id}")

      strain_before = Game.vassals(world, user) |> hd() |> Map.get(:oath_strain)
      # QA issue c0ec53ed — criterion 7678's "strain and Honor hits" was
      # only half-wired: only Oath Strain moved. This is the vassal's
      # OWN Honor, read straight off `Game.honor/2` before the refusal.
      honor_before = Game.honor(world, other_user)

      vassal_live
      |> element("[data-test='refuse-levy']")
      |> render_click()

      status = Game.vassal_status(world, other_user)
      assert status.levy_status == :refused

      strain_after = Game.vassals(world, user) |> hd() |> Map.get(:oath_strain)
      assert strain_after > strain_before

      honor_after = Game.honor(world, other_user)
      assert honor_after < honor_before
      assert honor_after == honor_before - Tribute.refusal_honor_penalty()
    end
  end
end
