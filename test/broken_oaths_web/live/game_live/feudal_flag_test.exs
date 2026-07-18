defmodule BrokenOathsWeb.GameLive.FeudalFlagTest do
  @moduledoc """
  Proves the `config :broken_oaths, :feudal_enabled` shipping gate at
  the LiveView surface: with the flag OFF, ordering an attack on a
  rival PLAYER's city is refused exactly like unit-vs-unit "no Stone
  Age PvP" (`combat-error` toast, `:not_hostile`,
  `BrokenOaths.Game.FeudalFlagTest` covers the same rejection at the
  `WorldServer` level), and the feudal UI (`vassals-list`,
  `vassal-status`, `oath-screen`, and stories 909/910's own `bank-gold`/
  `bank-cap`/`player-honor`/`steward-log`) never renders — nothing ever
  creates a `Vassalage` row to power the first three, and
  `GameLive.Play`'s own `@feudal_enabled?` assign gates the last four
  directly (they read STRUCTURAL `Player` fields that exist, at inert
  defaults, regardless of the flag — see `BrokenOaths.Game.
  Bank`/`BrokenOaths.Game.Stewardship`'s own moduledocs). With the flag
  ON, the same order lands (the deeper capture/vassalization/tribute
  flow itself stays the 906/907/908 spex suites' own job; the deeper
  Bank/Stewardship flow stays the 909/910 spex suites' own job).
  """

  # async: false — mounts two real `GameLive.Play` LiveViews, each
  # spawning/sharing the same `WorldServer` GenServer, same status
  # `PlayTest`'s own moduledoc documents.
  use BrokenOathsTest.ConnCase, async: false

  import Phoenix.LiveViewTest
  import BrokenOaths.WorldsFixtures

  alias BrokenOaths.Game
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.Worlds.Regions

  setup :register_and_log_in_user

  setup %{conn: conn} do
    other_user = UsersFixtures.user_fixture()
    other_conn = log_in_user(build_conn(), other_user)

    original = Application.get_env(:broken_oaths, :feudal_enabled)
    on_exit(fn -> Application.put_env(:broken_oaths, :feudal_enabled, original) end)

    {:ok,
     conn: conn,
     world: world_fixture(%{seed: 424_242}),
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

  # `lord`'s own fresh Warrior, spawned directly onto a land tile
  # adjacent to `rival_city` — mirrors `FeudalFlagTest`'s own
  # `lord_adjacent_to_rival_city/1`, just driven through two mounted
  # `GameLive.Play` views instead of bare `Game` calls.
  defp lord_warrior_adjacent_to(world, lord, rival_city) do
    {:ok, lord_player} = Game.join_world(world, lord)

    [attacker_tile | _] =
      world
      |> Regions.adjacent_tiles(rival_city.tile_id)
      |> Enum.filter(&(Regions.tile_class(world, &1) == :land))

    Game.spawn_unit_for_test(world, lord_player.id, :warrior, attacker_tile)
  end

  describe "with the flag OFF" do
    test "attacking a rival's city is refused, and no feudal UI ever renders", %{
      conn: conn,
      user: user,
      other_conn: other_conn,
      other_user: other_user,
      world: world
    } do
      Application.put_env(:broken_oaths, :feudal_enabled, false)

      play_live = join_and_mount(conn, world)
      other_play_live = join_and_mount(other_conn, world)

      rival_city = found_city(other_play_live, world, other_user)
      _my_city = found_city(play_live, world, user)

      attacker = lord_warrior_adjacent_to(world, user, rival_city)

      html = render(play_live)
      refute html =~ ~s(data-test="vassals-list")
      refute html =~ ~s(data-test="vassal-status")
      refute html =~ ~s(data-test="oath-screen")
      refute html =~ ~s(data-test="city-status")
      refute html =~ ~s(data-test="bank-gold")
      refute html =~ ~s(data-test="bank-cap")
      refute html =~ ~s(data-test="player-honor")
      refute html =~ ~s(data-test="steward-log")

      html =
        render_hook(play_live, "attack", %{
          "unit_id" => to_string(attacker.id),
          "target_city_id" => to_string(rival_city.id)
        })

      assert html =~ ~s(data-test="combat-error")
      assert html =~ "Stone Age players cannot fight each other"

      [unchanged] = for c <- Game.player_cities(world, other_user), c.id == rival_city.id, do: c
      assert unchanged.hp == rival_city.hp

      refute html =~ ~s(data-test="vassals-list")
      refute html =~ ~s(data-test="vassal-status")
      refute html =~ ~s(data-test="oath-screen")
      refute html =~ ~s(data-test="city-status")
      refute html =~ ~s(data-test="bank-gold")
      refute html =~ ~s(data-test="bank-cap")
      refute html =~ ~s(data-test="player-honor")
      refute html =~ ~s(data-test="steward-log")

      # Story 909's own collect/upgrade events are refused outright
      # too, not merely hidden — belt-and-suspenders alongside the
      # missing UI above (`BrokenOaths.Game.FeudalFlagTest`'s own
      # "Bank/Stewardship, with the flag OFF" case covers the same
      # refusal directly against `Game`).
      gold_before = Game.gold(world, user)
      render_hook(play_live, "collect_bank", %{})
      assert Game.gold(world, user) == gold_before
    end
  end

  describe "with the flag ON" do
    test "attacking a rival's city lands", %{
      conn: conn,
      user: user,
      other_conn: other_conn,
      other_user: other_user,
      world: world
    } do
      Application.put_env(:broken_oaths, :feudal_enabled, true)

      play_live = join_and_mount(conn, world)
      other_play_live = join_and_mount(other_conn, world)

      rival_city = found_city(other_play_live, world, other_user)
      _my_city = found_city(play_live, world, user)

      attacker = lord_warrior_adjacent_to(world, user, rival_city)

      render_hook(play_live, "attack", %{
        "unit_id" => to_string(attacker.id),
        "target_city_id" => to_string(rival_city.id)
      })

      assert_push_event(play_live, "game:combat", %{damage_dealt: dealt}, 500)
      assert dealt > 0
    end
  end
end
