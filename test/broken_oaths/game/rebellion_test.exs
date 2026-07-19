defmodule BrokenOaths.Game.RebellionTest do
  use BrokenOathsTest.DataCase, async: true

  alias BrokenOaths.Game.OathStrain
  alias BrokenOaths.Game.Player
  alias BrokenOaths.Game.Rebellion
  alias BrokenOaths.Game.Rebellion.Resolution
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures

  # -------------------------------------------------------------------
  # Fixtures
  # -------------------------------------------------------------------

  defp two_players_fixture(world_attrs \\ %{}) do
    world = WorldsFixtures.world_fixture(world_attrs)
    {rebel, lord} = {UsersFixtures.user_fixture(), UsersFixtures.user_fixture()}

    [rebel_player, lord_player] =
      [rebel, lord]
      |> Enum.with_index(1)
      |> Enum.map(fn {user, region_id} ->
        {:ok, player} =
          %Player{}
          |> Player.changeset(%{
            world_id: world.id,
            user_id: user.id,
            region_id: region_id,
            joined_turn: 0
          })
          |> Repo.insert()

        player
      end)

    {world, rebel_player, lord_player}
  end

  defp valid_attrs do
    {world, rebel_player, lord_player} = two_players_fixture()

    %{
      world_id: world.id,
      rebel_player_id: rebel_player.id,
      former_lord_player_id: lord_player.id,
      started_turn: 12,
      risen_city_ids: [1],
      loyal_city_ids: [2],
      army_size: 3
    }
  end

  defp city(id, opts) do
    %{
      id: id,
      player_id: Keyword.get(opts, :player_id, 1),
      tile_id: Keyword.get(opts, :tile_id, id * 100),
      occupied_by_player_id: Keyword.get(opts, :occupied_by_player_id)
    }
  end

  defp active_rebellion(overrides \\ %{}) do
    struct(
      %Rebellion{
        status: :active,
        started_turn: 0,
        risen_city_ids: [1, 2],
        loyal_city_ids: [3],
        army_size: 4,
        rebel_player_id: 100,
        former_lord_player_id: 200,
        world_id: 1
      },
      overrides
    )
  end

  # -------------------------------------------------------------------
  # Rebellion — schema / changeset
  # -------------------------------------------------------------------

  describe "changeset/2" do
    test "is valid with valid attrs" do
      changeset = Rebellion.changeset(%Rebellion{}, valid_attrs())
      assert changeset.valid?
    end

    test "requires world_id, rebel_player_id, former_lord_player_id, started_turn" do
      changeset = Rebellion.changeset(%Rebellion{}, %{})
      refute changeset.valid?

      assert %{
               world_id: ["can't be blank"],
               rebel_player_id: ["can't be blank"],
               former_lord_player_id: ["can't be blank"],
               started_turn: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "status defaults to active" do
      {:ok, rebellion} = Rebellion.changeset(%Rebellion{}, valid_attrs()) |> Repo.insert()
      assert rebellion.status == :active
    end

    test "risen_city_ids/loyal_city_ids/army_size default to empty/zero" do
      {world, rebel_player, lord_player} = two_players_fixture()

      {:ok, rebellion} =
        %Rebellion{}
        |> Rebellion.changeset(%{
          world_id: world.id,
          rebel_player_id: rebel_player.id,
          former_lord_player_id: lord_player.id,
          started_turn: 0
        })
        |> Repo.insert()

      assert rebellion.risen_city_ids == []
      assert rebellion.loyal_city_ids == []
      assert rebellion.army_size == 0
    end

    test "rejects a rebel who is their own former lord" do
      {world, rebel_player, _lord_player} = two_players_fixture()

      changeset =
        Rebellion.changeset(%Rebellion{}, %{
          world_id: world.id,
          rebel_player_id: rebel_player.id,
          former_lord_player_id: rebel_player.id,
          started_turn: 0
        })

      refute changeset.valid?
      assert %{rebel_player_id: ["can't be the same as the former lord"]} = errors_on(changeset)
    end

    test "rejects a negative started_turn" do
      changeset = Rebellion.changeset(%Rebellion{}, Map.put(valid_attrs(), :started_turn, -1))
      refute changeset.valid?
      assert %{started_turn: [_]} = errors_on(changeset)
    end

    test "rejects a negative army_size" do
      changeset = Rebellion.changeset(%Rebellion{}, Map.put(valid_attrs(), :army_size, -1))
      refute changeset.valid?
      assert %{army_size: [_]} = errors_on(changeset)
    end

    test "reparations_gold is optional and nil by default, never crashes the changeset" do
      changeset = Rebellion.changeset(%Rebellion{}, valid_attrs())
      assert changeset.valid?
      assert get_field(changeset, :reparations_gold) == nil
    end

    test "rejects a negative reparations_gold when present" do
      changeset =
        Rebellion.changeset(%Rebellion{}, Map.put(valid_attrs(), :reparations_gold, -5))

      refute changeset.valid?
      assert %{reparations_gold: [_]} = errors_on(changeset)
    end

    test "peace_outcome is required once status is peace" do
      changeset =
        Rebellion.changeset(%Rebellion{}, Map.put(valid_attrs(), :status, "peace"))

      refute changeset.valid?
      assert %{peace_outcome: ["can't be blank"]} = errors_on(changeset)
    end

    test "peace_outcome is forbidden outside of a peace status" do
      changeset =
        Rebellion.changeset(%Rebellion{}, Map.put(valid_attrs(), :peace_outcome, "independence"))

      refute changeset.valid?
      assert %{peace_outcome: ["can only be set when status is peace"]} = errors_on(changeset)
    end

    test "peace with a peace_outcome is valid" do
      attrs =
        valid_attrs()
        |> Map.put(:status, "peace")
        |> Map.put(:peace_outcome, "independence")

      changeset = Rebellion.changeset(%Rebellion{}, attrs)
      assert changeset.valid?
    end
  end

  describe "changeset/2 — status transitions exactly once" do
    test "a persisted, active rebellion may transition to an ended status" do
      {:ok, rebellion} = Rebellion.changeset(%Rebellion{}, valid_attrs()) |> Repo.insert()

      changeset = Rebellion.changeset(rebellion, %{status: "crushed"})
      assert changeset.valid?
    end

    test "an already-ended rebellion may never change status again" do
      {:ok, rebellion} = Rebellion.changeset(%Rebellion{}, valid_attrs()) |> Repo.insert()
      {:ok, crushed} = Rebellion.changeset(rebellion, %{status: "crushed"}) |> Repo.update()

      back_to_active = Rebellion.changeset(crushed, %{status: "active"})
      refute back_to_active.valid?
      assert %{status: [_]} = errors_on(back_to_active)

      to_a_different_ended_status = Rebellion.changeset(crushed, %{status: "peace", peace_outcome: "independence"})
      refute to_a_different_ended_status.valid?
      assert %{status: [_]} = errors_on(to_a_different_ended_status)
    end

    test "re-saving the SAME already-persisted status is a no-op, not a rejected transition" do
      {:ok, rebellion} = Rebellion.changeset(%Rebellion{}, valid_attrs()) |> Repo.insert()
      {:ok, crushed} = Rebellion.changeset(rebellion, %{status: "crushed"}) |> Repo.update()

      changeset = Rebellion.changeset(crushed, %{status: "crushed"})
      assert changeset.valid?
    end

    test "an update that never touches status at all is unaffected by the guard" do
      {:ok, rebellion} = Rebellion.changeset(%Rebellion{}, valid_attrs()) |> Repo.insert()
      {:ok, crushed} = Rebellion.changeset(rebellion, %{status: "crushed"}) |> Repo.update()

      changeset = Rebellion.changeset(crushed, %{army_size: 9})
      assert changeset.valid?
    end
  end

  # -------------------------------------------------------------------
  # Resolution — tyranny_score/2, city_resistance/2
  # -------------------------------------------------------------------

  describe "tyranny_score/2" do
    test "a lord with full Honor and zero tribute scores zero tyranny" do
      assert Resolution.tyranny_score(100, 0.0) == 0
    end

    test "a lord with zero Honor and maximal tribute scores maximal tyranny" do
      assert Resolution.tyranny_score(0, 1.0) == 100
    end

    test "raising tribute_rate, Honor held fixed, only ever raises the score" do
      scores = for rate <- [0.0, 0.25, 0.5, 0.75, 1.0], do: Resolution.tyranny_score(100, rate)
      assert scores == Enum.sort(scores)
    end

    test "falling Honor, tribute_rate held fixed, only ever raises the score" do
      # Honor descends (100 -> 0) while tyranny only ever rises, so the
      # resulting scores already come out in ascending order.
      scores = for honor <- [100, 75, 50, 25, 0], do: Resolution.tyranny_score(honor, 0.25)
      assert scores == Enum.sort(scores)
    end

    test "Honor beyond the 0..100 domain (unclamped elsewhere in this codebase) is tolerated, clamped internally" do
      assert Resolution.tyranny_score(-50, 0.0) == Resolution.tyranny_score(0, 0.0)
      assert Resolution.tyranny_score(500, 0.0) == Resolution.tyranny_score(100, 0.0)
    end

    test "score always stays within 0..100" do
      for honor <- [-100, 0, 50, 100, 300], rate <- [0.0, 0.3, 0.6, 1.0] do
        score = Resolution.tyranny_score(honor, rate)
        assert score >= 0
        assert score <= 100
      end
    end

    test "raises (crashes the process) for an out-of-domain tribute_rate" do
      assert_raise FunctionClauseError, fn -> Resolution.tyranny_score(100, 1.5) end
      assert_raise FunctionClauseError, fn -> Resolution.tyranny_score(100, -0.1) end
    end
  end

  describe "city_resistance/2" do
    test "the same seed and tile_id always resistance to the same value" do
      assert Resolution.city_resistance(42, 7) == Resolution.city_resistance(42, 7)
    end

    test "stays within the 0..100 domain across many seeds/tile_ids" do
      for seed <- 1..10, tile_id <- 1..20 do
        resistance = Resolution.city_resistance(seed, tile_id)
        assert resistance >= 0
        assert resistance <= 100
      end
    end

    test "a different seed can (and typically does) resistance the same tile_id differently" do
      values = for seed <- 1..30, do: Resolution.city_resistance(seed, 99)
      assert Enum.uniq(values) != [hd(values)]
    end
  end

  describe "city_rises?/4 and resolve_risings/4" do
    test "a tyrant (max tyranny) rises every city, regardless of per-city resistance" do
      cities = for id <- 1..50, do: city(id, tile_id: id * 37)

      {risen_ids, loyal_ids} = Resolution.resolve_risings(0, 1.0, 42, cities)

      assert length(risen_ids) == 50
      assert loyal_ids == []
    end

    test "a just, light-handed lord (zero tyranny) keeps almost every city loyal" do
      cities = for id <- 1..50, do: city(id, tile_id: id * 37)

      {risen_ids, loyal_ids} = Resolution.resolve_risings(100, 0.0, 42, cities)

      assert length(risen_ids) <= 3, "expected a just lord to keep the overwhelming majority loyal, got #{length(risen_ids)} risen"
      assert length(loyal_ids) >= 47
    end

    test "resolve_risings/4 is deterministic and repeatable for the same inputs" do
      cities = for id <- 1..20, do: city(id, tile_id: id * 11)

      first = Resolution.resolve_risings(60, 0.5, 7, cities)
      second = Resolution.resolve_risings(60, 0.5, 7, cities)

      assert first == second
    end

    test "resolve_risings/4 partitions every city's own id into exactly one of the two lists" do
      cities = for id <- 1..20, do: city(id, tile_id: id * 11)

      {risen_ids, loyal_ids} = Resolution.resolve_risings(55, 0.4, 7, cities)

      assert Enum.sort(risen_ids ++ loyal_ids) == Enum.map(cities, & &1.id)
    end

    test "city_rises?/4 agrees with the tyranny_score/city_resistance comparison directly" do
      assert Resolution.city_rises?(0, 1.0, 42, 5) == (Resolution.tyranny_score(0, 1.0) >= Resolution.city_resistance(42, 5))
    end
  end

  # -------------------------------------------------------------------
  # Resolution — army_size/1
  # -------------------------------------------------------------------

  describe "army_size/1" do
    test "delegates directly to OathStrain.rebellion_army_size/1" do
      for strain <- [0, 25, 50, 75, 100] do
        assert Resolution.army_size(strain) == OathStrain.rebellion_army_size(strain)
      end
    end
  end

  # -------------------------------------------------------------------
  # Resolution — end conditions
  # -------------------------------------------------------------------

  describe "independence_hold_turns/0" do
    test "is a positive, named constant" do
      # Reconciled to N = 10 against the story-919 spex's own
      # hard-coded placeholder (`Criterion7752Spex`'s own `@hold_turns
      # 10`) during the WorldServer/LiveView wiring pass — see
      # `Resolution`'s own moduledoc.
      assert Resolution.independence_hold_turns() == 10
    end
  end

  describe "crushed?/2" do
    test "false when nothing ever rose" do
      rebellion = active_rebellion(%{risen_city_ids: []})
      cities = [city(3, occupied_by_player_id: 200)]

      refute Resolution.crushed?(rebellion, cities)
    end

    test "true once the former lord holds every risen city again" do
      rebellion = active_rebellion(%{risen_city_ids: [1, 2], former_lord_player_id: 200})

      cities = [
        city(1, occupied_by_player_id: 200),
        city(2, occupied_by_player_id: 200)
      ]

      assert Resolution.crushed?(rebellion, cities)
    end

    test "false while only SOME of the risen cities have been retaken" do
      rebellion = active_rebellion(%{risen_city_ids: [1, 2], former_lord_player_id: 200})

      cities = [
        city(1, occupied_by_player_id: 200),
        city(2, occupied_by_player_id: nil)
      ]

      refute Resolution.crushed?(rebellion, cities)
    end

    test "false when a risen city is occupied by someone other than the former lord" do
      rebellion = active_rebellion(%{risen_city_ids: [1], former_lord_player_id: 200})
      cities = [city(1, occupied_by_player_id: 999)]

      refute Resolution.crushed?(rebellion, cities)
    end
  end

  describe "rebel_defeated?/2" do
    test "true once the rebel has zero free cities left" do
      rebellion = active_rebellion(%{rebel_player_id: 100})
      cities = [city(1, player_id: 100, occupied_by_player_id: 200)]

      assert Resolution.rebel_defeated?(rebellion, cities)
    end

    test "false while the rebel still holds at least one free city" do
      rebellion = active_rebellion(%{rebel_player_id: 100})
      cities = [city(1, player_id: 100, occupied_by_player_id: nil)]

      refute Resolution.rebel_defeated?(rebellion, cities)
    end
  end

  describe "independence_won?/3" do
    test "false when nothing ever rose, no matter how many turns pass" do
      rebellion = active_rebellion(%{risen_city_ids: [], started_turn: 0})
      refute Resolution.independence_won?(rebellion, [], 1000)
    end

    test "false before the hold-turns threshold elapses, even if every risen city is held" do
      rebellion = active_rebellion(%{risen_city_ids: [1], started_turn: 10})
      cities = [city(1, occupied_by_player_id: nil)]

      refute Resolution.independence_won?(rebellion, cities, 10 + Resolution.independence_hold_turns() - 1)
    end

    test "true once the threshold elapses and every risen city is still free" do
      rebellion = active_rebellion(%{risen_city_ids: [1, 2], started_turn: 10})

      cities = [
        city(1, occupied_by_player_id: nil),
        city(2, occupied_by_player_id: nil)
      ]

      assert Resolution.independence_won?(rebellion, cities, 10 + Resolution.independence_hold_turns())
    end

    test "false once the threshold elapses if even one risen city has been reoccupied" do
      rebellion = active_rebellion(%{risen_city_ids: [1, 2], former_lord_player_id: 200, started_turn: 10})

      cities = [
        city(1, occupied_by_player_id: nil),
        city(2, occupied_by_player_id: 200)
      ]

      refute Resolution.independence_won?(rebellion, cities, 10 + Resolution.independence_hold_turns())
    end
  end

  # -------------------------------------------------------------------
  # Resolution — status transitions
  # -------------------------------------------------------------------

  describe "win_independence/1" do
    test "builds a valid :active -> :independence_won changeset" do
      changeset = Resolution.win_independence(active_rebellion())
      assert changeset.valid?
      assert get_field(changeset, :status) == :independence_won
    end

    test "raises (crashes the process) when called on an already-ended rebellion" do
      assert_raise FunctionClauseError, fn ->
        Resolution.win_independence(active_rebellion(%{status: :crushed}))
      end
    end
  end

  describe "crush/1" do
    test "builds a valid :active -> :crushed changeset" do
      changeset = Resolution.crush(active_rebellion())
      assert changeset.valid?
      assert get_field(changeset, :status) == :crushed
    end

    test "raises (crashes the process) when called on an already-ended rebellion" do
      assert_raise FunctionClauseError, fn ->
        Resolution.crush(active_rebellion(%{status: :peace, peace_outcome: :independence}))
      end
    end
  end

  describe "resolve_peace/3" do
    test "builds a valid :active -> :peace changeset for :restored_vassal" do
      changeset = Resolution.resolve_peace(active_rebellion(), :restored_vassal)
      assert changeset.valid?
      assert get_field(changeset, :status) == :peace
      assert get_field(changeset, :peace_outcome) == :restored_vassal
      assert get_field(changeset, :reparations_gold) == nil
    end

    test "builds a valid :active -> :peace changeset for :independence, with optional reparations" do
      changeset = Resolution.resolve_peace(active_rebellion(), :independence, 50)
      assert changeset.valid?
      assert get_field(changeset, :peace_outcome) == :independence
      assert get_field(changeset, :reparations_gold) == 50
    end

    test "nobody loses cities in a peace — only status/peace_outcome/reparations_gold change" do
      rebellion = active_rebellion()
      changeset = Resolution.resolve_peace(rebellion, :independence, 25)

      assert get_field(changeset, :risen_city_ids) == rebellion.risen_city_ids
      assert get_field(changeset, :loyal_city_ids) == rebellion.loyal_city_ids
    end

    test "raises (crashes the process) for a non-binary outcome" do
      bogus_outcome = Enum.random([:something_else])

      assert_raise FunctionClauseError, fn ->
        Resolution.resolve_peace(active_rebellion(), bogus_outcome)
      end
    end

    test "raises (crashes the process) when called on an already-ended rebellion" do
      assert_raise FunctionClauseError, fn ->
        Resolution.resolve_peace(active_rebellion(%{status: :independence_won}), :restored_vassal)
      end
    end
  end

  # -------------------------------------------------------------------
  # Resolution — heir_retained_vassals/3 (story 917)
  # -------------------------------------------------------------------

  describe "heir_retained_vassals/3" do
    test "keeps every vassal who never won independence" do
      rebellions = []
      assert Resolution.heir_retained_vassals(200, [1, 2, 3], rebellions) == [1, 2, 3]
    end

    test "drops a vassal whose rebellion against this lord won independence" do
      rebellions = [active_rebellion(%{rebel_player_id: 1, former_lord_player_id: 200, status: :independence_won})]

      assert Resolution.heir_retained_vassals(200, [1, 2, 3], rebellions) == [2, 3]
    end

    test "an active or crushed rebellion does not cost the vassal their place" do
      rebellions = [
        active_rebellion(%{rebel_player_id: 1, former_lord_player_id: 200, status: :active}),
        active_rebellion(%{rebel_player_id: 2, former_lord_player_id: 200, status: :crushed})
      ]

      assert Resolution.heir_retained_vassals(200, [1, 2, 3], rebellions) == [1, 2, 3]
    end

    test "a won-independence rebellion against a DIFFERENT lord does not affect this lord's own retention" do
      rebellions = [
        active_rebellion(%{rebel_player_id: 1, former_lord_player_id: 999, status: :independence_won})
      ]

      assert Resolution.heir_retained_vassals(200, [1, 2, 3], rebellions) == [1, 2, 3]
    end
  end
end
