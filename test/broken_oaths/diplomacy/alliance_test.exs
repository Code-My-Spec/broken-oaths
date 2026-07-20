defmodule BrokenOaths.Diplomacy.AllianceTest do
  use BrokenOathsTest.DataCase, async: true

  alias BrokenOaths.Diplomacy.Alliance
  alias BrokenOaths.Players.Player
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures

  defp two_players_fixture do
    world = WorldsFixtures.world_fixture()
    user_a = UsersFixtures.user_fixture()
    user_b = UsersFixtures.user_fixture()

    {:ok, player_a} =
      %Player{}
      |> Player.changeset(%{world_id: world.id, user_id: user_a.id, region_id: 1, joined_turn: 0})
      |> Repo.insert()

    {:ok, player_b} =
      %Player{}
      |> Player.changeset(%{world_id: world.id, user_id: user_b.id, region_id: 2, joined_turn: 0})
      |> Repo.insert()

    {world, player_a, player_b}
  end

  defp valid_attrs do
    {world, player_a, player_b} = two_players_fixture()

    %{
      world_id: world.id,
      player_a_id: player_a.id,
      player_b_id: player_b.id,
      proposer_player_id: player_a.id
    }
  end

  test "changeset with valid attrs is valid" do
    changeset = Alliance.changeset(%Alliance{}, valid_attrs())
    assert changeset.valid?
  end

  test "changeset requires world_id, player_a_id, player_b_id, and proposer_player_id" do
    changeset = Alliance.changeset(%Alliance{}, %{})
    refute changeset.valid?

    assert %{
             world_id: ["can't be blank"],
             player_a_id: ["can't be blank"],
             player_b_id: ["can't be blank"],
             proposer_player_id: ["can't be blank"]
           } = errors_on(changeset)
  end

  test "status defaults to proposed when not supplied" do
    changeset = Alliance.changeset(%Alliance{}, valid_attrs())
    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :status) == :proposed
  end

  test "status must be proposed or accepted" do
    changeset = Alliance.changeset(%Alliance{}, Map.put(valid_attrs(), :status, :rejected))
    refute changeset.valid?
    assert %{status: ["is invalid"]} = errors_on(changeset)
  end

  test "the two allied players must be different" do
    attrs = valid_attrs()
    changeset = Alliance.changeset(%Alliance{}, %{attrs | player_b_id: attrs.player_a_id})
    refute changeset.valid?
    assert %{player_b_id: ["can't be the same as player_a_id"]} = errors_on(changeset)
  end

  test "the proposer must be one of the two allied players" do
    {world, player_a, player_b} = two_players_fixture()
    {_other_world, stranger, _} = two_players_fixture()

    attrs = %{
      world_id: world.id,
      player_a_id: player_a.id,
      player_b_id: player_b.id,
      proposer_player_id: stranger.id
    }

    changeset = Alliance.changeset(%Alliance{}, attrs)
    refute changeset.valid?
    assert %{proposer_player_id: ["must be one of the allied players"]} = errors_on(changeset)
  end

  test "player_a_id/player_b_id are stored in a canonical (lowest id first) order" do
    attrs = valid_attrs()
    reversed = %{attrs | player_a_id: attrs.player_b_id, player_b_id: attrs.player_a_id}

    changeset = Alliance.changeset(%Alliance{}, reversed)
    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :player_a_id) == attrs.player_a_id
    assert Ecto.Changeset.get_field(changeset, :player_b_id) == attrs.player_b_id
  end

  test "only one alliance may exist per pair of players in a world, regardless of proposal order" do
    attrs = valid_attrs()
    assert {:ok, _alliance} = Alliance.changeset(%Alliance{}, attrs) |> Repo.insert()

    reversed = %{
      attrs
      | player_a_id: attrs.player_b_id,
        player_b_id: attrs.player_a_id,
        proposer_player_id: attrs.player_b_id
    }

    {:error, changeset} = Alliance.changeset(%Alliance{}, reversed) |> Repo.insert()
    assert %{world_id: ["has already been taken"]} = errors_on(changeset)
  end

  test "an alliance may be accepted via a second changeset, transitioning proposed to accepted" do
    attrs = valid_attrs()
    assert {:ok, alliance} = Alliance.changeset(%Alliance{}, attrs) |> Repo.insert()
    assert alliance.status == :proposed

    assert {:ok, accepted} =
             alliance |> Alliance.changeset(%{status: :accepted}) |> Repo.update()

    assert accepted.status == :accepted
  end
end
