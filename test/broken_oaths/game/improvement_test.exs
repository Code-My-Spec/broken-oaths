defmodule BrokenOaths.Game.ImprovementTest do
  use BrokenOathsTest.DataCase, async: true

  alias BrokenOaths.Game.Improvement
  alias BrokenOaths.Players.Player
  alias BrokenOaths.Game.Unit
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.Worlds.Terrain
  alias BrokenOaths.WorldsFixtures

  defp player_fixture(world) do
    user = UsersFixtures.user_fixture()

    {:ok, player} =
      %Player{}
      |> Player.changeset(%{world_id: world.id, user_id: user.id, region_id: 1, joined_turn: 0})
      |> Repo.insert()

    player
  end

  defp worker_fixture(world, player) do
    {:ok, unit} =
      %Unit{}
      |> Unit.changeset(%{
        world_id: world.id,
        player_id: player.id,
        type: :worker,
        tile_id: 42,
        hp: 10,
        max_hp: 10,
        movement: 2,
        max_movement: 2
      })
      |> Repo.insert()

    unit
  end

  defp valid_attrs(world) do
    %{world_id: world.id, tile_id: 100, kind: :farm, progress: 0, status: :building}
  end

  test "changeset with valid attrs is valid" do
    world = WorldsFixtures.world_fixture()
    changeset = Improvement.changeset(%Improvement{}, valid_attrs(world))
    assert changeset.valid?
  end

  test "changeset requires world_id, tile_id, kind, and status" do
    changeset = Improvement.changeset(%Improvement{}, %{})
    refute changeset.valid?

    assert %{
             world_id: ["can't be blank"],
             tile_id: ["can't be blank"],
             kind: ["can't be blank"]
           } = errors_on(changeset)
  end

  test "kind must be farm, mine, or road" do
    world = WorldsFixtures.world_fixture()
    changeset = Improvement.changeset(%Improvement{}, %{valid_attrs(world) | kind: :castle})
    refute changeset.valid?
    assert %{kind: ["is invalid"]} = errors_on(changeset)
  end

  test "status defaults to building" do
    world = WorldsFixtures.world_fixture()
    {:ok, improvement} = %Improvement{} |> Improvement.changeset(valid_attrs(world)) |> Repo.insert()
    assert improvement.status == :building
    assert improvement.progress == 0
  end

  test "progress cannot be negative" do
    world = WorldsFixtures.world_fixture()
    changeset = Improvement.changeset(%Improvement{}, %{valid_attrs(world) | progress: -1})
    refute changeset.valid?
    assert %{progress: ["must be greater than or equal to 0"]} = errors_on(changeset)
  end

  test "only one improvement per tile per world" do
    world = WorldsFixtures.world_fixture()
    assert {:ok, _} = %Improvement{} |> Improvement.changeset(valid_attrs(world)) |> Repo.insert()

    {:error, changeset} = %Improvement{} |> Improvement.changeset(valid_attrs(world)) |> Repo.insert()
    assert %{world_id: ["has already been taken"]} = errors_on(changeset)
  end

  test "the same tile in a different world is unaffected" do
    world1 = WorldsFixtures.world_fixture()
    world2 = WorldsFixtures.world_fixture()

    assert {:ok, _} = %Improvement{} |> Improvement.changeset(valid_attrs(world1)) |> Repo.insert()
    assert {:ok, _} = %Improvement{} |> Improvement.changeset(valid_attrs(world2)) |> Repo.insert()
  end

  test "builder_unit_id may reference a worker, or be nil while paused" do
    world = WorldsFixtures.world_fixture()
    player = player_fixture(world)
    worker = worker_fixture(world, player)

    attrs = Map.put(valid_attrs(world), :builder_unit_id, worker.id)
    {:ok, improvement} = %Improvement{} |> Improvement.changeset(attrs) |> Repo.insert()
    assert improvement.builder_unit_id == worker.id

    {:ok, paused} = improvement |> Improvement.changeset(%{builder_unit_id: nil}) |> Repo.update()
    assert paused.builder_unit_id == nil
  end

  describe "duration (story 902, Mining's 3-turn unlock)" do
    test "duration is nil by default — WorldServer resolves it explicitly at build-start" do
      world = WorldsFixtures.world_fixture()
      {:ok, improvement} = %Improvement{} |> Improvement.changeset(valid_attrs(world)) |> Repo.insert()
      assert improvement.duration == nil
    end

    test "duration can be set to a research-resolved override" do
      world = WorldsFixtures.world_fixture()
      attrs = Map.merge(valid_attrs(world), %{kind: :mine, duration: 3})
      {:ok, improvement} = %Improvement{} |> Improvement.changeset(attrs) |> Repo.insert()
      assert improvement.duration == 3
    end

    test "duration must be positive" do
      world = WorldsFixtures.world_fixture()
      changeset = Improvement.changeset(%Improvement{}, Map.put(valid_attrs(world), :duration, 0))
      refute changeset.valid?
      assert %{duration: ["must be greater than 0"]} = errors_on(changeset)
    end
  end

  describe "duration/1" do
    test "matches the story 882 yield table" do
      assert Improvement.duration(:farm) == 3
      assert Improvement.duration(:mine) == 5
      assert Improvement.duration(:road) == 2
    end
  end

  describe "allowed?/2" do
    test "farm needs flat, featureless grassland or plains" do
      assert Improvement.allowed?(:farm, %Terrain{base: :grassland})
      assert Improvement.allowed?(:farm, %Terrain{base: :plains})
      refute Improvement.allowed?(:farm, %Terrain{base: :grassland, relief: :hills})
      refute Improvement.allowed?(:farm, %Terrain{base: :grassland, feature: :woods})
      refute Improvement.allowed?(:farm, %Terrain{base: :desert})
    end

    test "mine needs hills, regardless of base or feature" do
      assert Improvement.allowed?(:mine, %Terrain{base: :plains, relief: :hills})
      assert Improvement.allowed?(:mine, %Terrain{base: :grassland, relief: :hills, feature: :woods})
      refute Improvement.allowed?(:mine, %Terrain{base: :plains, relief: :flat})
    end

    test "road allows any terrain (mountains/water are excluded upstream by tile class)" do
      assert Improvement.allowed?(:road, %Terrain{base: :desert})
      assert Improvement.allowed?(:road, %Terrain{base: :grassland, relief: :hills})
    end
  end
end
