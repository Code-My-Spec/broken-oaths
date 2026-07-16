defmodule BrokenOaths.Game.ReorderProductionTest do
  # Queue reordering (story 879 / issue 5853dfaa): items carry explicit
  # positions; a reorder swaps positions with the predecessor while item
  # identity — and banked progress — stays put.
  use BrokenOathsTest.DataCase, async: false

  alias BrokenOaths.Game
  alias BrokenOaths.Game.WorldServer
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures

  setup do
    world = WorldsFixtures.world_fixture(%{frequency: 8})
    user = UsersFixtures.user_fixture()
    {:ok, _player} = Game.join_world(world, user)

    [settler] = for u <- Game.player_units(world, user), u.type == :settler, do: u
    :ok = Game.found_city(world, user, settler.id)
    [city] = Game.player_cities(world, user)

    on_exit(fn -> WorldServer.restart(world) end)
    %{world: world, user: user, city: city}
  end

  test "moving a queued item up swaps order but not identity", ctx do
    :ok = Game.queue_production(ctx.world, ctx.user, ctx.city.id, "warrior")
    :ok = Game.queue_production(ctx.world, ctx.user, ctx.city.id, "worker")

    [city] = Game.player_cities(ctx.world, ctx.user)
    [%{type: :warrior} = head, %{type: :worker} = tail] = city.queue

    # The tail item can't jump the head in one hop past it — one swap
    # makes it the head.
    :ok = Game.reorder_production_item(ctx.world, ctx.user, ctx.city.id, tail.id)

    [city] = Game.player_cities(ctx.world, ctx.user)
    assert [%{id: worker_id, type: :worker}, %{id: warrior_id, type: :warrior}] = city.queue
    assert worker_id == tail.id
    assert warrior_id == head.id
  end

  test "the head item refuses to move and unknown items are not found", ctx do
    :ok = Game.queue_production(ctx.world, ctx.user, ctx.city.id, "warrior")
    [city] = Game.player_cities(ctx.world, ctx.user)
    [head] = city.queue

    assert {:error, :invalid_item} =
             Game.reorder_production_item(ctx.world, ctx.user, ctx.city.id, head.id)

    assert {:error, :not_found} =
             Game.reorder_production_item(ctx.world, ctx.user, ctx.city.id, 999_999)
  end

  test "reordering survives a server restart (positions persist)", ctx do
    :ok = Game.queue_production(ctx.world, ctx.user, ctx.city.id, "warrior")
    :ok = Game.queue_production(ctx.world, ctx.user, ctx.city.id, "worker")

    [city] = Game.player_cities(ctx.world, ctx.user)
    [_head, tail] = city.queue
    :ok = Game.reorder_production_item(ctx.world, ctx.user, ctx.city.id, tail.id)

    :ok = Game.restart_world_server(ctx.world)

    [city] = Game.player_cities(ctx.world, ctx.user)
    assert [%{type: :worker}, %{type: :warrior}] = city.queue
  end
end
