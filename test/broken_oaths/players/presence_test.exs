defmodule BrokenOaths.Players.PresenceTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Players.Presence

  setup do
    world = %{id: System.unique_integer([:positive])}
    user = %{id: System.unique_integer([:positive])}
    other_user = %{id: System.unique_integer([:positive])}
    {:ok, world: world, user: user, other_user: other_user}
  end

  describe "connect/2 and online?/2" do
    test "a user with no connection is offline", %{world: world, user: user} do
      refute Presence.online?(world, user)
    end

    test "connecting marks the caller online", %{world: world, user: user} do
      :ok = Presence.connect(world, user)
      assert Presence.online?(world, user)
    end

    test "connecting is scoped to the world", %{world: world, user: user} do
      other_world = %{id: System.unique_integer([:positive])}
      :ok = Presence.connect(world, user)

      assert Presence.online?(world, user)
      refute Presence.online?(other_world, user)
    end

    test "connecting is scoped to the user", %{world: world, user: user, other_user: other_user} do
      :ok = Presence.connect(world, user)

      assert Presence.online?(world, user)
      refute Presence.online?(world, other_user)
    end

    test "connecting twice from the same process is idempotent", %{world: world, user: user} do
      :ok = Presence.connect(world, user)
      :ok = Presence.connect(world, user)
      assert Presence.online?(world, user)
    end
  end

  describe "disconnect/2" do
    test "explicitly disconnecting drops online status", %{world: world, user: user} do
      :ok = Presence.connect(world, user)
      assert Presence.online?(world, user)

      :ok = Presence.disconnect(world, user)
      refute Presence.online?(world, user)
    end
  end

  describe "process death" do
    test "a connection is dropped automatically when its owning process dies", %{
      world: world,
      user: user
    } do
      test_pid = self()

      {:ok, pid} =
        Task.start(fn ->
          Presence.connect(world, user)
          send(test_pid, :connected)

          receive do
            :stop -> :ok
          end
        end)

      assert_receive :connected
      assert Presence.online?(world, user)

      ref = Process.monitor(pid)
      send(pid, :stop)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}

      # The test's own monitor and the Registry's internal cleanup monitor
      # are two independent monitors on the same process — both fire on
      # exit, but not necessarily in the same order, so the Registry's own
      # removal can lag a moment behind our own `:DOWN` — poll briefly
      # rather than assert instantaneous cleanup.
      refute eventually(fn -> Presence.online?(world, user) end, false)
    end

    test "a second connection from another process keeps the user online after the first exits",
         %{world: world, user: user} do
      test_pid = self()

      {:ok, pid} =
        Task.start(fn ->
          Presence.connect(world, user)
          send(test_pid, :connected)

          receive do
            :stop -> :ok
          end
        end)

      assert_receive :connected
      :ok = Presence.connect(world, user)

      ref = Process.monitor(pid)
      send(pid, :stop)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}

      assert eventually(fn -> Presence.online?(world, user) end, true)
    end
  end

  defp eventually(fun, expected, attempts \\ 20) do
    Enum.reduce_while(1..attempts, fun.(), fn _, result ->
      if result == expected do
        {:halt, result}
      else
        Process.sleep(5)
        {:cont, fun.()}
      end
    end)
  end

  describe "online_user_ids/1" do
    test "lists every distinct connected user for the given world", %{
      world: world,
      user: user,
      other_user: other_user
    } do
      :ok = Presence.connect(world, user)
      :ok = Presence.connect(world, other_user)

      ids = Presence.online_user_ids(world)
      assert Enum.sort(ids) == Enum.sort([user.id, other_user.id])
    end

    test "never lists a user connected to a different world", %{world: world, user: user} do
      other_world = %{id: System.unique_integer([:positive])}
      :ok = Presence.connect(other_world, user)

      assert Presence.online_user_ids(world) == []
    end

    test "an offline world reports no one online", %{world: world} do
      assert Presence.online_user_ids(world) == []
    end
  end
end
