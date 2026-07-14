defmodule BrokenOaths.Game.OrderTest do
  use BrokenOathsTest.DataCase, async: true

  alias BrokenOaths.Game.Order
  alias BrokenOaths.Game.Player
  alias BrokenOaths.Game.Unit
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures

  defp unit_fixture do
    world = WorldsFixtures.world_fixture()
    user = UsersFixtures.user_fixture()

    {:ok, player} =
      %Player{}
      |> Player.changeset(%{
        world_id: world.id,
        user_id: user.id,
        region_id: 1,
        joined_turn: 0
      })
      |> Repo.insert()

    {:ok, unit} =
      %Unit{}
      |> Unit.changeset(%{
        world_id: world.id,
        player_id: player.id,
        type: :settler,
        tile_id: 42,
        hp: 5,
        max_hp: 5,
        movement: 2,
        max_movement: 2
      })
      |> Repo.insert()

    unit
  end

  defp valid_attrs do
    unit = unit_fixture()
    %{unit_id: unit.id, kind: :move, path: [43, 44, 45], status: :pending}
  end

  test "changeset with valid attrs is valid" do
    changeset = Order.changeset(%Order{}, valid_attrs())
    assert changeset.valid?
  end

  test "changeset requires unit_id and kind, and rejects an empty path" do
    changeset = Order.changeset(%Order{}, %{})
    refute changeset.valid?

    assert %{
             unit_id: ["can't be blank"],
             kind: ["can't be blank"],
             path: ["should have at least 1 item(s)"]
           } = errors_on(changeset)
  end

  test "status defaults to pending when not supplied" do
    attrs = valid_attrs() |> Map.delete(:status)
    changeset = Order.changeset(%Order{}, attrs)
    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :status) == :pending
  end

  test "kind must be move" do
    changeset = Order.changeset(%Order{}, %{valid_attrs() | kind: :attack})
    refute changeset.valid?
    assert %{kind: ["is invalid"]} = errors_on(changeset)
  end

  test "status must be pending or interrupted" do
    changeset = Order.changeset(%Order{}, %{valid_attrs() | status: :cancelled})
    refute changeset.valid?
    assert %{status: ["is invalid"]} = errors_on(changeset)
  end

  test "path cannot be empty" do
    changeset = Order.changeset(%Order{}, %{valid_attrs() | path: []})
    refute changeset.valid?
    assert %{path: ["should have at least 1 item(s)"]} = errors_on(changeset)
  end

  test "a unit can only have one active order" do
    attrs = valid_attrs()
    assert {:ok, order} = Order.changeset(%Order{}, attrs) |> Repo.insert()

    {:error, changeset} =
      Order.changeset(%Order{}, %{attrs | path: [50]}) |> Repo.insert()

    assert %{unit_id: ["has already been taken"]} = errors_on(changeset)
    assert order.path == [43, 44, 45]
  end
end
