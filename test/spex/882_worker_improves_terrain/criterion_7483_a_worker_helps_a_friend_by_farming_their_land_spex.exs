defmodule BrokenOathsSpex.Story882.Criterion7483Spex do
  @moduledoc """
  Story 882 — Worker Improves Terrain
  Criterion 7483 — improvements can be built anywhere passable,
  including another player's territory; a completed farm feeds
  whichever city works that tile.

  Cross-epic regression fix (this criterion predates story 893's
  barbarian AI, and has nothing to do with it): once barbarian AI went
  live, the second player's worker — walking through the FIRST
  player's own territory for up to 30 turns, plus the 12 turns spent
  producing it — became exposed to a real, camp-spawned barbarian a
  camp guaranteed inside that territory (criterion 7543) could kill it
  with, breaking THIS criterion for a reason entirely unrelated to what
  it tests (worker/improvement mechanics across two players).
  `Fixtures.isolate_camp/2` (story 893's own bridge, `WorldServer`'s
  `:isolate_camp_for_test` handler) destroys every camp in the world —
  passing a sentinel that matches no real camp id destroys all of them,
  not just "every other one." `WorldServer.spawn_wilderness_camps/3`
  fires on EACH player's own first founding (`do_found_city/3`'s own
  `first_founding?` check), not once globally, so this scenario's own
  isolation call has to wait until BOTH players have founded their
  first city before every camp that will ever exist here does — called
  right after that, before either player's worker/settler spends any
  turn near either territory. Barbarians are irrelevant to this
  criterion's SUBJECT, so eliminating them outright (not tolerating
  incidental interference) is the same hardening pattern story 893/894's
  own restructured criteria settled on.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a worker helps a friend by farming their land" do
    scenario "a second player's worker farms inside the first player's territory" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "a worker standing on valid farmland inside a friendly player's territory", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        farmland =
          city.territory
          |> Enum.reject(&(&1 == city.tile_id))
          |> Enum.filter(land?)
          |> Enum.find(fn t ->
            terrain = Fixtures.tile_terrain(context.world, t)
            terrain.relief == :flat and terrain.feature == nil and terrain.base in [:grassland, :plains]
          end)

        {:ok, other_join_live, _html} = live(context.other_conn, ~p"/play")

        other_join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, other_play_live, _html} = live(context.other_conn, ~p"/play/#{context.world.id}")

        [other_settler | _] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :settler,
              do: u

        # The second player founds far from the first, then produces a
        # worker rather than trespassing with their starting settler.
        render_hook(other_play_live, "found_city", %{"unit_id" => other_settler.id})
        [other_city] = Fixtures.player_cities(context.world, context.other_user)

        # See this module's doc: barbarians are irrelevant to this
        # criterion's SUBJECT. `spawn_wilderness_camps/3` fires on EACH
        # player's own first founding (`WorldServer.do_found_city/3`),
        # so this has to wait until BOTH players have founded before
        # every camp that will ever exist for this scenario does —
        # eliminate them all now, before either player's units spend
        # dozens of turns anywhere near either territory.
        :ok = Fixtures.isolate_camp(context.world, :none)

        render_hook(other_play_live, "queue_production", %{
          "city_id" => other_city.id,
          "item" => "worker"
        })

        for _ <- 1..12, do: Fixtures.advance_turn(context.world)

        [worker] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :worker,
              do: u

        render_hook(other_play_live, "queue_move", %{"unit_id" => worker.id, "to_tile" => farmland})

        Enum.reduce_while(1..30, :ok, fn _, :ok ->
          [w] =
            for u <- Fixtures.player_units(context.world, context.other_user),
                u.id == worker.id,
                do: u

          if w.tile_id == farmland do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:other_play_live, other_play_live)
         |> Map.put(:city, city)
         |> Map.put(:worker, worker)
         |> Map.put(:farmland, farmland)}
      end

      when_ "the worker's owner starts a Farm and it completes", context do
        render_hook(context.other_play_live, "select_unit", %{"unit_id" => context.worker.id})

        render_hook(context.other_play_live, "start_improvement", %{
          "unit_id" => context.worker.id,
          "kind" => "farm"
        })

        for _ <- 1..3, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the farm exists on that tile", context do
        assert Fixtures.tile_improvement(context.world, context.farmland) == :farm
        {:ok, context}
      end

      then_ "it feeds whichever city works the tile — the friend's city, in this case", context do
        [before] =
          for cc <- Fixtures.player_cities(context.world, context.user), cc.id == context.city.id, do: cc

        [worked | _] = before.worked_tiles

        render_hook(context.play_live, "assign_worked_tile", %{
          "city_id" => before.id,
          "from_tile_id" => worked,
          "to_tile_id" => nil
        })

        [baseline] =
          for cc <- Fixtures.player_cities(context.world, context.user), cc.id == before.id, do: cc

        Fixtures.advance_turn(context.world)

        [before_assign] =
          for cc <- Fixtures.player_cities(context.world, context.user), cc.id == before.id, do: cc

        render_hook(context.play_live, "assign_worked_tile", %{
          "city_id" => before.id,
          "from_tile_id" => nil,
          "to_tile_id" => context.farmland
        })

        [after_baseline] =
          for cc <- Fixtures.player_cities(context.world, context.user), cc.id == before.id, do: cc

        Fixtures.advance_turn(context.world)

        [after_assign] =
          for cc <- Fixtures.player_cities(context.world, context.user), cc.id == before.id, do: cc

        no_op_delta = before_assign.food - baseline.food
        farmed_delta = after_assign.food - after_baseline.food

        # This city sat idle while the second player's given_ spent up to
        # ~40 turns producing and walking its own worker (sharing this
        # world's turn clock) — plenty of time for city1 to have grown and
        # auto-assigned other worked tiles beyond the one turned unassigned
        # here. `no_op_delta` is therefore the CITY's current steady
        # per-turn income (center + whatever else it's grown to work), not
        # zero. Isolate the farm tile's own contribution the same way
        # criterion 7490 does: the marginal difference between the two
        # back-to-back per-turn deltas, taken immediately adjacent so
        # nothing else about the city changes in between.
        assert farmed_delta - no_op_delta >= 2
        {:ok, context}
      end

      then_ "nothing prevents building on any player's territory (no open-borders system yet)", context do
        assert Fixtures.tile_improvement(context.world, context.farmland) == :farm
        {:ok, context}
      end
    end
  end
end
