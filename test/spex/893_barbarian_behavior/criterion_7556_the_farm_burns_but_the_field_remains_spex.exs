defmodule BrokenOathsSpex.Story893.Criterion7556Spex do
  @moduledoc """
  Story 893 — Barbarian Behavior
  Criterion 7556 — a barbarian entering a completed improvement
  pillages it: the improvement is removed from the tile (per
  stone_age.md §3.2, "removed from the map"), yields stop, and a
  worker can repair it, which takes exactly 1 turn — much less than a
  fresh build (Farm: 3 turns, per `Improvement.duration/1`).

  Barbarian-fixture note: see criterion 7551's moduledoc — this uses a
  REAL camp-spawned warrior, one of the 1-2 camps that spawn already
  inside the player's own territory (criterion 7543).

  Steering the barbarian onto a specific tile: rather than predicting
  which of several equally-close tiles a hunting barbarian picks (an
  ambiguity criterion 7551 already flags), a farm is built on the
  UNIQUE bridge tile between the camp and a deliberately-placed lord —
  the same "bridge" technique criterion 7536 (story 891) uses to land
  a unit on a specific intermediate hex. The lord sits 3 hexes out
  (camp -> farm tile -> mid tile -> lord), so the barbarian's first
  hop is forced onto the farmed tile while the lord itself stays
  safely out of the pillage's way and (per criterion 7551) still 1
  hex short of adjacency after that first hop — giving the barbarian
  a second hop off the farm tile before combat (criterion 7553) can
  lock it there, so the tile is free again for a worker to repair.

  KNOWN LIMITATION (geometric): the "bridge"/"mid" tiles are each the
  first candidate found by adjacency search, not verified as the
  UNIQUE shortest path — ties are possible on some coastlines. Same
  caveat class as criterion 7536's own bridge-selection choice.

  Inferred, not-yet-implemented shape: as in criterion 7551, this
  assumes each pushed warrior gains a `tile_id` field.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the farm burns but the field remains" do
    scenario "a barbarian pillages a farm it walks through, and a worker repairs it in one turn" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player founded their first city, revealing a nearby barbarian camp",
             context do
        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})

        assert_push_event(play_live, "game:camps", %{camps: camps0})
        [camp | _] = camps0
        [city] = Fixtures.player_cities(context.world, context.user)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:camp_id, camp.id)
         |> Map.put(:camp_tile, camp.tile_id)
         |> Map.put(:camp_warrior_baseline_ids, MapSet.new(camp.warriors, & &1.id))}
      end

      given_ "a completed farm sits on the barbarian's only path to a distant lord", context do
        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        farmable? = fn t ->
          terrain = Fixtures.tile_terrain(context.world, t)
          terrain.relief == :flat and terrain.feature == nil and terrain.base in [:grassland, :plains]
        end

        camp_neighbors = Fixtures.adjacent_tiles(context.world, context.camp_tile) |> Enum.filter(land?)
        farm_tile = Enum.find(camp_neighbors, farmable?)

        mid_tile =
          Fixtures.adjacent_tiles(context.world, farm_tile)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 == context.camp_tile))
          |> Enum.reject(&(&1 in camp_neighbors))
          |> List.first()

        lord_target =
          Fixtures.adjacent_tiles(context.world, mid_tile)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 == farm_tile))
          |> Enum.reject(&(&1 == context.camp_tile))
          |> Enum.reject(&(&1 in camp_neighbors))
          |> List.first()

        # Produce a worker, walk it to the bridge tile, farm it, then
        # walk it away again — the barbarian cannot step onto an
        # occupied tile, and a lingering worker would silently block
        # the whole scenario.
        render_hook(context.play_live, "queue_production", %{
          "city_id" => to_string(context.city.id),
          "item" => "worker"
        })

        for _ <- 1..12, do: Fixtures.advance_turn(context.world)

        [worker] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :worker, do: u

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(worker.id),
          "to_tile" => farm_tile
        })

        Enum.reduce_while(1..15, :ok, fn _, :ok ->
          [w] = for u <- Fixtures.player_units(context.world, context.user), u.id == worker.id, do: u

          if w.tile_id == farm_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        render_hook(context.play_live, "select_unit", %{"unit_id" => to_string(worker.id)})
        render_hook(context.play_live, "start_improvement", %{"unit_id" => to_string(worker.id), "kind" => "farm"})
        for _ <- 1..3, do: Fixtures.advance_turn(context.world)

        assert Fixtures.tile_improvement(context.world, farm_tile) == :farm

        away_tile =
          Fixtures.adjacent_tiles(context.world, farm_tile)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in [context.camp_tile, mid_tile]))
          |> List.first()

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(worker.id),
          "to_tile" => away_tile
        })

        Enum.reduce_while(1..15, :ok, fn _, :ok ->
          [w] = for u <- Fixtures.player_units(context.world, context.user), u.id == worker.id, do: u

          if w.tile_id == away_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [worker] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == worker.id, do: u

        # Now walk the lord out to its 3-hexes-out post, via the same
        # bridge/mid chain.
        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(lord.id),
          "to_tile" => lord_target
        })

        Enum.reduce_while(1..30, :ok, fn _, :ok ->
          [l] = for u <- Fixtures.player_units(context.world, context.user), u.id == lord.id, do: u

          if l.tile_id == lord_target do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [lord] = for u <- Fixtures.player_units(context.world, context.user), u.id == lord.id, do: u

        {:ok,
         context
         |> Map.put(:worker, worker)
         |> Map.put(:farm_tile, farm_tile)
         |> Map.put(:lord, lord)}
      end

      given_ "a barbarian warrior has spawned at the camp", context do
        warrior =
          Enum.reduce_while(1..12, nil, fn _turn, _acc ->
            Fixtures.advance_turn(context.world)
            assert_push_event(context.play_live, "game:camps", %{camps: camps}, 500)
            camp = Enum.find(camps, &(&1.id == context.camp_id))

            new_warrior =
              Enum.find(camp.warriors, &(&1.id not in context.camp_warrior_baseline_ids))

            if new_warrior, do: {:halt, new_warrior}, else: {:cont, nil}
          end)

        {:ok, Map.put(context, :barbarian, warrior)}
      end

      when_ "one more turn boundary passes and the barbarian steps onto the farm", context do
        Fixtures.advance_turn(context.world)
        assert_push_event(context.play_live, "game:camps", %{camps: camps}, 500)
        camp = Enum.find(camps, &(&1.id == context.camp_id))
        barbarian_after = Enum.find(camp.warriors, &(&1.id == context.barbarian.id))

        {:ok, Map.put(context, :barbarian_after, barbarian_after)}
      end

      then_ "the farm is pillaged, but the tile itself remains ordinary land", context do
        assert context.barbarian_after != nil
        assert context.barbarian_after.tile_id == context.farm_tile

        refute Fixtures.tile_improvement(context.world, context.farm_tile) == :farm
        assert Fixtures.tile_class(context.world, context.farm_tile) == :land
        {:ok, context}
      end

      when_ "the barbarian moves on and a worker returns to repair the farm", context do
        Enum.reduce_while(1..8, :ok, fn _turn, :ok ->
          Fixtures.advance_turn(context.world)
          assert_push_event(context.play_live, "game:camps", %{camps: camps}, 500)
          camp = Enum.find(camps, &(&1.id == context.camp_id))
          barbarian = Enum.find(camp.warriors, &(&1.id == context.barbarian.id))

          if barbarian == nil or barbarian.tile_id != context.farm_tile do
            {:halt, :ok}
          else
            {:cont, :ok}
          end
        end)

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(context.worker.id),
          "to_tile" => context.farm_tile
        })

        Enum.reduce_while(1..15, :ok, fn _, :ok ->
          [w] =
            for u <- Fixtures.player_units(context.world, context.user),
                u.id == context.worker.id,
                do: u

          if w.tile_id == context.farm_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        render_hook(context.play_live, "select_unit", %{"unit_id" => to_string(context.worker.id)})

        render_hook(context.play_live, "start_improvement", %{
          "unit_id" => to_string(context.worker.id),
          "kind" => "farm"
        })

        Fixtures.advance_turn(context.world)

        {:ok, context}
      end

      then_ "a single turn's repair makes the farm whole again", context do
        assert Fixtures.tile_improvement(context.world, context.farm_tile) == :farm
        {:ok, context}
      end
    end
  end
end
