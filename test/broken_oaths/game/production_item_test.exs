defmodule BrokenOaths.Game.ProductionItemTest do
  use BrokenOathsTest.DataCase, async: true

  alias BrokenOaths.Cities.City
  alias BrokenOaths.Players.Player
  alias BrokenOaths.Game.ProductionItem
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures

  defp city_fixture do
    world = WorldsFixtures.world_fixture()
    user = UsersFixtures.user_fixture()

    {:ok, player} =
      %Player{}
      |> Player.changeset(%{world_id: world.id, user_id: user.id, region_id: 1, joined_turn: 0})
      |> Repo.insert()

    {:ok, city} =
      %City{}
      |> City.changeset(%{
        world_id: world.id,
        player_id: player.id,
        tile_id: 7,
        name: "Oakhaven",
        size: 1,
        food: 0
      })
      |> Repo.insert()

    city
  end

  defp valid_attrs do
    %{city_id: city_fixture().id, type: :warrior, banked: 0, cost: 40, position: 1}
  end

  test "changeset with valid attrs is valid" do
    assert ProductionItem.changeset(%ProductionItem{}, valid_attrs()).valid?
  end

  test "changeset requires city_id, type, banked, and cost" do
    changeset = ProductionItem.changeset(%ProductionItem{}, %{})
    refute changeset.valid?

    assert %{
             city_id: ["can't be blank"],
             type: ["can't be blank"],
             cost: ["can't be blank"]
           } = errors_on(changeset)
  end

  test "type must be settler, worker, warrior, or granary" do
    changeset = ProductionItem.changeset(%ProductionItem{}, %{valid_attrs() | type: :monument})
    refute changeset.valid?
    assert %{type: ["is invalid"]} = errors_on(changeset)
  end

  test "granary is a valid type (story 902)" do
    changeset = ProductionItem.changeset(%ProductionItem{}, %{valid_attrs() | type: :granary})
    assert changeset.valid?
  end

  test "banked cannot be negative" do
    changeset = ProductionItem.changeset(%ProductionItem{}, %{valid_attrs() | banked: -1})
    refute changeset.valid?
    assert %{banked: ["must be greater than or equal to 0"]} = errors_on(changeset)
  end

  test "cost must be positive" do
    changeset = ProductionItem.changeset(%ProductionItem{}, %{valid_attrs() | cost: 0})
    refute changeset.valid?
    assert %{cost: ["must be greater than 0"]} = errors_on(changeset)
  end

  test "banked defaults to 0" do
    {:ok, item} = %ProductionItem{} |> ProductionItem.changeset(Map.delete(valid_attrs(), :banked)) |> Repo.insert()
    assert item.banked == 0
  end
end
