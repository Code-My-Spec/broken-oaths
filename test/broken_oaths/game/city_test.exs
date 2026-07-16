defmodule BrokenOaths.Game.CityTest do
  use BrokenOathsTest.DataCase, async: true

  alias BrokenOaths.Game.City
  alias BrokenOaths.Game.Player
  alias BrokenOaths.Game.ProductionItem
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures

  defp player_fixture(world, region_id \\ 1) do
    user = UsersFixtures.user_fixture()

    {:ok, player} =
      %Player{}
      |> Player.changeset(%{world_id: world.id, user_id: user.id, region_id: region_id, joined_turn: 0})
      |> Repo.insert()

    player
  end

  defp valid_attrs do
    world = WorldsFixtures.world_fixture()
    player = player_fixture(world)

    %{
      world_id: world.id,
      player_id: player.id,
      tile_id: 7,
      name: "Oakhaven",
      size: 1,
      food: 0,
      territory: [7, 8, 9],
      worked_tiles: [8]
    }
  end

  test "changeset with valid attrs is valid" do
    changeset = City.changeset(%City{}, valid_attrs())
    assert changeset.valid?
  end

  test "changeset requires world_id, player_id, tile_id, and name — size/food default instead" do
    changeset = City.changeset(%City{}, %{})
    refute changeset.valid?

    assert %{
             world_id: ["can't be blank"],
             player_id: ["can't be blank"],
             tile_id: ["can't be blank"],
             name: ["can't be blank"]
           } = errors_on(changeset)
  end

  test "territory and worked_tiles default to an empty list" do
    attrs = valid_attrs() |> Map.delete(:territory) |> Map.delete(:worked_tiles)
    {:ok, city} = %City{} |> City.changeset(attrs) |> Repo.insert()
    assert city.territory == []
    assert city.worked_tiles == []
  end

  test "name cannot be blank" do
    changeset = City.changeset(%City{}, %{valid_attrs() | name: ""})
    refute changeset.valid?
    assert %{name: ["can't be blank"]} = errors_on(changeset)
  end

  test "size must be within the Stone Age range of 1 to 4" do
    changeset = City.changeset(%City{}, %{valid_attrs() | size: 0})
    refute changeset.valid?
    assert %{size: ["must be greater than or equal to 1"]} = errors_on(changeset)

    changeset = City.changeset(%City{}, %{valid_attrs() | size: 5})
    refute changeset.valid?
    assert %{size: ["must be less than or equal to 4"]} = errors_on(changeset)
  end

  test "food cannot be negative" do
    changeset = City.changeset(%City{}, %{valid_attrs() | food: -1})
    refute changeset.valid?
    assert %{food: ["must be greater than or equal to 0"]} = errors_on(changeset)
  end

  test "worked_tiles cannot exceed size — a citizen can be idle, never doubled up" do
    attrs = %{valid_attrs() | size: 1, worked_tiles: [8, 9]}
    changeset = City.changeset(%City{}, attrs)
    refute changeset.valid?
    assert %{worked_tiles: ["cannot exceed size"]} = errors_on(changeset)
  end

  test "worked_tiles shorter than size is valid — a citizen can be manually unassigned" do
    attrs = %{valid_attrs() | size: 2, worked_tiles: []}
    assert City.changeset(%City{}, attrs).valid?
  end

  test "only one city per tile per world" do
    attrs = valid_attrs()
    assert {:ok, _city} = %City{} |> City.changeset(attrs) |> Repo.insert()

    other_player = player_fixture(%{id: attrs.world_id}, 2)
    dup_attrs = %{attrs | player_id: other_player.id}

    {:error, changeset} = %City{} |> City.changeset(dup_attrs) |> Repo.insert()
    assert %{world_id: ["has already been taken"]} = errors_on(changeset)
  end

  test "a city's production_items preload as an empty list until items are queued" do
    {:ok, city} = %City{} |> City.changeset(valid_attrs()) |> Repo.insert()
    city = Repo.preload(city, :production_items)
    assert city.production_items == []

    {:ok, _item} =
      %ProductionItem{}
      |> ProductionItem.changeset(%{city_id: city.id, type: :warrior, banked: 0, cost: 40, position: 1})
      |> Repo.insert()

    reloaded = City |> Repo.get!(city.id) |> Repo.preload(:production_items)
    assert [%ProductionItem{type: :warrior}] = reloaded.production_items
  end
end
