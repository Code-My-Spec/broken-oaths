defmodule BrokenOaths.Game.AllianceCommandTest do
  # async: false — exercises a real `Game.WorldServer` (via
  # `Game.join_world/2`), the same reason `BrokenOaths.ChatTest` and
  # `BrokenOaths.Game.WorldServerTest` opt out of async.
  use BrokenOathsTest.DataCase, async: false

  alias BrokenOaths.Game
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures

  defp two_joined_players_fixture(world_attrs \\ %{seed: 424_242, frequency: 8}) do
    world = WorldsFixtures.world_fixture(world_attrs)
    user = UsersFixtures.user_fixture()
    other_user = UsersFixtures.user_fixture()

    {:ok, _player} = Game.join_world(world, user)
    {:ok, _other_player} = Game.join_world(world, other_user)

    %{world: world, user: user, other_user: other_user}
  end

  describe "propose_alliance/3" do
    test "creates a pending alliance visible to both parties" do
      %{world: world, user: user, other_user: other_user} = two_joined_players_fixture()

      assert :ok = Game.propose_alliance(world, user, other_user)

      assert [alliance] = Game.alliances(world, user)
      assert alliance.status == :proposed
      assert alliance.proposed_by_me? == true
      assert alliance.other_user_id == other_user.id

      assert [their_view] = Game.alliances(world, other_user)
      assert their_view.status == :proposed
      assert their_view.proposed_by_me? == false
      assert their_view.other_user_id == user.id
      assert their_view.id == alliance.id
    end

    test "refuses a second proposal once one already exists" do
      %{world: world, user: user, other_user: other_user} = two_joined_players_fixture()

      assert :ok = Game.propose_alliance(world, user, other_user)
      assert {:error, :already_proposed} = Game.propose_alliance(world, other_user, user)
    end

    test "refuses a proposal to someone who never joined the world" do
      %{world: world, user: user} = two_joined_players_fixture()
      stranger = UsersFixtures.user_fixture()

      assert {:error, :not_a_player} = Game.propose_alliance(world, user, stranger)
    end
  end

  describe "accept_alliance/3" do
    test "the other party accepting flips the alliance to accepted for both sides" do
      %{world: world, user: user, other_user: other_user} = two_joined_players_fixture()

      :ok = Game.propose_alliance(world, user, other_user)
      [%{id: alliance_id}] = Game.alliances(world, user)

      assert :ok = Game.accept_alliance(world, other_user, alliance_id)

      assert [%{status: :accepted}] = Game.alliances(world, user)
      assert [%{status: :accepted}] = Game.alliances(world, other_user)
    end

    test "the original proposer cannot accept their own proposal" do
      %{world: world, user: user, other_user: other_user} = two_joined_players_fixture()

      :ok = Game.propose_alliance(world, user, other_user)
      [%{id: alliance_id}] = Game.alliances(world, user)

      assert {:error, :self_accept} = Game.accept_alliance(world, user, alliance_id)
    end

    test "an uninvolved player cannot accept someone else's proposal" do
      # `two_joined_players_fixture/1`'s default world (seed 424242,
      # frequency 8) has exactly TWO spawnable regions (issue
      # 7509b3e6, see story 879's criterion 7472) — a third join needs
      # seed 1 / frequency 9, which deterministically yields three
      # (same fixture story 900's criterion 7605 uses).
      %{world: world, user: user, other_user: other_user} =
        two_joined_players_fixture(%{seed: 1, frequency: 9})

      stranger = UsersFixtures.user_fixture()
      {:ok, _player} = Game.join_world(world, stranger)

      :ok = Game.propose_alliance(world, user, other_user)
      [%{id: alliance_id}] = Game.alliances(world, user)

      assert {:error, :not_a_party} = Game.accept_alliance(world, stranger, alliance_id)
    end
  end
end
