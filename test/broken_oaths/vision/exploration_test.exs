defmodule BrokenOaths.Vision.ExplorationTest do
  use BrokenOathsTest.DataCase, async: true

  alias BrokenOaths.Vision.Exploration
  alias BrokenOaths.Players.Player
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures

  defp player_fixture do
    world = WorldsFixtures.world_fixture()
    user = UsersFixtures.user_fixture()

    {:ok, player} =
      %Player{}
      |> Player.changeset(%{
        world_id: world.id,
        user_id: user.id,
        region_id: 1,
        joined_turn: 0
      })
      |> Repo.insert()

    player
  end

  defp valid_attrs do
    player = player_fixture()
    %{world_id: player.world_id, player_id: player.id, explored: [1, 2, 3]}
  end

  test "changeset with valid attrs is valid" do
    changeset = Exploration.changeset(%Exploration{}, valid_attrs())
    assert changeset.valid?
  end

  test "changeset requires world_id and player_id" do
    changeset = Exploration.changeset(%Exploration{}, %{})
    refute changeset.valid?

    assert %{
             world_id: ["can't be blank"],
             player_id: ["can't be blank"]
           } = errors_on(changeset)
  end

  test "explored defaults to an empty list when not supplied" do
    attrs = valid_attrs() |> Map.delete(:explored)
    changeset = Exploration.changeset(%Exploration{}, attrs)
    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :explored) == []
  end

  test "explored can be an empty list when explicitly given" do
    changeset = Exploration.changeset(%Exploration{}, %{valid_attrs() | explored: []})
    assert changeset.valid?
  end

  test "a player has only one exploration mask per world" do
    attrs = valid_attrs()
    assert {:ok, _exploration} = Exploration.changeset(%Exploration{}, attrs) |> Repo.insert()

    {:error, changeset} =
      Exploration.changeset(%Exploration{}, %{attrs | explored: [4, 5]}) |> Repo.insert()

    assert %{world_id: ["has already been taken"]} = errors_on(changeset)
  end
end
