defmodule BrokenOaths.WorldsTest do
  use BrokenOathsTest.DataCase, async: true

  alias BrokenOaths.Worlds
  alias BrokenOaths.Worlds.World
  import BrokenOaths.WorldsFixtures

  describe "list_worlds/0" do
    test "returns all worlds ordered by inserted_at desc" do
      world1 = world_fixture(%{name: "First"})
      world2 = world_fixture(%{name: "Second"})

      worlds = Worlds.list_worlds()
      ids = Enum.map(worlds, & &1.id)

      assert world2.id in ids
      assert world1.id in ids
      # Most recent first
      assert hd(ids) == world2.id
    end

    test "returns empty list when no worlds" do
      assert Worlds.list_worlds() == []
    end
  end

  describe "get_world!/1" do
    test "returns the world with the given id" do
      world = world_fixture()
      fetched = Worlds.get_world!(world.id)
      assert fetched.id == world.id
      assert fetched.name == world.name
      assert fetched.seed == world.seed
    end

    test "raises on non-existent id" do
      assert_raise Ecto.NoResultsError, fn ->
        Worlds.get_world!(0)
      end
    end
  end

  describe "create_open_world/0" do
    test "creates an active, full-size world with a name and a seed" do
      {:ok, world} = Worlds.create_open_world()

      assert world.status == "active"
      assert world.frequency == 54
      assert is_integer(world.seed)
      assert is_binary(world.name) and world.name != ""
    end

    test "successive worlds get distinct seeds" do
      {:ok, a} = Worlds.create_open_world()
      {:ok, b} = Worlds.create_open_world()

      refute a.seed == b.seed
    end
  end

  describe "create_world/1" do
    test "creates a world with valid attrs" do
      attrs = %{name: "My World", seed: 12345}
      assert {:ok, %World{} = world} = Worlds.create_world(attrs)
      assert world.name == "My World"
      assert world.seed == 12345
      assert world.frequency == 54
      assert world.status == "active"
    end

    test "uses default frequency" do
      {:ok, world} = Worlds.create_world(%{name: "Default", seed: 99})
      assert world.frequency == 54
    end

    test "allows custom frequency" do
      {:ok, world} = Worlds.create_world(%{name: "Custom", seed: 100, frequency: 8})
      assert world.frequency == 8
    end

    test "rejects out-of-range frequency" do
      assert {:error, changeset} = Worlds.create_world(%{name: "Huge", seed: 101, frequency: 999})
      assert errors_on(changeset).frequency

      assert {:error, changeset} = Worlds.create_world(%{name: "Zero", seed: 102, frequency: 0})
      assert errors_on(changeset).frequency
    end

    test "fails without name" do
      assert {:error, changeset} = Worlds.create_world(%{seed: 123})
      assert errors_on(changeset).name
    end

    test "fails without seed" do
      assert {:error, changeset} = Worlds.create_world(%{name: "No Seed"})
      assert errors_on(changeset).seed
    end

    test "enforces unique seed constraint" do
      world_fixture(%{seed: 42})
      assert {:error, changeset} = Worlds.create_world(%{name: "Dupe", seed: 42})
      assert errors_on(changeset).seed
    end
  end

  describe "update_world/2" do
    test "updates world name" do
      world = world_fixture()
      assert {:ok, updated} = Worlds.update_world(world, %{name: "New Name"})
      assert updated.name == "New Name"
    end

    test "updates world seed" do
      world = world_fixture()
      assert {:ok, updated} = Worlds.update_world(world, %{seed: 999})
      assert updated.seed == 999
    end
  end

  describe "delete_world/1" do
    test "deletes the world" do
      world = world_fixture()
      assert {:ok, _} = Worlds.delete_world(world)

      assert_raise Ecto.NoResultsError, fn ->
        Worlds.get_world!(world.id)
      end
    end
  end

  describe "random_world_name/1" do
    test "returns a two-word name" do
      name = Worlds.random_world_name(42)
      assert [_, _] = String.split(name, " ")
    end

    test "is deterministic" do
      assert Worlds.random_world_name(42) == Worlds.random_world_name(42)
    end

    test "different seeds give different names" do
      # Not guaranteed but overwhelmingly likely with different seeds
      names = Enum.map(1..10, &Worlds.random_world_name/1) |> Enum.uniq()
      assert length(names) > 1
    end
  end
end
