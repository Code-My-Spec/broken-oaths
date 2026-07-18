defmodule BrokenOaths.Game.StewardLogTest do
  use BrokenOathsTest.DataCase, async: true

  alias BrokenOaths.Game.Player
  alias BrokenOaths.Game.StewardLog
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures

  defp two_players_fixture do
    world = WorldsFixtures.world_fixture()
    {steward, owner} = {UsersFixtures.user_fixture(), UsersFixtures.user_fixture()}

    [steward_player, owner_player] =
      [steward, owner]
      |> Enum.with_index(1)
      |> Enum.map(fn {user, region_id} ->
        {:ok, player} =
          %Player{}
          |> Player.changeset(%{
            world_id: world.id,
            user_id: user.id,
            region_id: region_id,
            joined_turn: 0
          })
          |> Repo.insert()

        player
      end)

    {world, steward_player, owner_player}
  end

  defp valid_attrs(overrides \\ %{}) do
    {world, steward_player, owner_player} = two_players_fixture()

    Map.merge(
      %{
        world_id: world.id,
        steward_player_id: steward_player.id,
        owner_player_id: owner_player.id,
        action: :bank_collect,
        turn: 12
      },
      overrides
    )
  end

  test "changeset with valid attrs is valid" do
    changeset = StewardLog.changeset(%StewardLog{}, valid_attrs())
    assert changeset.valid?
  end

  test "changeset requires world_id, steward_player_id, owner_player_id, action, and turn" do
    changeset = StewardLog.changeset(%StewardLog{}, %{})
    refute changeset.valid?

    assert %{
             world_id: ["can't be blank"],
             steward_player_id: ["can't be blank"],
             owner_player_id: ["can't be blank"],
             action: ["can't be blank"],
             turn: ["can't be blank"]
           } = errors_on(changeset)
  end

  test "details defaults to an empty map" do
    {:ok, log} = StewardLog.changeset(%StewardLog{}, valid_attrs()) |> Repo.insert()
    assert log.details == %{}
  end

  test "sabotage defaults to false" do
    {:ok, log} = StewardLog.changeset(%StewardLog{}, valid_attrs()) |> Repo.insert()
    assert log.sabotage == false
  end

  test "action accepts every catalogued kind" do
    for action <- [:bank_collect, :production_set, :emergency_defense] do
      changeset = StewardLog.changeset(%StewardLog{}, valid_attrs(%{action: action}))
      assert changeset.valid?
    end
  end

  test "action refuses an unknown kind" do
    changeset = StewardLog.changeset(%StewardLog{}, valid_attrs(%{action: :disband_unit}))
    refute changeset.valid?
    assert %{action: [_]} = errors_on(changeset)
  end

  test "a steward can never log an action against their own household" do
    attrs = valid_attrs()
    changeset = StewardLog.changeset(%StewardLog{}, %{attrs | owner_player_id: attrs.steward_player_id})
    refute changeset.valid?
    assert %{owner_player_id: ["can't be the same as the steward"]} = errors_on(changeset)
  end

  test "turn must be non-negative" do
    changeset = StewardLog.changeset(%StewardLog{}, valid_attrs(%{turn: -1}))
    refute changeset.valid?
    assert %{turn: [_]} = errors_on(changeset)
  end

  test "details carries an arbitrary action-shaped payload" do
    attrs = valid_attrs(%{action: :production_set, details: %{"city_id" => 7, "item" => "worker"}})
    {:ok, log} = StewardLog.changeset(%StewardLog{}, attrs) |> Repo.insert()
    assert log.details == %{"city_id" => 7, "item" => "worker"}
  end

  test "sabotage can be flagged true on an entry" do
    attrs = valid_attrs(%{sabotage: true})
    {:ok, log} = StewardLog.changeset(%StewardLog{}, attrs) |> Repo.insert()
    assert log.sabotage == true
  end

  test "several log entries can exist for the same steward/owner pair across turns" do
    {world, steward_player, owner_player} = two_players_fixture()

    common = %{
      world_id: world.id,
      steward_player_id: steward_player.id,
      owner_player_id: owner_player.id
    }

    assert {:ok, _first} =
             StewardLog.changeset(%StewardLog{}, Map.merge(common, %{action: :bank_collect, turn: 1}))
             |> Repo.insert()

    assert {:ok, _second} =
             StewardLog.changeset(
               %StewardLog{},
               Map.merge(common, %{action: :production_set, turn: 2})
             )
             |> Repo.insert()
  end
end
