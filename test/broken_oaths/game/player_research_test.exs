defmodule BrokenOaths.Game.PlayerResearchTest do
  use BrokenOathsTest.DataCase, async: true

  alias BrokenOaths.Game.Player
  alias BrokenOaths.Game.PlayerResearch
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures

  @all_techs [
    :pottery,
    :animal_husbandry,
    :mining,
    :sailing,
    :astrology,
    :writing,
    :irrigation,
    :archery,
    :masonry,
    :the_wheel,
    :bronze_working
  ]

  defp player_fixture do
    world = WorldsFixtures.world_fixture()
    user = UsersFixtures.user_fixture()

    {:ok, player} =
      %Player{}
      |> Player.changeset(%{world_id: world.id, user_id: user.id, region_id: 1, joined_turn: 0})
      |> Repo.insert()

    {world, player}
  end

  defp valid_attrs do
    {world, player} = player_fixture()
    %{world_id: world.id, player_id: player.id}
  end

  test "changeset with valid attrs is valid" do
    changeset = PlayerResearch.changeset(%PlayerResearch{}, valid_attrs())
    assert changeset.valid?
  end

  test "changeset requires world_id and player_id" do
    changeset = PlayerResearch.changeset(%PlayerResearch{}, %{})
    refute changeset.valid?
    assert %{world_id: ["can't be blank"], player_id: ["can't be blank"]} = errors_on(changeset)
  end

  test "completed_techs and banked_science default to empty, current_research defaults to nil" do
    {:ok, player_research} =
      PlayerResearch.changeset(%PlayerResearch{}, valid_attrs()) |> Repo.insert()

    assert player_research.completed_techs == []
    assert player_research.banked_science == %{}
    assert player_research.current_research == nil
  end

  test "current_research must be one of the eleven Ancient-era techs" do
    attrs = Map.put(valid_attrs(), :current_research, :printing_press)
    changeset = PlayerResearch.changeset(%PlayerResearch{}, attrs)
    refute changeset.valid?
    assert %{current_research: ["is invalid"]} = errors_on(changeset)
  end

  test "current_research may be any of the eleven valid techs" do
    for tech <- @all_techs do
      attrs = Map.put(valid_attrs(), :current_research, tech)
      changeset = PlayerResearch.changeset(%PlayerResearch{}, attrs)
      assert changeset.valid?
    end
  end

  test "current_research cannot be a tech that's already completed" do
    attrs =
      valid_attrs()
      |> Map.put(:completed_techs, [:pottery])
      |> Map.put(:current_research, :pottery)

    changeset = PlayerResearch.changeset(%PlayerResearch{}, attrs)
    refute changeset.valid?

    assert %{current_research: ["can't be a tech that's already completed"]} =
             errors_on(changeset)
  end

  test "banked_science persists a per-tech map" do
    attrs =
      valid_attrs()
      |> Map.put(:current_research, :mining)
      |> Map.put(:banked_science, %{"mining" => 30, "pottery" => 50})

    assert {:ok, player_research} =
             PlayerResearch.changeset(%PlayerResearch{}, attrs) |> Repo.insert()

    assert player_research.banked_science == %{"mining" => 30, "pottery" => 50}
  end

  test "only one research row may exist per (world, player)" do
    attrs = valid_attrs()
    assert {:ok, _} = PlayerResearch.changeset(%PlayerResearch{}, attrs) |> Repo.insert()

    {:error, changeset} = PlayerResearch.changeset(%PlayerResearch{}, attrs) |> Repo.insert()
    assert %{world_id: ["has already been taken"]} = errors_on(changeset)
  end

  test "a second player in the same world gets their own row" do
    {world, player_a} = player_fixture()
    user_b = UsersFixtures.user_fixture()

    {:ok, player_b} =
      %Player{}
      |> Player.changeset(%{world_id: world.id, user_id: user_b.id, region_id: 2, joined_turn: 0})
      |> Repo.insert()

    assert {:ok, _} =
             PlayerResearch.changeset(%PlayerResearch{}, %{
               world_id: world.id,
               player_id: player_a.id
             })
             |> Repo.insert()

    assert {:ok, _} =
             PlayerResearch.changeset(%PlayerResearch{}, %{
               world_id: world.id,
               player_id: player_b.id
             })
             |> Repo.insert()
  end

  test "progress can be updated via a second changeset" do
    {:ok, player_research} =
      PlayerResearch.changeset(
        %PlayerResearch{},
        Map.put(valid_attrs(), :current_research, :mining)
      )
      |> Repo.insert()

    assert {:ok, updated} =
             player_research
             |> PlayerResearch.changeset(%{
               banked_science: %{"mining" => 75},
               completed_techs: [:mining],
               current_research: nil
             })
             |> Repo.update()

    assert updated.completed_techs == [:mining]
    assert updated.current_research == nil
    assert updated.banked_science == %{"mining" => 75}
  end
end
