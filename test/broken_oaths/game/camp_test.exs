defmodule BrokenOaths.Game.CampTest do
  use BrokenOathsTest.DataCase, async: true

  alias BrokenOaths.Game.Camp
  alias BrokenOaths.WorldsFixtures

  defp valid_attrs do
    world = WorldsFixtures.world_fixture()
    %{world_id: world.id, tile_id: 7, hp: 100, spawn_counter: 0}
  end

  test "changeset with valid attrs is valid" do
    changeset = Camp.changeset(%Camp{}, valid_attrs())
    assert changeset.valid?
  end

  test "changeset requires world_id and tile_id" do
    changeset = Camp.changeset(%Camp{}, %{})
    refute changeset.valid?

    # hp/spawn_counter aren't "blank" against a fresh %Camp{} struct —
    # both have schema defaults (100/0), already present before cast.
    assert %{world_id: ["can't be blank"], tile_id: ["can't be blank"]} = errors_on(changeset)
  end

  test "hp and spawn_counter are required when explicitly nulled out" do
    changeset = Camp.changeset(%Camp{}, %{valid_attrs() | hp: nil, spawn_counter: nil})
    refute changeset.valid?
    assert %{hp: ["can't be blank"], spawn_counter: ["can't be blank"]} = errors_on(changeset)
  end

  test "hp defaults to 100 when omitted from the struct" do
    assert %Camp{}.hp == 100
  end

  test "hp cannot exceed 100" do
    changeset = Camp.changeset(%Camp{}, %{valid_attrs() | hp: 101})
    refute changeset.valid?
    assert %{hp: ["must be less than or equal to 100"]} = errors_on(changeset)
  end

  test "hp cannot be negative" do
    changeset = Camp.changeset(%Camp{}, %{valid_attrs() | hp: -1})
    refute changeset.valid?
    assert %{hp: ["must be greater than or equal to 0"]} = errors_on(changeset)
  end

  test "hp can be zero (destroyed)" do
    changeset = Camp.changeset(%Camp{}, %{valid_attrs() | hp: 0})
    assert changeset.valid?
  end

  test "spawn_counter cannot be negative" do
    changeset = Camp.changeset(%Camp{}, %{valid_attrs() | spawn_counter: -1})
    refute changeset.valid?
    assert %{spawn_counter: ["must be greater than or equal to 0"]} = errors_on(changeset)
  end

  test "destroyed_at is optional" do
    changeset = Camp.changeset(%Camp{}, valid_attrs())
    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :destroyed_at) == nil
  end

  test "only one camp per tile per world" do
    attrs = valid_attrs()
    assert {:ok, _camp} = Camp.changeset(%Camp{}, attrs) |> Repo.insert()

    {:error, changeset} = Camp.changeset(%Camp{}, attrs) |> Repo.insert()
    assert %{world_id: ["has already been taken"]} = errors_on(changeset)
  end

  test "max_hp/0 is 100" do
    assert Camp.max_hp() == 100
  end
end
