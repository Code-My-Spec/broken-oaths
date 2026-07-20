defmodule BrokenOaths.Chat.MessageTest do
  use BrokenOathsTest.DataCase, async: true

  alias BrokenOaths.Chat.Conversation
  alias BrokenOaths.Chat.Message
  alias BrokenOaths.Players.Player
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures

  defp conversation_fixture do
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

    {:ok, conversation} =
      %Conversation{}
      |> Conversation.changeset(%{
        world_id: world.id,
        player_a_id: player_a.id,
        player_b_id: player_b.id
      })
      |> Repo.insert()

    {conversation, player_a, player_b}
  end

  defp valid_attrs do
    {conversation, player_a, _player_b} = conversation_fixture()

    %{
      conversation_id: conversation.id,
      sender_player_id: player_a.id,
      body: "Shall we clear that camp together?"
    }
  end

  test "changeset with valid attrs is valid" do
    changeset = Message.changeset(%Message{}, valid_attrs())
    assert changeset.valid?
  end

  test "changeset requires conversation_id, sender_player_id, and body" do
    changeset = Message.changeset(%Message{}, %{})
    refute changeset.valid?

    assert %{
             conversation_id: ["can't be blank"],
             sender_player_id: ["can't be blank"],
             body: ["can't be blank"]
           } = errors_on(changeset)
  end

  test "a body of exactly 500 characters is valid" do
    attrs = %{valid_attrs() | body: String.duplicate("a", 500)}
    changeset = Message.changeset(%Message{}, attrs)
    assert changeset.valid?
  end

  test "a body over 500 characters is rejected" do
    attrs = %{valid_attrs() | body: String.duplicate("a", 501)}
    changeset = Message.changeset(%Message{}, attrs)
    refute changeset.valid?
    assert %{body: ["should be at most 500 character(s)"]} = errors_on(changeset)
  end

  test "an empty body is rejected" do
    attrs = %{valid_attrs() | body: ""}
    changeset = Message.changeset(%Message{}, attrs)
    refute changeset.valid?
    assert %{body: ["can't be blank"]} = errors_on(changeset)
  end

  test "persists and can be read back ordered by insertion" do
    {conversation, player_a, player_b} = conversation_fixture()

    {:ok, first} =
      %Message{}
      |> Message.changeset(%{
        conversation_id: conversation.id,
        sender_player_id: player_a.id,
        body: "first"
      })
      |> Repo.insert()

    {:ok, second} =
      %Message{}
      |> Message.changeset(%{
        conversation_id: conversation.id,
        sender_player_id: player_b.id,
        body: "second"
      })
      |> Repo.insert()

    ids =
      Message
      |> Ecto.Query.where(conversation_id: ^conversation.id)
      |> Ecto.Query.order_by(:inserted_at)
      |> Repo.all()
      |> Enum.map(& &1.id)

    assert ids == [first.id, second.id]
  end
end
