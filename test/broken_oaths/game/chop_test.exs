defmodule BrokenOaths.Game.ChopTest do
  # async: false — exercises a named, Registry-addressed WorldServer,
  # same status as `FortifyTest`'s own suite.
  use BrokenOathsTest.DataCase, async: false

  import Ecto.Query

  alias BrokenOaths.Cities.Improvement
  alias BrokenOaths.Game
  alias BrokenOaths.Simulation.WorldServer
  alias BrokenOaths.Repo
  alias BrokenOaths.Units.Unit
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.Terrain
  alias BrokenOaths.WorldsFixtures

  @frequency 8

  setup do
    world = WorldsFixtures.world_fixture(%{seed: 424_242, frequency: @frequency})
    user = UsersFixtures.user_fixture()
    {:ok, player} = Game.join_world(world, user)

    # A joined player only ever gets a Lord + a Settler (`Game.join_world/2`)
    # — no city yet, hence no science income at all — so the capital has
    # to be founded (using that same settler) before any research can
    # ever accrue, the same order every research-driving test in
    # `world_server_test.exs` already establishes. `isolate_camp_for_test/2`
    # mirrors that same file's own defensive habit before a long
    # turn-advance loop: nothing about a Chop scenario cares about
    # barbarian activity, so keep it out of the way entirely.
    [settler] = for u <- Game.player_units(world, user), u.type == :settler, do: u
    :ok = Game.found_city(world, user, settler.id)
    :ok = Game.isolate_camp_for_test(world, -1)

    %{world: world, user: user, player: player}
  end

  # Founds a fresh city on a land tile ADJACENT to a `feature` tile —
  # `Production.founding_territory/2` is always the founding tile plus
  # its six neighbors, so this guarantees the feature tile lands in the
  # freshly founded city's own starting territory without needing city
  # growth. Mirrors `found_far_city/3`'s own "spawn a settler, try to
  # found, retry the next candidate on :too_close" technique
  # (`world_server_test.exs`), just filtering candidates on an ADJACENT
  # feature instead of pure spacing. Returns `%{city_id:, tile:}` (the
  # tile is the CHOPPABLE one, a neighbor of the city center) or `nil`.
  defp found_city_near_feature(world, user, player_id, feature) do
    Enum.find_value(0..641, fn tile ->
      if Regions.tile_class(world, tile) == :land do
        chop_tile =
          world
          |> Regions.adjacent_tiles(tile)
          |> Enum.find(fn n ->
            Regions.tile_class(world, n) == :land and
              Regions.terrain(world, n).feature == feature
          end)

        if chop_tile, do: try_found(world, user, player_id, tile, chop_tile)
      end
    end)
  end

  # Same as `found_city_near_feature/4`, but the chop tile must ALSO be
  # flat grassland/plains — the exact shape `Improvement.allowed?(:farm,
  # ...)` needs once cleared — for the "chopped grassland becomes
  # Farm-allowed" scenario.
  defp found_city_near_farmable_woods(world, user, player_id) do
    Enum.find_value(0..641, fn tile ->
      if Regions.tile_class(world, tile) == :land do
        chop_tile =
          world
          |> Regions.adjacent_tiles(tile)
          |> Enum.find(fn n ->
            t = Regions.terrain(world, n)

            Regions.tile_class(world, n) == :land and t.feature == :woods and
              t.relief == :flat and t.base in [:grassland, :plains]
          end)

        if chop_tile, do: try_found(world, user, player_id, tile, chop_tile)
      end
    end)
  end

  defp try_found(world, user, player_id, tile, chop_tile) do
    settler = Game.spawn_unit_for_test(world, player_id, :settler, tile)

    case Game.found_city(world, user, settler.id) do
      :ok ->
        city = Game.player_cities(world, user) |> Enum.find(&(&1.tile_id == tile))
        %{city_id: city.id, tile: chop_tile}

      {:error, _} ->
        nil
    end
  end

  defp research_mining(world, user) do
    :ok = Game.set_research(world, user, :mining)
    complete_current_research(world, user)
    assert :mining in Game.player_research(world, user).completed_techs
  end

  defp research_bronze_working(world, user) do
    research_mining(world, user)
    :ok = Game.set_research(world, user, :bronze_working)
    complete_current_research(world, user)
    assert :bronze_working in Game.player_research(world, user).completed_techs
  end

  # Same 130-turn cap `research_the_wheel/2` (world_server_test.exs)
  # already established as enough for the priciest research any of
  # these helpers drive to completion.
  defp complete_current_research(world, user) do
    Enum.reduce_while(1..130, :ok, fn _, :ok ->
      if Game.player_research(world, user).current_research == nil do
        {:halt, :ok}
      else
        :ok = Game.advance_turn(world)
        {:cont, :ok}
      end
    end)
  end

  defp unit_by_id(world, user, unit_id) do
    Enum.find(Game.player_units(world, user), &(&1.id == unit_id))
  end

  defp city_by_id(world, user, city_id) do
    Enum.find(Game.player_cities(world, user), &(&1.id == city_id))
  end

  describe "chop/3 (story 927 'Workers chop woods and rainforest')" do
    test "removes the feature — terrain now reads feature: nil and movement_cost drops to 1", %{
      world: world,
      user: user,
      player: player
    } do
      research_mining(world, user)
      %{tile: tile} = found_city_near_feature(world, user, player.id, :woods)
      worker = Game.spawn_unit_for_test(world, player.id, :worker, tile)

      assert Terrain.movement_cost(Regions.terrain(world, tile)) == 2
      assert Game.chop(world, user, worker.id) == :ok

      cleared = Game.cleared_features(world)
      assert MapSet.member?(cleared, tile)

      terrain = Regions.terrain(world, tile, cleared)
      assert terrain.feature == nil
      assert Terrain.movement_cost(terrain) == 1
    end

    test "yield is 20 + 8 * the chopping player's own completed-tech count", %{
      world: world,
      user: user,
      player: player
    } do
      research_mining(world, user)
      %{city_id: city_id, tile: tile} = found_city_near_feature(world, user, player.id, :woods)
      worker = Game.spawn_unit_for_test(world, player.id, :worker, tile)

      :ok = Game.queue_production(world, user, city_id, :warrior)
      pr = Game.player_research(world, user)
      assert Improvement.chop_yield(:woods, pr) == 28

      assert Game.chop(world, user, worker.id) == :ok
      assert [%{banked: 28}] = city_by_id(world, user, city_id).queue
    end

    test "Rainforest yields 75% of Woods at the same tech count, rounded down", %{
      world: world,
      user: user,
      player: player
    } do
      research_bronze_working(world, user)

      %{city_id: city_id, tile: tile} =
        found_city_near_feature(world, user, player.id, :rainforest)

      worker = Game.spawn_unit_for_test(world, player.id, :worker, tile)

      :ok = Game.queue_production(world, user, city_id, :warrior)
      pr = Game.player_research(world, user)
      assert Improvement.chop_yield(:rainforest, pr) == 27

      assert Game.chop(world, user, worker.id) == :ok
      assert [%{banked: 27}] = city_by_id(world, user, city_id).queue
    end

    test "overflow beyond the current item's own cost carries to the next queued item at the next turn boundary",
         %{world: world, user: user, player: player} do
      research_mining(world, user)
      %{city_id: city_id, tile: tile} = found_city_near_feature(world, user, player.id, :woods)
      worker = Game.spawn_unit_for_test(world, player.id, :worker, tile)

      :ok = Game.queue_production(world, user, city_id, :warrior)
      :ok = Game.queue_production(world, user, city_id, :worker)

      # This city's own per-turn income (founding auto-works its own
      # best-scoring tile, story 878 — `City.persist_found_city!/3` — so
      # this varies by seed/site, never hardcoded here) times however
      # many turns bank enough that the chop's own lump (28, Woods at 1
      # tech) is guaranteed to push the Warrior (cost 40) over the top —
      # `Improvement.chop_yield/2` already has its own dedicated formula
      # coverage (`improvement_test.exs`); this test's own subject is
      # ONLY the overflow-carries mechanics.
      income = city_by_id(world, user, city_id).production
      lump = Improvement.chop_yield(:woods, Game.player_research(world, user))
      turns = max(1, div(40 - lump, income) + 1)

      for _ <- 1..turns, do: :ok = Game.advance_turn(world)
      pre_chop = city_by_id(world, user, city_id)
      # A sanity check on the "no confound" assumption above: still
      # size 1 (no growth reshuffled territory/worked_tiles mid-loop).
      assert pre_chop.size == 1

      assert [%{type: :warrior, banked: pre_chop_banked}, %{type: :worker, banked: 0}] =
               pre_chop.queue

      assert Game.chop(world, user, worker.id) == :ok

      # `chop/3` only ever credits `banked` — it never runs completion
      # itself, so this is still sitting over cost (40), unresolved.
      after_chop_banked = pre_chop_banked + lump
      assert after_chop_banked > 40

      assert [%{type: :warrior, banked: ^after_chop_banked}, %{type: :worker, banked: 0}] =
               city_by_id(world, user, city_id).queue

      # This turn's own income lands first, THEN the Warrior completes
      # and whatever's left over carries into the Worker right behind
      # it — nothing is wasted.
      :ok = Game.advance_turn(world)
      overflow = after_chop_banked + income - 40
      assert [%{type: :worker, banked: ^overflow}] = city_by_id(world, user, city_id).queue
    end

    test "requires Mining to chop Woods", %{world: world, user: user, player: player} do
      %{tile: tile} = found_city_near_feature(world, user, player.id, :woods)
      worker = Game.spawn_unit_for_test(world, player.id, :worker, tile)

      assert Game.chop(world, user, worker.id) == {:error, :tech_locked}
    end

    test "requires Bronze Working to chop Rainforest — Mining alone isn't enough", %{
      world: world,
      user: user,
      player: player
    } do
      research_mining(world, user)
      %{tile: tile} = found_city_near_feature(world, user, player.id, :rainforest)
      worker = Game.spawn_unit_for_test(world, player.id, :worker, tile)

      assert Game.chop(world, user, worker.id) == {:error, :tech_locked}
    end

    test "spends a worker build charge", %{world: world, user: user, player: player} do
      research_mining(world, user)
      %{tile: tile} = found_city_near_feature(world, user, player.id, :woods)
      worker = Game.spawn_unit_for_test(world, player.id, :worker, tile)
      assert worker.charges == 3

      assert Game.chop(world, user, worker.id) == :ok
      assert unit_by_id(world, user, worker.id).charges == 2
    end

    test "a worker with no charges left can't chop", %{world: world, user: user, player: player} do
      research_mining(world, user)
      %{tile: tile} = found_city_near_feature(world, user, player.id, :woods)
      worker = Game.spawn_unit_for_test(world, player.id, :worker, tile)

      Repo.update_all(from(u in Unit, where: u.id == ^worker.id), set: [charges: 0])
      :ok = WorldServer.restart(world)

      assert Game.chop(world, user, worker.id) == {:error, :no_charges}
    end

    test "a worker chopping on its last charge is expended, same removal path Farm/Mine use", %{
      world: world,
      user: user,
      player: player
    } do
      research_mining(world, user)
      %{tile: tile} = found_city_near_feature(world, user, player.id, :woods)
      worker = Game.spawn_unit_for_test(world, player.id, :worker, tile)

      Repo.update_all(from(u in Unit, where: u.id == ^worker.id), set: [charges: 1])
      :ok = WorldServer.restart(world)

      assert Game.chop(world, user, worker.id) == :ok
      assert unit_by_id(world, user, worker.id) == nil
    end

    test "requires the tile to be inside the chopper's own territory", %{
      world: world,
      user: user,
      player: player
    } do
      research_mining(world, user)
      capital_territory = world |> Game.player_cities(user) |> Enum.flat_map(& &1.territory)

      wild_tile =
        Enum.find(0..641, fn t ->
          Regions.tile_class(world, t) == :land and Regions.terrain(world, t).feature == :woods and
            t not in capital_territory
        end)

      worker = Game.spawn_unit_for_test(world, player.id, :worker, wild_tile)
      assert Game.chop(world, user, worker.id) == {:error, :not_territory}
    end

    test "refuses a tile with a hostile co-occupant", %{world: world, user: user, player: player} do
      research_mining(world, user)
      %{tile: tile} = found_city_near_feature(world, user, player.id, :woods)
      worker = Game.spawn_unit_for_test(world, player.id, :worker, tile)
      _barbarian = Game.spawn_barbarian_for_test(world, tile)

      assert Game.chop(world, user, worker.id) == {:error, :enemy_present}
    end

    test "a chopped grassland becomes Farm-allowed", %{world: world, user: user, player: player} do
      research_mining(world, user)
      %{tile: tile} = found_city_near_farmable_woods(world, user, player.id)
      worker = Game.spawn_unit_for_test(world, player.id, :worker, tile)

      assert Game.start_improvement(world, user, worker.id, :farm) == {:error, :invalid_terrain}

      assert Game.chop(world, user, worker.id) == :ok
      assert Game.start_improvement(world, user, worker.id, :farm) == :ok
    end

    test "refuses a unit_id the caller doesn't own", %{world: world, user: user, player: player} do
      research_mining(world, user)
      %{tile: tile} = found_city_near_feature(world, user, player.id, :woods)
      worker = Game.spawn_unit_for_test(world, player.id, :worker, tile)

      stranger = UsersFixtures.user_fixture()
      {:ok, _stranger_player} = Game.join_world(world, stranger)

      assert Game.chop(world, stranger, worker.id) == {:error, :not_owner}
    end

    test "refuses a non-worker unit", %{world: world, user: user, player: player} do
      research_mining(world, user)
      %{tile: tile} = found_city_near_feature(world, user, player.id, :woods)
      warrior = Game.spawn_unit_for_test(world, player.id, :warrior, tile)

      assert Game.chop(world, user, warrior.id) == {:error, :not_worker}
    end

    test "refuses a tile with no feature to chop", %{world: world, user: user, player: player} do
      research_mining(world, user)

      bare_tile =
        Enum.find(
          0..641,
          &(Regions.tile_class(world, &1) == :land and Regions.terrain(world, &1).feature == nil)
        )

      worker = Game.spawn_unit_for_test(world, player.id, :worker, bare_tile)
      assert Game.chop(world, user, worker.id) == {:error, :not_choppable}
    end

    test "persists cleared_features across a WorldServer restart", %{
      world: world,
      user: user,
      player: player
    } do
      research_mining(world, user)
      %{tile: tile} = found_city_near_feature(world, user, player.id, :woods)
      worker = Game.spawn_unit_for_test(world, player.id, :worker, tile)

      assert Game.chop(world, user, worker.id) == :ok
      :ok = WorldServer.restart(world)

      assert MapSet.member?(Game.cleared_features(world), tile)
    end
  end
end
