defmodule BrokenOaths.Game.VassalageTest do
  use BrokenOathsTest.DataCase, async: true

  alias BrokenOaths.Players.Player
  alias BrokenOaths.Game.Vassalage
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures

  defp two_players_fixture do
    world = WorldsFixtures.world_fixture()
    {lord, vassal} = {UsersFixtures.user_fixture(), UsersFixtures.user_fixture()}

    [lord_player, vassal_player] =
      [lord, vassal]
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

    {world, lord_player, vassal_player}
  end

  defp valid_attrs do
    {world, lord_player, vassal_player} = two_players_fixture()

    %{
      world_id: world.id,
      lord_player_id: lord_player.id,
      vassal_player_id: vassal_player.id
    }
  end

  test "changeset with valid attrs is valid" do
    changeset = Vassalage.changeset(%Vassalage{}, valid_attrs())
    assert changeset.valid?
  end

  test "changeset requires world_id, lord_player_id, and vassal_player_id" do
    changeset = Vassalage.changeset(%Vassalage{}, %{})
    refute changeset.valid?

    assert %{
             world_id: ["can't be blank"],
             lord_player_id: ["can't be blank"],
             vassal_player_id: ["can't be blank"]
           } = errors_on(changeset)
  end

  test "tribute_rate defaults to 0.25" do
    {:ok, vassalage} = Vassalage.changeset(%Vassalage{}, valid_attrs()) |> Repo.insert()
    assert vassalage.tribute_rate == 0.25
  end

  test "oath_strain defaults to 0" do
    {:ok, vassalage} = Vassalage.changeset(%Vassalage{}, valid_attrs()) |> Repo.insert()
    assert vassalage.oath_strain == 0
  end

  test "hidden_agenda defaults to nil (chosen later, at the Oath screen)" do
    {:ok, vassalage} = Vassalage.changeset(%Vassalage{}, valid_attrs()) |> Repo.insert()
    assert vassalage.hidden_agenda == nil
  end

  test "contract_terms defaults to an empty map" do
    {:ok, vassalage} = Vassalage.changeset(%Vassalage{}, valid_attrs()) |> Repo.insert()
    assert vassalage.contract_terms == %{}
  end

  test "status defaults to :active" do
    {:ok, vassalage} = Vassalage.changeset(%Vassalage{}, valid_attrs()) |> Repo.insert()
    assert vassalage.status == :active
  end

  test "a lord cannot be their own vassal" do
    attrs = valid_attrs()
    changeset = Vassalage.changeset(%Vassalage{}, %{attrs | vassal_player_id: attrs.lord_player_id})
    refute changeset.valid?
    assert %{vassal_player_id: ["can't be the same as the lord"]} = errors_on(changeset)
  end

  test "tribute_rate must fall within 0 and 1" do
    attrs = Map.put(valid_attrs(), :tribute_rate, 1.5)
    changeset = Vassalage.changeset(%Vassalage{}, attrs)
    refute changeset.valid?
    assert %{tribute_rate: [_]} = errors_on(changeset)

    attrs = Map.put(valid_attrs(), :tribute_rate, -0.1)
    changeset = Vassalage.changeset(%Vassalage{}, attrs)
    refute changeset.valid?
    assert %{tribute_rate: [_]} = errors_on(changeset)
  end

  test "oath_strain must fall within 0 and 100" do
    attrs = Map.put(valid_attrs(), :oath_strain, 101)
    changeset = Vassalage.changeset(%Vassalage{}, attrs)
    refute changeset.valid?
    assert %{oath_strain: [_]} = errors_on(changeset)

    attrs = Map.put(valid_attrs(), :oath_strain, -1)
    changeset = Vassalage.changeset(%Vassalage{}, attrs)
    refute changeset.valid?
    assert %{oath_strain: [_]} = errors_on(changeset)
  end

  test "hidden_agenda accepts every Hidden Agenda v1 option" do
    for agenda <- [:restore, :usurp, :kingmaker, :merchant_prince] do
      attrs = Map.put(valid_attrs(), :hidden_agenda, agenda)
      changeset = Vassalage.changeset(%Vassalage{}, attrs)
      assert changeset.valid?
    end
  end

  test "hidden_agenda refuses an unknown option" do
    attrs = Map.put(valid_attrs(), :hidden_agenda, :conqueror)
    changeset = Vassalage.changeset(%Vassalage{}, attrs)
    refute changeset.valid?
    assert %{hidden_agenda: [_]} = errors_on(changeset)
  end

  test "status refuses an unknown option" do
    attrs = Map.put(valid_attrs(), :status, :sworn)
    changeset = Vassalage.changeset(%Vassalage{}, attrs)
    refute changeset.valid?
    assert %{status: [_]} = errors_on(changeset)
  end

  test "status may be :active or :broken" do
    for status <- [:active, :broken] do
      attrs = Map.put(valid_attrs(), :status, status)
      changeset = Vassalage.changeset(%Vassalage{}, attrs)
      assert changeset.valid?
    end
  end

  test "contract_terms carries an arbitrary reciprocal-duties bag" do
    attrs = Map.put(valid_attrs(), :contract_terms, %{"protection" => true, "spoils_share" => 0.1})
    {:ok, vassalage} = Vassalage.changeset(%Vassalage{}, attrs) |> Repo.insert()
    assert vassalage.contract_terms == %{"protection" => true, "spoils_share" => 0.1}
  end

  test "an agenda can be chosen via a second changeset (the Oath screen commit)" do
    {:ok, vassalage} = Vassalage.changeset(%Vassalage{}, valid_attrs()) |> Repo.insert()

    assert {:ok, chosen} =
             vassalage |> Vassalage.changeset(%{hidden_agenda: :usurp}) |> Repo.update()

    assert chosen.hidden_agenda == :usurp
  end

  test "a vassal cannot serve two lords at once in the same world" do
    attrs = valid_attrs()
    assert {:ok, _first} = Vassalage.changeset(%Vassalage{}, attrs) |> Repo.insert()

    {:ok, second_lord} =
      %Player{}
      |> Player.changeset(%{
        world_id: attrs.world_id,
        user_id: UsersFixtures.user_fixture().id,
        region_id: 3,
        joined_turn: 0
      })
      |> Repo.insert()

    second_attrs = %{attrs | lord_player_id: second_lord.id}

    assert {:error, changeset} = Vassalage.changeset(%Vassalage{}, second_attrs) |> Repo.insert()
    assert %{world_id: [_]} = errors_on(changeset)
  end
end
