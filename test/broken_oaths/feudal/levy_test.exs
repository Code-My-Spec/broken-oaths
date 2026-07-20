defmodule BrokenOaths.Feudal.LevyTest do
  use BrokenOathsTest.DataCase, async: true

  alias BrokenOaths.Feudal.Levy
  alias BrokenOaths.Players.Player
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures

  defp three_players_fixture do
    world = WorldsFixtures.world_fixture()

    {lord, vassal, target} =
      {UsersFixtures.user_fixture(), UsersFixtures.user_fixture(), UsersFixtures.user_fixture()}

    [lord_player, vassal_player, target_player] =
      [lord, vassal, target]
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

    {world, lord_player, vassal_player, target_player}
  end

  defp valid_attrs do
    {world, lord_player, vassal_player, target_player} = three_players_fixture()

    %{
      world_id: world.id,
      lord_player_id: lord_player.id,
      vassal_player_id: vassal_player.id,
      target_player_id: target_player.id,
      pledged_share: 0.5
    }
  end

  test "changeset with valid attrs is valid" do
    changeset = Levy.changeset(%Levy{}, valid_attrs())
    assert changeset.valid?
  end

  test "status defaults to :pending" do
    {:ok, levy} = Levy.changeset(%Levy{}, valid_attrs()) |> Repo.insert()
    assert levy.status == :pending
  end

  test "changeset requires world_id, lord_player_id, vassal_player_id, target_player_id, and pledged_share" do
    changeset = Levy.changeset(%Levy{}, %{})
    refute changeset.valid?

    assert %{
             world_id: ["can't be blank"],
             lord_player_id: ["can't be blank"],
             vassal_player_id: ["can't be blank"],
             target_player_id: ["can't be blank"],
             pledged_share: ["can't be blank"]
           } = errors_on(changeset)
  end

  test "pledged_share must be greater than 0" do
    attrs = Map.put(valid_attrs(), :pledged_share, 0.0)
    changeset = Levy.changeset(%Levy{}, attrs)
    refute changeset.valid?
    assert %{pledged_share: ["must be greater than 0"]} = errors_on(changeset)
  end

  test "pledged_share cannot exceed 1 (the whole standing army)" do
    attrs = Map.put(valid_attrs(), :pledged_share, 1.5)
    changeset = Levy.changeset(%Levy{}, attrs)
    refute changeset.valid?
    assert %{pledged_share: ["must be less than or equal to 1"]} = errors_on(changeset)
  end

  test "pledged_share of exactly 1 (the whole army) is valid" do
    attrs = Map.put(valid_attrs(), :pledged_share, 1.0)
    changeset = Levy.changeset(%Levy{}, attrs)
    assert changeset.valid?
  end

  test "status must be one of pending, answered, or refused" do
    attrs = Map.put(valid_attrs(), :status, :sworn)
    changeset = Levy.changeset(%Levy{}, attrs)
    refute changeset.valid?
    assert %{status: ["is invalid"]} = errors_on(changeset)
  end

  test "status may be answered or refused" do
    for status <- [:pending, :answered, :refused] do
      attrs = Map.put(valid_attrs(), :status, status)
      changeset = Levy.changeset(%Levy{}, attrs)
      assert changeset.valid?
    end
  end

  test "a lord cannot call themselves to arms" do
    attrs = valid_attrs()
    changeset = Levy.changeset(%Levy{}, %{attrs | vassal_player_id: attrs.lord_player_id})
    refute changeset.valid?
    assert %{vassal_player_id: ["can't be the same as the lord"]} = errors_on(changeset)
  end

  test "the war's target cannot be the vassal being called" do
    attrs = valid_attrs()
    changeset = Levy.changeset(%Levy{}, %{attrs | target_player_id: attrs.vassal_player_id})
    refute changeset.valid?
    assert %{target_player_id: ["can't be the same as the vassal"]} = errors_on(changeset)
  end

  test "the war's target cannot be the lord issuing the call" do
    attrs = valid_attrs()
    changeset = Levy.changeset(%Levy{}, %{attrs | target_player_id: attrs.lord_player_id})
    refute changeset.valid?
    assert %{target_player_id: ["can't be the same as the lord"]} = errors_on(changeset)
  end

  test "a levy can be answered via a second changeset, keeping the pledge" do
    {:ok, levy} = Levy.changeset(%Levy{}, valid_attrs()) |> Repo.insert()

    assert {:ok, answered} = levy |> Levy.changeset(%{status: :answered}) |> Repo.update()
    assert answered.status == :answered
    assert answered.pledged_share == levy.pledged_share
  end

  test "a levy can be refused via a second changeset" do
    {:ok, levy} = Levy.changeset(%Levy{}, valid_attrs()) |> Repo.insert()

    assert {:ok, refused} = levy |> Levy.changeset(%{status: :refused}) |> Repo.update()
    assert refused.status == :refused
  end

  test "multiple levies can exist for the same lord and vassal against different targets" do
    attrs = valid_attrs()
    assert {:ok, _first} = Levy.changeset(%Levy{}, attrs) |> Repo.insert()

    {:ok, second_target} =
      %Player{}
      |> Player.changeset(%{
        world_id: attrs.world_id,
        user_id: UsersFixtures.user_fixture().id,
        region_id: 4,
        joined_turn: 0
      })
      |> Repo.insert()

    second_attrs = %{attrs | target_player_id: second_target.id}
    assert {:ok, _second} = Levy.changeset(%Levy{}, second_attrs) |> Repo.insert()
  end
end
