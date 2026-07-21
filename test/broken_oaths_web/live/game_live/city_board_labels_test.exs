defmodule BrokenOathsWeb.GameLive.CityBoardLabelsTest do
  @moduledoc """
  Playtest issue cee40da6 — "City names should show below the city with
  a fill showing their build progress." Two things ride the client's
  `.Board` hook can't otherwise get: `PlayView.city_marker/1`'s new
  `progress:` fraction on every `game:cities` push (asserted here,
  server-side) and the canvas draw loop itself, which reads its own
  source (`BoardHookSourceTest`, the "the canvas board itself is never
  asserted, but plain server-side source IS" status that module's own
  moduledoc already establishes).

  `name:` was already part of every `game:cities` entry before this
  issue (`city_marker/1`/`enemy_city_marker/1` both already `Map.take`
  it) — nothing new to assert there. `progress:` is the new field, and
  the interesting behavior is where it does and doesn't appear: an
  OWNED city always carries it (0.0 with nothing queued, banked/cost
  once something is), while a fogged HOSTILE city never does — its
  build queue stays exactly as hidden as its production TYPE already
  was (QA issue 56ee521a's own `enemy_city_marker/1` never exposed
  that either).
  """

  # async: false — mounts a real `GameLive.Play` LiveView, which spawns
  # a real `BrokenOaths.Simulation.WorldServer` GenServer outside this
  # test's own sandbox ownership, the same non-async status every other
  # `Play`-mounting test in this directory already carries.
  use BrokenOathsTest.ConnCase, async: false

  import Phoenix.LiveViewTest
  import BrokenOaths.WorldsFixtures

  alias BrokenOaths.Game
  alias BrokenOaths.UsersFixtures

  setup :register_and_log_in_user

  setup do
    {:ok, world: world_fixture(%{seed: 424_242})}
  end

  defp join_and_mount(conn, world) do
    {:ok, join_live, _html} = live(conn, ~p"/play")

    join_live
    |> element("[data-test='join-world-#{world.id}']")
    |> render_click()

    live(conn, ~p"/play/#{world.id}")
  end

  defp found_first_city(play_live, world, user) do
    [settler | _] = for u <- Game.player_units(world, user), u.type == :settler, do: u
    render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
    assert_push_event(play_live, "game:camps", %{camps: _camps}, 500)
    [city] = Game.player_cities(world, user)
    city
  end

  describe "an owned city's own progress fraction" do
    test "a freshly founded city with nothing queued pushes progress: 0.0", %{
      conn: conn,
      world: world,
      user: user
    } do
      {:ok, play_live, _html} = join_and_mount(conn, world)
      city = found_first_city(play_live, world, user)

      # `found_first_city/3` already waited on "game:camps" (story 892's
      # wilderness seed), which lands in the SAME `refresh_board/1` call
      # that pushes "game:cities" — a fresh mount reads it cleanly.
      {:ok, fresh, _html} = live(conn, ~p"/play/#{world.id}")
      assert_push_event(fresh, "game:cities", %{cities: cities}, 500)

      marker = Enum.find(cities, &(&1.id == city.id))
      assert marker
      assert marker.name == city.name
      assert marker.hostile == false
      assert marker.progress == 0.0
    end

    test "a queued build's banked/cost fraction rides the very next push", %{
      conn: conn,
      world: world,
      user: user
    } do
      {:ok, play_live, _html} = join_and_mount(conn, world)
      city = found_first_city(play_live, world, user)

      render_hook(play_live, "queue_production", %{
        "city_id" => to_string(city.id),
        "item" => "warrior"
      })

      # A Warrior costs 40 production; the flat base alone is 5/turn
      # (`Production.flat_base/0`), so three turns bank 15 without ever
      # completing the build (15 < 40) — the fraction has to hold
      # steady mid-build, not just at 0 or 1.
      Game.advance_turn(world)
      Game.advance_turn(world)
      Game.advance_turn(world)

      [refreshed] = Game.player_cities(world, user)
      [head_item | _] = refreshed.queue
      expected = head_item.banked / head_item.cost
      assert expected > 0.0 and expected < 1.0

      {:ok, fresh, _html} = live(conn, ~p"/play/#{world.id}")
      assert_push_event(fresh, "game:cities", %{cities: cities}, 500)

      marker = Enum.find(cities, &(&1.id == city.id))
      assert_in_delta marker.progress, expected, 0.001
    end
  end

  describe "fog consistency (QA issue 56ee521a's own boundary)" do
    setup do
      other_user = UsersFixtures.user_fixture()
      other_conn = log_in_user(build_conn(), other_user)

      original = Application.get_env(:broken_oaths, :feudal_enabled)
      Application.put_env(:broken_oaths, :feudal_enabled, true)
      on_exit(fn -> Application.put_env(:broken_oaths, :feudal_enabled, original) end)

      {:ok, other_user: other_user, other_conn: other_conn}
    end

    test "a hostile city's own progress never rides the board, even once its name/hp do", %{
      conn: conn,
      user: user,
      other_conn: other_conn,
      other_user: other_user,
      world: world
    } do
      {:ok, other_play_live, _html} = join_and_mount(other_conn, world)
      {:ok, play_live, _html} = join_and_mount(conn, world)

      rival_city = found_first_city(other_play_live, world, other_user)
      _my_city = found_first_city(play_live, world, user)

      # Same barbarian-interference guard `FeudalCaptureUITest` already
      # documents: a roaming barbarian killing an untracked unit would
      # fail this test for a reason that has nothing to do with fog.
      :ok = Game.isolate_camp_for_test(world, -1)

      # Queue the rival something real to bank against — the leak this
      # test guards against is only interesting once there's actual
      # progress that COULD have shown up.
      render_hook(other_play_live, "queue_production", %{
        "city_id" => to_string(rival_city.id),
        "item" => "warrior"
      })

      {:ok, other_player} = Game.join_world(world, user)

      warrior_tile =
        world
        |> BrokenOaths.Worlds.Regions.adjacent_tiles(rival_city.tile_id)
        |> Enum.filter(&(BrokenOaths.Worlds.Regions.tile_class(world, &1) == :land))
        |> hd()

      Game.spawn_unit_for_test(world, other_player.id, :warrior, warrior_tile)
      Game.advance_turn(world)

      {:ok, fresh, _html} = live(conn, ~p"/play/#{world.id}")
      assert_push_event(fresh, "game:cities", %{cities: cities}, 500)

      hostile = Enum.find(cities, &(&1.id == rival_city.id))
      assert hostile
      assert hostile.hostile == true
      assert hostile.name == rival_city.name
      refute Map.has_key?(hostile, :progress)
    end
  end
end
