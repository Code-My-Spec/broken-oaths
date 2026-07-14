defmodule BrokenOaths.Game.PlayerTest do
  use BrokenOathsTest.DataCase, async: true

  alias BrokenOaths.Game.Player
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures

  defp valid_attrs do
    world = WorldsFixtures.world_fixture()
    user = UsersFixtures.user_fixture()

    %{world_id: world.id, user_id: user.id, region_id: 1, gold: 50, joined_turn: 0}
  end

  test "changeset with valid attrs is valid" do
    changeset = Player.changeset(%Player{}, valid_attrs())
    assert changeset.valid?
  end

  test "changeset requires world_id, user_id, region_id, and joined_turn" do
    changeset = Player.changeset(%Player{}, %{})
    refute changeset.valid?

    assert %{
             world_id: ["can't be blank"],
             user_id: ["can't be blank"],
             region_id: ["can't be blank"],
             joined_turn: ["can't be blank"]
           } = errors_on(changeset)
  end

  test "gold defaults to 50 when not supplied" do
    attrs = valid_attrs() |> Map.delete(:gold)
    changeset = Player.changeset(%Player{}, attrs)
    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :gold) == 50
  end

  test "gold must be non-negative" do
    changeset = Player.changeset(%Player{}, %{valid_attrs() | gold: -1})
    refute changeset.valid?
    assert %{gold: ["must be greater than or equal to 0"]} = errors_on(changeset)
  end

  test "joined_turn must be non-negative" do
    changeset = Player.changeset(%Player{}, %{valid_attrs() | joined_turn: -1})
    refute changeset.valid?
    assert %{joined_turn: ["must be greater than or equal to 0"]} = errors_on(changeset)
  end

  test "world_id must reference an existing world" do
    attrs = %{valid_attrs() | world_id: -1}
    {:error, changeset} = Player.changeset(%Player{}, attrs) |> Repo.insert()
    assert %{world: ["does not exist"]} = errors_on(changeset)
  end

  test "a user can only join a world once" do
    attrs = valid_attrs()
    assert {:ok, _player} = Player.changeset(%Player{}, attrs) |> Repo.insert()

    dup_attrs = Map.put(attrs, :region_id, attrs.region_id + 1)
    {:error, changeset} = Player.changeset(%Player{}, dup_attrs) |> Repo.insert()
    assert %{world_id: ["has already been taken"]} = errors_on(changeset)
  end

  test "a region can only be claimed by one player per world" do
    attrs = valid_attrs()
    assert {:ok, player} = Player.changeset(%Player{}, attrs) |> Repo.insert()

    other_user = UsersFixtures.user_fixture()

    dup_attrs = %{attrs | user_id: other_user.id, region_id: player.region_id}
    {:error, changeset} = Player.changeset(%Player{}, dup_attrs) |> Repo.insert()
    assert %{world_id: ["has already been taken"]} = errors_on(changeset)
  end
end
