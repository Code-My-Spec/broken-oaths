defmodule BrokenOathsWeb.GameLive.AlliancePanelTest do
  # async: false — exercises a real `Game.WorldServer` (via
  # `Game.join_world/2`), the same reason `BrokenOaths.ChatTest` and
  # `BrokenOaths.Game.AllianceCommandTest` opt out of async.
  use BrokenOathsTest.DataCase, async: false

  import Phoenix.LiveViewTest

  alias BrokenOaths.Game
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures
  alias BrokenOathsWeb.GameLive.AlliancePanel

  defp two_joined_players_fixture(world_attrs \\ %{seed: 424_242, frequency: 8}) do
    world = WorldsFixtures.world_fixture(world_attrs)
    user = UsersFixtures.user_fixture()
    other_user = UsersFixtures.user_fixture()

    {:ok, _player} = Game.join_world(world, user)
    {:ok, _other_player} = Game.join_world(world, other_user)

    %{world: world, user: user, other_user: other_user}
  end

  describe "closed by default" do
    test "always renders the alliance-button, with the panel closed" do
      %{world: world, user: user} = two_joined_players_fixture()

      html =
        render_component(AlliancePanel,
          id: "alliance-panel",
          world: world,
          user: user,
          known_players: []
        )

      assert html =~ ~s(data-test="alliance-button")
      refute html =~ ~s(data-test="alliance-panel")
    end
  end

  describe "propose/accept wiring" do
    test "a proposed alliance appears via Game.alliances/2 for both parties" do
      %{world: world, user: user, other_user: other_user} = two_joined_players_fixture()

      :ok = Game.propose_alliance(world, user, other_user)

      assert [%{status: :proposed, proposed_by_me?: true, other_user_id: other_id}] =
               Game.alliances(world, user)

      assert other_id == other_user.id

      assert [%{status: :proposed, proposed_by_me?: false}] = Game.alliances(world, other_user)
    end

    test "accepting flips both sides to accepted" do
      %{world: world, user: user, other_user: other_user} = two_joined_players_fixture()

      :ok = Game.propose_alliance(world, user, other_user)
      [%{id: alliance_id}] = Game.alliances(world, user)
      :ok = Game.accept_alliance(world, other_user, alliance_id)

      assert [%{status: :accepted}] = Game.alliances(world, user)
      assert [%{status: :accepted}] = Game.alliances(world, other_user)
    end
  end
end
