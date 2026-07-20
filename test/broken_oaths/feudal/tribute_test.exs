defmodule BrokenOaths.Feudal.TributeTest do
  use BrokenOathsTest.DataCase, async: true

  alias BrokenOaths.Players.Player
  alias BrokenOaths.Feudal.Tribute
  alias BrokenOaths.Feudal.Vassalage
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures

  defp world_with_players(count) do
    world = WorldsFixtures.world_fixture()

    players =
      for region_id <- 1..count do
        {:ok, player} =
          %Player{}
          |> Player.changeset(%{
            world_id: world.id,
            user_id: UsersFixtures.user_fixture().id,
            region_id: region_id,
            joined_turn: 0
          })
          |> Repo.insert()

        player
      end

    {world, players}
  end

  defp vassalage_fixture(world, lord, vassal, overrides \\ %{}) do
    attrs =
      Map.merge(
        %{world_id: world.id, lord_player_id: lord.id, vassal_player_id: vassal.id},
        overrides
      )

    {:ok, vassalage} = Vassalage.changeset(%Vassalage{}, attrs) |> Repo.insert()
    vassalage
  end

  describe "tribute_amount/2" do
    test "12 gold/turn at the default 25% pays exactly 3" do
      assert Tribute.tribute_amount(12, 0.25) == 3
    end

    test "20 gold/turn at 50% pays exactly 10" do
      assert Tribute.tribute_amount(20, 0.5) == 10
    end

    test "rounds to the nearest gold" do
      assert Tribute.tribute_amount(10, 0.25) == 3
    end

    test "zero income pays nothing" do
      assert Tribute.tribute_amount(0, 0.25) == 0
    end

    test "negative income never pays negative tribute" do
      assert Tribute.tribute_amount(-5, 0.25) == 0
    end
  end

  describe "collect/3" do
    test "moves the computed tribute from vassal to lord" do
      players = %{1 => %{gold: 100}, 2 => %{gold: 50}}
      vassalage = %Vassalage{lord_player_id: 1, vassal_player_id: 2, tribute_rate: 0.25}

      {new_players, tribute} = Tribute.collect(players, vassalage, 12)

      assert tribute == 3
      assert new_players[2].gold == 47
      assert new_players[1].gold == 103
    end

    test "an empty treasury goes into debt rather than floor at zero" do
      players = %{1 => %{gold: 0}, 2 => %{gold: 0}}
      vassalage = %Vassalage{lord_player_id: 1, vassal_player_id: 2, tribute_rate: 0.25}

      {new_players, tribute} = Tribute.collect(players, vassalage, 12)

      assert tribute == 3
      assert new_players[2].gold == -3
    end

    test "zero income moves nothing and leaves players untouched" do
      players = %{1 => %{gold: 100}, 2 => %{gold: 50}}
      vassalage = %Vassalage{lord_player_id: 1, vassal_player_id: 2, tribute_rate: 0.25}

      {new_players, tribute} = Tribute.collect(players, vassalage, 0)

      assert tribute == 0
      assert new_players == players
    end
  end

  describe "collect_all/5" do
    test "resolves several active vassalages in a single pass, each its own tribute and log entry" do
      players = %{1 => %{gold: 0}, 2 => %{gold: 100}, 3 => %{gold: 100}, 4 => %{gold: 100}}

      vassalages = [
        %Vassalage{lord_player_id: 1, vassal_player_id: 2, tribute_rate: 0.25, status: :active},
        %Vassalage{lord_player_id: 1, vassal_player_id: 3, tribute_rate: 0.25, status: :active},
        %Vassalage{lord_player_id: 1, vassal_player_id: 4, tribute_rate: 0.25, status: :active}
      ]

      income = %{2 => 12, 3 => 12, 4 => 12}

      {new_players, logs} = Tribute.collect_all(vassalages, players, income, 99, 5)

      assert new_players[2].gold == 97
      assert new_players[3].gold == 97
      assert new_players[4].gold == 97
      assert new_players[1].gold == 9

      assert length(logs) == 3
      assert Enum.all?(logs, &(&1.amount == 3 and &1.turn == 5 and &1.world_id == 99 and &1.reason == :tribute))
      assert Enum.map(logs, & &1.to_player_id) |> Enum.uniq() == [1]
      assert Enum.map(logs, & &1.from_player_id) |> Enum.sort() == [2, 3, 4]
    end

    test "an income-less vassal contributes no log entry" do
      players = %{1 => %{gold: 0}, 2 => %{gold: 100}}

      vassalages = [
        %Vassalage{lord_player_id: 1, vassal_player_id: 2, tribute_rate: 0.25, status: :active}
      ]

      {new_players, logs} = Tribute.collect_all(vassalages, players, %{}, 1, 1)

      assert new_players == players
      assert logs == []
    end

    test "a broken (non-active) vassalage never collects" do
      players = %{1 => %{gold: 0}, 2 => %{gold: 100}}

      vassalages = [
        %Vassalage{lord_player_id: 1, vassal_player_id: 2, tribute_rate: 0.25, status: :broken}
      ]

      {new_players, logs} = Tribute.collect_all(vassalages, players, %{2 => 12}, 1, 1)

      assert new_players == players
      assert logs == []
    end

    test "a raised rate is reflected on the very next collection" do
      players = %{1 => %{gold: 0}, 2 => %{gold: 100}}

      vassalage = %Vassalage{lord_player_id: 1, vassal_player_id: 2, tribute_rate: 0.5, status: :active}

      {new_players, [log]} = Tribute.collect_all([vassalage], players, %{2 => 20}, 1, 1)

      assert log.amount == 10
      assert new_players[2].gold == 90
      assert new_players[1].gold == 10
    end
  end

  describe "set_rate_changeset/2" do
    test "raises the tribute rate" do
      {world, [lord, vassal]} = world_with_players(2)
      vassalage = vassalage_fixture(world, lord, vassal)

      assert {:ok, updated} = Tribute.set_rate_changeset(vassalage, 0.5) |> Repo.update()
      assert updated.tribute_rate == 0.5
    end
  end

  describe "call to arms" do
    setup do
      {world, [lord, vassal, target]} = world_with_players(3)
      %{world: world, lord: lord, vassal: vassal, target: target}
    end

    test "issue_changeset/5 builds a pending levy against a third player", %{
      world: world,
      lord: lord,
      vassal: vassal,
      target: target
    } do
      changeset = Tribute.issue_changeset(world.id, lord.id, vassal.id, target.id, 0.5)
      assert changeset.valid?

      {:ok, levy} = Repo.insert(changeset)
      assert levy.status == :pending
      assert levy.pledged_share == 0.5
    end

    test "answer_changeset/1 marks a levy answered", %{
      world: world,
      lord: lord,
      vassal: vassal,
      target: target
    } do
      {:ok, levy} =
        Tribute.issue_changeset(world.id, lord.id, vassal.id, target.id, 0.5) |> Repo.insert()

      assert {:ok, answered} = Tribute.answer_changeset(levy) |> Repo.update()
      assert answered.status == :answered
    end

    test "refuse_changeset/1 marks a levy refused", %{
      world: world,
      lord: lord,
      vassal: vassal,
      target: target
    } do
      {:ok, levy} =
        Tribute.issue_changeset(world.id, lord.id, vassal.id, target.id, 0.5) |> Repo.insert()

      assert {:ok, refused} = Tribute.refuse_changeset(levy) |> Repo.update()
      assert refused.status == :refused
    end
  end

  describe "spike_oath_strain/1" do
    test "raises oath_strain from a fresh 0 by the refusal spike" do
      {world, [lord, vassal]} = world_with_players(2)
      vassalage = vassalage_fixture(world, lord, vassal)
      assert vassalage.oath_strain == 0

      {:ok, spiked} = Tribute.spike_oath_strain(vassalage) |> Repo.update()
      assert spiked.oath_strain == Tribute.oath_strain_refusal_spike()
      assert spiked.oath_strain > 0
    end

    test "clamps at 100 across repeated refusals" do
      {world, [lord, vassal]} = world_with_players(2)
      vassalage = vassalage_fixture(world, lord, vassal, %{oath_strain: 95})

      {:ok, spiked} = Tribute.spike_oath_strain(vassalage) |> Repo.update()
      assert spiked.oath_strain == 100
    end
  end
end
