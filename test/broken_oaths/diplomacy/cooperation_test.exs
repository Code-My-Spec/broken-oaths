defmodule BrokenOaths.Diplomacy.CooperationTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Diplomacy.Alliance
  alias BrokenOaths.Diplomacy.Cooperation

  describe "record_damage/4 and split_bounty/3" do
    test "a sole attacker's own damage still splits into their full share of the bounty" do
      contributions =
        %{}
        |> Cooperation.record_damage(:camp_1, :p1, 100)

      assert Cooperation.split_bounty(contributions, :camp_1, 30) == %{p1: 30}
    end

    test "a 70/30 damage split pays a clean 21/9 gold split" do
      contributions =
        %{}
        |> Cooperation.record_damage(:camp_1, :p1, 70)
        |> Cooperation.record_damage(:camp_1, :p2, 30)

      assert Cooperation.split_bounty(contributions, :camp_1, 30) == %{p1: 21, p2: 9}
    end

    test "a 40/60 damage split pays a clean 12/18 gold split" do
      contributions =
        %{}
        |> Cooperation.record_damage(:camp_1, :p1, 40)
        |> Cooperation.record_damage(:camp_1, :p2, 60)

      assert Cooperation.split_bounty(contributions, :camp_1, 30) == %{p1: 12, p2: 18}
    end

    test "damage from the same player accumulates across multiple strikes" do
      contributions =
        %{}
        |> Cooperation.record_damage(:camp_1, :p1, 10)
        |> Cooperation.record_damage(:camp_1, :p1, 10)
        |> Cooperation.record_damage(:camp_1, :p2, 5)

      assert Cooperation.split_bounty(contributions, :camp_1, 25) == %{p1: 20, p2: 5}
    end

    test "an uneven split always sums to exactly the total reward, with no gold lost to rounding" do
      contributions =
        %{}
        |> Cooperation.record_damage(:camp_1, :p1, 1)
        |> Cooperation.record_damage(:camp_1, :p2, 1)
        |> Cooperation.record_damage(:camp_1, :p3, 1)

      shares = Cooperation.split_bounty(contributions, :camp_1, 10)
      assert Enum.sum(Map.values(shares)) == 10
      assert map_size(shares) == 3
    end

    test "a target with no recorded damage splits nothing" do
      assert Cooperation.split_bounty(%{}, :camp_1, 30) == %{}
    end

    test "contributions to a DIFFERENT target never bleed into this one's split" do
      contributions =
        %{}
        |> Cooperation.record_damage(:camp_1, :p1, 100)
        |> Cooperation.record_damage(:camp_2, :p2, 100)

      assert Cooperation.split_bounty(contributions, :camp_1, 30) == %{p1: 30}
    end

    test "forget/2 drops a target's ledger entirely" do
      contributions =
        %{}
        |> Cooperation.record_damage(:camp_1, :p1, 100)
        |> Cooperation.forget(:camp_1)

      assert Cooperation.split_bounty(contributions, :camp_1, 30) == %{}
    end
  end

  describe "propose/4" do
    test "a fresh proposal (no existing alliance) is valid, proposed by the caller" do
      assert {:ok, changeset} = Cooperation.propose(nil, 1, 10, 20)
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :proposer_player_id) == 10
      assert Ecto.Changeset.get_field(changeset, :status) == :proposed
    end

    test "proposing again once already proposed is refused" do
      existing = %Alliance{status: :proposed}
      assert Cooperation.propose(existing, 1, 10, 20) == {:error, :already_proposed}
    end

    test "proposing again once already accepted is refused" do
      existing = %Alliance{status: :accepted}
      assert Cooperation.propose(existing, 1, 10, 20) == {:error, :already_allied}
    end
  end

  describe "accept/2" do
    test "the non-proposing party may accept a proposed alliance" do
      alliance = %Alliance{
        world_id: 1,
        status: :proposed,
        player_a_id: 10,
        player_b_id: 20,
        proposer_player_id: 10
      }

      assert {:ok, changeset} = Cooperation.accept(alliance, 20)
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :status) == :accepted
    end

    test "the original proposer cannot accept their own proposal" do
      alliance = %Alliance{status: :proposed, player_a_id: 10, player_b_id: 20, proposer_player_id: 10}
      assert Cooperation.accept(alliance, 10) == {:error, :self_accept}
    end

    test "a stranger to the alliance cannot accept it" do
      alliance = %Alliance{status: :proposed, player_a_id: 10, player_b_id: 20, proposer_player_id: 10}
      assert Cooperation.accept(alliance, 99) == {:error, :not_a_party}
    end

    test "an already-accepted alliance cannot be accepted again" do
      alliance = %Alliance{status: :accepted, player_a_id: 10, player_b_id: 20, proposer_player_id: 10}
      assert Cooperation.accept(alliance, 20) == {:error, :already_accepted}
    end
  end
end
