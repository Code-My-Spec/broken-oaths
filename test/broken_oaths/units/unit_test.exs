defmodule BrokenOaths.Units.UnitTest do
  use BrokenOathsTest.DataCase, async: true

  alias BrokenOaths.Players.Player
  alias BrokenOaths.Units.Unit
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.Worlds.World
  alias BrokenOaths.WorldsFixtures

  defp player_fixture(attrs \\ %{}) do
    world = attrs[:world] || WorldsFixtures.world_fixture()
    user = UsersFixtures.user_fixture()

    {:ok, player} =
      %Player{}
      |> Player.changeset(%{
        world_id: world.id,
        user_id: user.id,
        region_id: attrs[:region_id] || 1,
        joined_turn: 0
      })
      |> Repo.insert()

    player
  end

  defp valid_attrs do
    player = player_fixture()

    %{
      world_id: player.world_id,
      player_id: player.id,
      type: :lord,
      tile_id: 42,
      hp: 10,
      max_hp: 10,
      movement: 2,
      max_movement: 2
    }
  end

  test "changeset with valid attrs is valid" do
    changeset = Unit.changeset(%Unit{}, valid_attrs())
    assert changeset.valid?
  end

  test "changeset requires all fields except player_id and camp_id" do
    changeset = Unit.changeset(%Unit{}, %{})
    refute changeset.valid?

    assert %{
             world_id: ["can't be blank"],
             type: ["can't be blank"],
             tile_id: ["can't be blank"],
             hp: ["can't be blank"],
             max_hp: ["can't be blank"],
             movement: ["can't be blank"],
             max_movement: ["can't be blank"]
           } = errors_on(changeset)

    refute Map.has_key?(errors_on(changeset), :player_id)
    refute Map.has_key?(errors_on(changeset), :camp_id)
  end

  test "player_id is nullable — a barbarian warrior has no owner" do
    attrs = %{valid_attrs() | player_id: nil, type: :barbarian_warrior}
    changeset = Unit.changeset(%Unit{}, attrs)
    assert changeset.valid?
  end

  test "type must be lord or settler" do
    changeset = Unit.changeset(%Unit{}, %{valid_attrs() | type: :wizard})
    refute changeset.valid?
    assert %{type: ["is invalid"]} = errors_on(changeset)
  end

  test "hp must be greater than 0" do
    changeset = Unit.changeset(%Unit{}, %{valid_attrs() | hp: 0})
    refute changeset.valid?
    assert %{hp: ["must be greater than 0"]} = errors_on(changeset)
  end

  test "hp cannot exceed max_hp" do
    changeset = Unit.changeset(%Unit{}, %{valid_attrs() | hp: 11, max_hp: 10})
    refute changeset.valid?
    assert %{hp: ["must be less than or equal to max_hp"]} = errors_on(changeset)
  end

  test "movement cannot exceed max_movement" do
    changeset = Unit.changeset(%Unit{}, %{valid_attrs() | movement: 3, max_movement: 2})
    refute changeset.valid?
    assert %{movement: ["must be less than or equal to max_movement"]} = errors_on(changeset)
  end

  test "movement can be zero" do
    changeset = Unit.changeset(%Unit{}, %{valid_attrs() | movement: 0})
    assert changeset.valid?
  end

  # Story 882 playtest update (issue 1caa87e9 — worker build charges):
  # every unit type carries this field (only :worker ever spends it),
  # defaulting to 3 (a fresh Civ 6-style Builder's charge count) when
  # the caller doesn't set it explicitly.
  test "charges defaults to 3 when omitted" do
    changeset = Unit.changeset(%Unit{}, %{valid_attrs() | type: :worker})
    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :charges) == 3
  end

  test "charges can be set explicitly" do
    changeset = Unit.changeset(%Unit{}, Map.put(valid_attrs(), :charges, 1))
    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :charges) == 1
  end

  test "charges cannot be negative" do
    changeset = Unit.changeset(%Unit{}, Map.put(valid_attrs(), :charges, -1))
    refute changeset.valid?
    assert %{charges: ["must be greater than or equal to 0"]} = errors_on(changeset)
  end

  # Story 895: the blanket `(world_id, tile_id)` DB uniqueness this test
  # used to assert was dropped outright by migration
  # `20260716190000_drop_unit_tile_uniqueness_for_city_garrisons` — a
  # city's own tile is now a deliberate stacking exception (up to 3
  # friendly military units, plus any number of civilians; see
  # `BrokenOaths.Combat.CityDefense.garrison_room?/2`), and Postgres has
  # no built-in "unique except on these specific tiles" constraint, so
  # "one unit per hex" moved entirely to the application layer
  # (`WorldServer.occupied_by_own?/4` at queue time, `Turn`'s
  # `attempt_step/4` collision check at tick time — see `garrison_room?/2`'s
  # own test coverage in `city_defense_test.exs` for the exception
  # itself). The changeset/schema layer no longer refuses a same-tile
  # insert at all, which is exactly what this asserts now.
  test "the changeset layer no longer refuses two units sharing a tile" do
    attrs = valid_attrs()
    assert {:ok, _unit} = Unit.changeset(%Unit{}, attrs) |> Repo.insert()

    world = Repo.get!(World, attrs.world_id)
    other_player = player_fixture(%{world: world, region_id: 2})
    dup_attrs = %{attrs | world_id: world.id, player_id: other_player.id}

    assert {:ok, _other_unit} = Unit.changeset(%Unit{}, dup_attrs) |> Repo.insert()
  end
end
