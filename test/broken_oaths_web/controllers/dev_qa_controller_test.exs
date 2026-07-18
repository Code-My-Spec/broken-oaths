defmodule BrokenOathsWeb.DevQaControllerTest do
  # async: false — every action lazily starts a Registry-addressed
  # WorldServer GenServer for the fixture world (see
  # `BrokenOaths.Game.WorldServerTest`'s own reasoning).
  use BrokenOathsTest.ConnCase, async: false

  alias BrokenOaths.Game
  alias BrokenOaths.Game.Unit
  alias BrokenOaths.Game.WorldServer
  alias BrokenOaths.Repo
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures

  setup do
    world = WorldsFixtures.world_fixture(%{frequency: 8})
    on_exit(fn -> WorldServer.restart(world) end)
    %{world: world}
  end

  describe "GET /dev/qa/worlds/:id" do
    test "returns turn, turn_seconds, and paused", %{conn: conn, world: world} do
      conn = get(conn, ~p"/dev/qa/worlds/#{world.id}")

      assert %{"id" => id, "turn" => 0, "turn_seconds" => 60, "paused" => false} =
               json_response(conn, 200)

      assert id == world.id
    end
  end

  describe "POST /dev/qa/worlds/:id/pause and /resume" do
    test "pause freezes the clock, resume unfreezes it", %{conn: conn, world: world} do
      conn = post(conn, ~p"/dev/qa/worlds/#{world.id}/pause")
      assert json_response(conn, 200) == %{"ok" => true, "paused" => true}
      assert Game.paused?(world)

      conn = get(build_conn(), ~p"/dev/qa/worlds/#{world.id}")
      assert %{"paused" => true} = json_response(conn, 200)

      conn = post(build_conn(), ~p"/dev/qa/worlds/#{world.id}/resume")
      assert json_response(conn, 200) == %{"ok" => true, "paused" => false}
      refute Game.paused?(world)
    end
  end

  describe "POST /dev/qa/worlds/:id/step" do
    test "advances exactly one turn, even while paused", %{conn: conn, world: world} do
      :ok = Game.pause_ticks(world)

      conn = post(conn, ~p"/dev/qa/worlds/#{world.id}/step")

      assert json_response(conn, 200) == %{"ok" => true, "turn" => 1}
      assert Game.turn_number(world) == 1
      assert Game.paused?(world)
    end
  end

  describe "POST /dev/qa/worlds/:id/units" do
    test "spawns a real player-owned unit", %{conn: conn, world: world} do
      user = UsersFixtures.user_fixture()
      {:ok, player} = Game.join_world(world, user)

      conn =
        post(conn, ~p"/dev/qa/worlds/#{world.id}/units", %{
          "player_id" => player.id,
          "type" => "warrior",
          "tile_id" => 42
        })

      assert %{"type" => "warrior", "tile_id" => 42, "hp" => 100, "movement" => 1} =
               json_response(conn, 201)
    end

    test "400s on an invalid unit type", %{conn: conn, world: world} do
      user = UsersFixtures.user_fixture()
      {:ok, player} = Game.join_world(world, user)

      conn =
        post(conn, ~p"/dev/qa/worlds/#{world.id}/units", %{
          "player_id" => player.id,
          "type" => "dragon",
          "tile_id" => 42
        })

      assert %{"error" => _} = json_response(conn, 400)
    end
  end

  describe "POST /dev/qa/worlds/:id/barbarians" do
    test "spawns an ownerless barbarian warrior", %{conn: conn, world: world} do
      conn = post(conn, ~p"/dev/qa/worlds/#{world.id}/barbarians", %{"tile_id" => 15})

      assert %{"type" => "barbarian_warrior", "tile_id" => 15, "camp_id" => nil} =
               json_response(conn, 201)
    end
  end

  describe "PATCH /dev/qa/worlds/:id/units/:unit_id" do
    test "sets hp, relocates, and recharges movement", %{conn: conn, world: world} do
      unit = Game.spawn_barbarian_for_test(world, 15)
      :ok = Game.set_unit_hp_for_test(world, unit.id, 1)

      conn =
        patch(conn, ~p"/dev/qa/worlds/#{world.id}/units/#{unit.id}", %{
          "hp" => 33,
          "tile_id" => 16,
          "recharge" => true
        })

      assert json_response(conn, 200) == %{"ok" => true}

      row = Repo.get!(Unit, unit.id)
      assert row.hp == 33
      assert row.tile_id == 16
      assert row.movement == row.max_movement
    end

    test "an occupied relocation target surfaces as a 400", %{conn: conn, world: world} do
      unit_a = Game.spawn_barbarian_for_test(world, 20)
      _unit_b = Game.spawn_barbarian_for_test(world, 21)

      conn = patch(conn, ~p"/dev/qa/worlds/#{world.id}/units/#{unit_a.id}", %{"tile_id" => 21})

      assert %{"error" => "occupied"} = json_response(conn, 400)
    end
  end

  describe "DELETE /dev/qa/worlds/:id/units/:unit_id" do
    test "hard-deletes a unit", %{conn: conn, world: world} do
      unit = Game.spawn_barbarian_for_test(world, 15)

      conn = delete(conn, ~p"/dev/qa/worlds/#{world.id}/units/#{unit.id}")

      assert json_response(conn, 200) == %{"ok" => true}
      assert Repo.get(Unit, unit.id) == nil
    end
  end

  describe "PATCH /dev/qa/worlds/:id/camps/:camp_id" do
    test "sets a camp's HP directly", %{conn: conn, world: world} do
      user = UsersFixtures.user_fixture()
      {:ok, _player} = Game.join_world(world, user)
      [settler] = for u <- Game.player_units(world, user), u.type == :settler, do: u
      :ok = Game.found_city(world, user, settler.id)
      [camp | _] = Game.list_camps(world)

      conn = patch(conn, ~p"/dev/qa/worlds/#{world.id}/camps/#{camp.id}", %{"hp" => 1})

      assert json_response(conn, 200) == %{"ok" => true}
      assert Enum.find(Game.list_camps(world), &(&1.id == camp.id)).hp == 1
    end
  end
end
