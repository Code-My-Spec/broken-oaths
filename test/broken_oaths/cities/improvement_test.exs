defmodule BrokenOaths.Cities.ImprovementTest do
  use BrokenOathsTest.DataCase, async: true

  alias BrokenOaths.Cities.Improvement
  alias BrokenOaths.Players.Player
  alias BrokenOaths.Units.Unit
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

    {:ok, improvement} =
      %Improvement{} |> Improvement.changeset(valid_attrs(world)) |> Repo.insert()

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

    {:error, changeset} =
      %Improvement{} |> Improvement.changeset(valid_attrs(world)) |> Repo.insert()

    assert %{world_id: ["has already been taken"]} = errors_on(changeset)
  end

  test "the same tile in a different world is unaffected" do
    world1 = WorldsFixtures.world_fixture()
    world2 = WorldsFixtures.world_fixture()

    assert {:ok, _} =
             %Improvement{} |> Improvement.changeset(valid_attrs(world1)) |> Repo.insert()

    assert {:ok, _} =
             %Improvement{} |> Improvement.changeset(valid_attrs(world2)) |> Repo.insert()
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

  # Story 929 "Build road to a destination" — `ensure_building/3`,
  # `start_improvement/4`'s own user-less tick-time sibling
  # (`Simulation.WorldServer.materialize_road_starts/2` is the real
  # caller; here it's driven directly, a plain hand-built tick-`state`,
  # same "no GenServer, no process" posture every OTHER pure function
  # in this module already gets tested with). Fixed seed/frequency (33,
  # 8) — the same fixture `WorldServerTest`'s own "start_improvement/4
  # gates :road on The Wheel" describe block already uses — so a land
  # tile can be found deterministically rather than risking a random
  # seed landing on water/mountain.
  describe "ensure_building/3 (story 929)" do
    defp land_tile(world) do
      Enum.find(0..641, &(BrokenOaths.Worlds.Regions.tile_class(world, &1) == :land))
    end

    defp road_state(world, player_id, opts \\ []) do
      research =
        if Keyword.get(opts, :the_wheel?, true) do
          %{completed_techs: [:mining, :the_wheel], current_research: nil, banked_science: %{}}
        else
          %{completed_techs: [], current_research: nil, banked_science: %{}}
        end

      %{
        world: world,
        improvements: %{},
        roads: Keyword.get(opts, :roads, %{}),
        player_research: %{player_id => research}
      }
    end

    test "starts a brand new :road row, given The Wheel is researched" do
      world = WorldsFixtures.world_fixture(%{seed: 33, frequency: 8})
      player = player_fixture(world)
      worker = worker_fixture(world, player)
      tile = land_tile(world)
      worker = %{worker | tile_id: tile, player_id: player.id}
      state = road_state(world, player.id)

      assert {:ok, new_state} = Improvement.ensure_building(state, worker, :road)

      assert %{status: :building, progress: 0, builder_unit_id: id} = new_state.roads[tile]
      assert id == worker.id
      assert Repo.get_by(Improvement, world_id: world.id, tile_id: tile, kind: :road)
    end

    test "refuses (does not insert a row) before The Wheel is researched" do
      world = WorldsFixtures.world_fixture(%{seed: 33, frequency: 8})
      player = player_fixture(world)
      worker = worker_fixture(world, player)
      tile = land_tile(world)
      worker = %{worker | tile_id: tile, player_id: player.id}
      state = road_state(world, player.id, the_wheel?: false)

      assert {:error, :invalid_terrain} = Improvement.ensure_building(state, worker, :road)
      refute Repo.get_by(Improvement, world_id: world.id, tile_id: tile, kind: :road)
    end

    test "resumes an already-building row rather than restarting progress, claiming the new builder" do
      world = WorldsFixtures.world_fixture(%{seed: 33, frequency: 8})
      player = player_fixture(world)
      original_worker = worker_fixture(world, player)
      new_worker = worker_fixture(world, player)
      tile = land_tile(world)

      {:ok, _row} =
        %Improvement{}
        |> Improvement.changeset(%{
          world_id: world.id,
          tile_id: tile,
          kind: :road,
          progress: 1,
          status: :building,
          builder_unit_id: original_worker.id
        })
        |> Repo.insert()

      new_worker = %{new_worker | tile_id: tile, player_id: player.id}

      roads = %{
        tile => %{
          tile_id: tile,
          kind: :road,
          progress: 1,
          status: :building,
          builder_unit_id: original_worker.id
        }
      }

      state = road_state(world, player.id, roads: roads)

      assert {:ok, new_state} = Improvement.ensure_building(state, new_worker, :road)

      assert %{status: :building, progress: 1, builder_unit_id: id} = new_state.roads[tile]
      assert id == new_worker.id
    end
  end

  describe "pillage/1 (story 893 criterion 7556)" do
    test "a completed improvement becomes pillaged, one repair-tick from done, builder cleared" do
      imp = %{kind: :farm, status: :complete, progress: 99, builder_unit_id: 7}

      pillaged = Improvement.pillage(imp)

      assert pillaged.status == :pillaged
      # Left one tick short of complete, so a worker repairs it in a single tick.
      assert pillaged.progress == max(Improvement.duration(:farm) - 1, 0)
      assert pillaged.builder_unit_id == nil
    end

    test "leaves a still-building improvement untouched" do
      imp = %{kind: :farm, status: :building, progress: 1, builder_unit_id: 7}
      assert Improvement.pillage(imp) == imp
    end

    test "leaves an already-pillaged improvement untouched" do
      imp = %{kind: :mine, status: :pillaged, progress: 0, builder_unit_id: nil}
      assert Improvement.pillage(imp) == imp
    end
  end

  describe "duration (story 902, Mining's 3-turn unlock)" do
    test "duration is nil by default — WorldServer resolves it explicitly at build-start" do
      world = WorldsFixtures.world_fixture()

      {:ok, improvement} =
        %Improvement{} |> Improvement.changeset(valid_attrs(world)) |> Repo.insert()

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

  describe "chop_yield/2 (story 927 — PM decision: yield scales with tech progress)" do
    defp research(completed_techs), do: %{completed_techs: completed_techs}

    test "Woods is 20 + 8 * the chopping player's own completed-tech count" do
      assert Improvement.chop_yield(:woods, research([])) == 20
      assert Improvement.chop_yield(:woods, research([:mining])) == 28
      assert Improvement.chop_yield(:woods, research([:mining, :bronze_working])) == 36
      assert Improvement.chop_yield(:woods, research([:a, :b, :c, :d, :e])) == 60
    end

    test "Rainforest is 75% of the Woods value at the same tech count, rounded down" do
      assert Improvement.chop_yield(:rainforest, research([])) == 15
      assert Improvement.chop_yield(:rainforest, research([:mining])) == 21
      assert Improvement.chop_yield(:rainforest, research([:mining, :bronze_working])) == 27
      assert Improvement.chop_yield(:rainforest, research([:a, :b, :c, :d, :e])) == 45
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

      assert Improvement.allowed?(:mine, %Terrain{
               base: :grassland,
               relief: :hills,
               feature: :woods
             })

      refute Improvement.allowed?(:mine, %Terrain{base: :plains, relief: :flat})
    end

    test "road allows any terrain (mountains/water are excluded upstream by tile class)" do
      assert Improvement.allowed?(:road, %Terrain{base: :desert})
      assert Improvement.allowed?(:road, %Terrain{base: :grassland, relief: :hills})
    end
  end
end
