defmodule BrokenOaths.Chat.BlockTest do
  use BrokenOathsTest.DataCase, async: true

  alias BrokenOaths.Chat.Block
  alias BrokenOaths.Players.Player
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures

  defp two_players_fixture do
    world = WorldsFixtures.world_fixture()
    blocker_user = UsersFixtures.user_fixture()
    blocked_user = UsersFixtures.user_fixture()

    {:ok, blocker} =
      %Player{}
      |> Player.changeset(%{
        world_id: world.id,
        user_id: blocker_user.id,
        region_id: 1,
        joined_turn: 0
      })
      |> Repo.insert()

    {:ok, blocked} =
      %Player{}
      |> Player.changeset(%{
        world_id: world.id,
        user_id: blocked_user.id,
        region_id: 2,
        joined_turn: 0
      })
      |> Repo.insert()

    {world, blocker, blocked}
  end

  defp valid_attrs do
    {world, blocker, blocked} = two_players_fixture()

    %{
      world_id: world.id,
      blocker_player_id: blocker.id,
      blocked_player_id: blocked.id
    }
  end

  test "changeset with valid attrs is valid" do
    changeset = Block.changeset(%Block{}, valid_attrs())
    assert changeset.valid?
  end

  test "changeset requires world_id, blocker_player_id, and blocked_player_id" do
    changeset = Block.changeset(%Block{}, %{})
    refute changeset.valid?

    assert %{
             world_id: ["can't be blank"],
             blocker_player_id: ["can't be blank"],
             blocked_player_id: ["can't be blank"]
           } = errors_on(changeset)
  end

  test "a player cannot block themselves" do
    attrs = valid_attrs()
    changeset = Block.changeset(%Block{}, %{attrs | blocked_player_id: attrs.blocker_player_id})
    refute changeset.valid?
    assert %{blocked_player_id: ["can't be the same as the blocker"]} = errors_on(changeset)
  end

  test "a duplicate {world, blocker, blocked} block is rejected" do
    attrs = valid_attrs()
    assert {:ok, _block} = Block.changeset(%Block{}, attrs) |> Repo.insert()

    {:error, changeset} = Block.changeset(%Block{}, attrs) |> Repo.insert()

    assert %{world_id: ["has already been taken"]} = errors_on(changeset)
  end

  test "blocking is directional — the reverse {blocker, blocked} pair is a distinct, valid row" do
    attrs = valid_attrs()
    assert {:ok, _block} = Block.changeset(%Block{}, attrs) |> Repo.insert()

    reversed = %{
      attrs
      | blocker_player_id: attrs.blocked_player_id,
        blocked_player_id: attrs.blocker_player_id
    }

    assert {:ok, _reverse_block} = Block.changeset(%Block{}, reversed) |> Repo.insert()
  end
end
