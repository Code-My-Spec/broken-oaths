defmodule BrokenOaths.Game.GoldLogTest do
  use BrokenOathsTest.DataCase, async: true

  alias BrokenOaths.Game.GoldLog
  alias BrokenOaths.Game.Player
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures

  defp two_players_fixture do
    world = WorldsFixtures.world_fixture()

    [from_player, to_player] =
      [UsersFixtures.user_fixture(), UsersFixtures.user_fixture()]
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

    {world, from_player, to_player}
  end

  defp valid_attrs do
    {world, from_player, to_player} = two_players_fixture()

    %{
      world_id: world.id,
      from_player_id: from_player.id,
      to_player_id: to_player.id,
      turn: 3,
      amount: 12
    }
  end

  test "changeset with valid attrs is valid" do
    changeset = GoldLog.changeset(%GoldLog{}, valid_attrs())
    assert changeset.valid?
  end

  test "reason defaults to :tribute" do
    {:ok, gold_log} = GoldLog.changeset(%GoldLog{}, valid_attrs()) |> Repo.insert()
    assert gold_log.reason == :tribute
  end

  test "changeset requires world_id, from_player_id, to_player_id, turn, and amount" do
    changeset = GoldLog.changeset(%GoldLog{}, %{})
    refute changeset.valid?

    assert %{
             world_id: ["can't be blank"],
             from_player_id: ["can't be blank"],
             to_player_id: ["can't be blank"],
             turn: ["can't be blank"],
             amount: ["can't be blank"]
           } = errors_on(changeset)
  end

  test "amount cannot be negative" do
    attrs = Map.put(valid_attrs(), :amount, -1)
    changeset = GoldLog.changeset(%GoldLog{}, attrs)
    refute changeset.valid?
    assert %{amount: ["must be greater than or equal to 0"]} = errors_on(changeset)
  end

  test "amount of 0 is a valid ledger entry (a vassal with no income owes nothing)" do
    attrs = Map.put(valid_attrs(), :amount, 0)
    changeset = GoldLog.changeset(%GoldLog{}, attrs)
    assert changeset.valid?
  end

  test "turn cannot be negative" do
    attrs = Map.put(valid_attrs(), :turn, -1)
    changeset = GoldLog.changeset(%GoldLog{}, attrs)
    refute changeset.valid?
    assert %{turn: ["must be greater than or equal to 0"]} = errors_on(changeset)
  end

  test "reason must be a known reason" do
    attrs = Map.put(valid_attrs(), :reason, :plunder)
    changeset = GoldLog.changeset(%GoldLog{}, attrs)
    refute changeset.valid?
    assert %{reason: ["is invalid"]} = errors_on(changeset)
  end

  test "from_player_id and to_player_id must be distinct" do
    attrs = valid_attrs()
    changeset = GoldLog.changeset(%GoldLog{}, %{attrs | to_player_id: attrs.from_player_id})
    refute changeset.valid?
    assert %{to_player_id: ["can't be the same as the from player"]} = errors_on(changeset)
  end

  test "both parties can see the same entry — a plain fetch by id round-trips every field" do
    attrs = valid_attrs()
    {:ok, gold_log} = GoldLog.changeset(%GoldLog{}, attrs) |> Repo.insert()

    fetched = Repo.get!(GoldLog, gold_log.id)
    assert fetched.world_id == attrs.world_id
    assert fetched.from_player_id == attrs.from_player_id
    assert fetched.to_player_id == attrs.to_player_id
    assert fetched.turn == attrs.turn
    assert fetched.amount == attrs.amount
    assert fetched.reason == :tribute
  end

  test "many gold log entries can accumulate for the same pair across turns" do
    attrs = valid_attrs()
    assert {:ok, _turn_3} = GoldLog.changeset(%GoldLog{}, attrs) |> Repo.insert()

    next_turn_attrs = %{attrs | turn: 4, amount: 15}
    assert {:ok, _turn_4} = GoldLog.changeset(%GoldLog{}, next_turn_attrs) |> Repo.insert()

    assert Repo.aggregate(GoldLog, :count) == 2
  end
end
