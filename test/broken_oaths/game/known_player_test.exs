defmodule BrokenOaths.Game.KnownPlayerTest do
  use BrokenOathsTest.DataCase, async: true

  alias BrokenOaths.Game.KnownPlayer
  alias BrokenOaths.Game.Player
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures

  defp two_players_fixture do
    world = WorldsFixtures.world_fixture()
    viewer_user = UsersFixtures.user_fixture()
    discovered_user = UsersFixtures.user_fixture()

    {:ok, viewer} =
      %Player{}
      |> Player.changeset(%{
        world_id: world.id,
        user_id: viewer_user.id,
        region_id: 1,
        joined_turn: 0
      })
      |> Repo.insert()

    {:ok, discovered} =
      %Player{}
      |> Player.changeset(%{
        world_id: world.id,
        user_id: discovered_user.id,
        region_id: 2,
        joined_turn: 0
      })
      |> Repo.insert()

    {world, viewer, discovered}
  end

  defp valid_attrs do
    {world, viewer, discovered} = two_players_fixture()

    %{
      world_id: world.id,
      viewer_player_id: viewer.id,
      discovered_player_id: discovered.id
    }
  end

  test "changeset with valid attrs is valid" do
    changeset = KnownPlayer.changeset(%KnownPlayer{}, valid_attrs())
    assert changeset.valid?
  end

  test "changeset requires world_id, viewer_player_id, and discovered_player_id" do
    changeset = KnownPlayer.changeset(%KnownPlayer{}, %{})
    refute changeset.valid?

    assert %{
             world_id: ["can't be blank"],
             viewer_player_id: ["can't be blank"],
             discovered_player_id: ["can't be blank"]
           } = errors_on(changeset)
  end

  test "a player cannot discover themselves" do
    attrs = valid_attrs()
    changeset = KnownPlayer.changeset(%KnownPlayer{}, %{attrs | discovered_player_id: attrs.viewer_player_id})
    refute changeset.valid?
    assert %{discovered_player_id: ["can't be the same as the viewer"]} = errors_on(changeset)
  end

  test "a discovery record is permanent once set — a duplicate {world, viewer, discovered} is rejected" do
    attrs = valid_attrs()
    assert {:ok, _known_player} = KnownPlayer.changeset(%KnownPlayer{}, attrs) |> Repo.insert()

    {:error, changeset} = KnownPlayer.changeset(%KnownPlayer{}, attrs) |> Repo.insert()

    assert %{world_id: ["has already been taken"]} = errors_on(changeset)
  end

  test "discovery is directional — the reverse {viewer, discovered} pair is a distinct, valid row" do
    attrs = valid_attrs()
    assert {:ok, _known_player} = KnownPlayer.changeset(%KnownPlayer{}, attrs) |> Repo.insert()

    reversed = %{
      attrs
      | viewer_player_id: attrs.discovered_player_id,
        discovered_player_id: attrs.viewer_player_id
    }

    assert {:ok, _reverse_known_player} = KnownPlayer.changeset(%KnownPlayer{}, reversed) |> Repo.insert()
  end
end
