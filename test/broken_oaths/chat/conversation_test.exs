defmodule BrokenOaths.Chat.ConversationTest do
  use BrokenOathsTest.DataCase, async: true

  alias BrokenOaths.Chat.Conversation
  alias BrokenOaths.Game.Player
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
      player_b_id: player_b.id
    }
  end

  test "changeset with valid attrs is valid" do
    changeset = Conversation.changeset(%Conversation{}, valid_attrs())
    assert changeset.valid?
  end

  test "changeset requires world_id, player_a_id, and player_b_id" do
    changeset = Conversation.changeset(%Conversation{}, %{})
    refute changeset.valid?

    assert %{
             world_id: ["can't be blank"],
             player_a_id: ["can't be blank"],
             player_b_id: ["can't be blank"]
           } = errors_on(changeset)
  end

  test "the two conversation participants must be different" do
    attrs = valid_attrs()
    changeset = Conversation.changeset(%Conversation{}, %{attrs | player_b_id: attrs.player_a_id})
    refute changeset.valid?
    assert %{player_b_id: ["can't be the same as player_a_id"]} = errors_on(changeset)
  end

  test "player_a_id/player_b_id are stored in a canonical (lowest id first) order" do
    attrs = valid_attrs()
    reversed = %{attrs | player_a_id: attrs.player_b_id, player_b_id: attrs.player_a_id}

    changeset = Conversation.changeset(%Conversation{}, reversed)
    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :player_a_id) == attrs.player_a_id
    assert Ecto.Changeset.get_field(changeset, :player_b_id) == attrs.player_b_id
  end

  test "only one conversation may exist per pair of players in a world, regardless of order" do
    attrs = valid_attrs()
    assert {:ok, _conversation} = Conversation.changeset(%Conversation{}, attrs) |> Repo.insert()

    reversed = %{
      attrs
      | player_a_id: attrs.player_b_id,
        player_b_id: attrs.player_a_id
    }

    {:error, changeset} = Conversation.changeset(%Conversation{}, reversed) |> Repo.insert()
    assert %{world_id: ["has already been taken"]} = errors_on(changeset)
  end

  test "the same pair of players may have separate conversations in separate worlds" do
    {world_one, player_a, player_b} = two_players_fixture()
    world_two = WorldsFixtures.world_fixture()

    attrs_one = %{world_id: world_one.id, player_a_id: player_a.id, player_b_id: player_b.id}
    attrs_two = %{world_id: world_two.id, player_a_id: player_a.id, player_b_id: player_b.id}

    assert {:ok, _conversation_one} =
             Conversation.changeset(%Conversation{}, attrs_one) |> Repo.insert()

    assert {:ok, _conversation_two} =
             Conversation.changeset(%Conversation{}, attrs_two) |> Repo.insert()
  end
end
