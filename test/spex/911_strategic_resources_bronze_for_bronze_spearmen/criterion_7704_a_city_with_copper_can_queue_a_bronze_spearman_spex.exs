defmodule BrokenOathsSpex.Story911.Criterion7704Spex do
  @moduledoc """
  Story 911 — Strategic Resources: Bronze for Bronze Spearmen
  Criterion 7704 — a city with Copper access can queue a Bronze
  Spearman once the Bronze Age is reached.

  ## Access rule under test (reworked for QA issue 3e6c124c "Copper
  availability wrong")

  Copper access is no longer "a bare Copper tile lies within a city's
  own territory" (story 911's original, MVP-narrow design) — it is now
  MINE-BASED and PLAYER-WIDE: a player has access once they have at
  least one COMPLETED Mine improvement sitting on a Copper tile within
  territory ANY of their own cities controls, and that single fact then
  unlocks the Bronze Spearman in EVERY city they own, not only the one
  whose territory holds the mine (`BrokenOaths.Cities.Production.
  player_copper_access?/2`).

  This scenario founds a city with a REAL Copper tile among its
  founding territory (the tile itself plus its six neighbors —
  `Production.founding_territory/2`), builds a completed Mine on that
  Copper tile (`Fixtures.complete_improvement/3` — the same narrow
  test-only bridge `:complete_improvement_for_test` already documents,
  standing in for a worker spending several real turns on it), reaches
  the Bronze Age the same way `SharedGivens.player_reached_bronze_age`
  does (Mining, then Bronze Working — story 902's expanded tree), and
  queues a Bronze Spearman through the real `"queue_production"` hook.
  Doesn't reuse `player_reached_bronze_age` itself, since that given
  founds the city wherever the starting settler happens to be — this
  criterion's own SUBJECT is a city deliberately placed so Copper falls
  within its territory.

  A second scenario segment then founds a SECOND city elsewhere on the
  map — deliberately with NO Copper anywhere in ITS OWN territory —
  and queues a Bronze Spearman there too, proving the PLAYER-WIDE half
  of the rework: the mined city's own Copper access reaches every city
  the player owns, not just the one sitting on the resource.

  Reuses story 903's own `TechPanel` research-selection contract
  (`"toggle_tech_panel"`, `"select_research"`, `"bronze_working_
  confirm"`, `[data-test='tech-completed-<name>']`) exactly —
  see `BrokenOathsSpex.SharedGivens.player_reached_bronze_age`'s own
  moduledoc for the full flow and turn-math rationale.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a city with Copper can queue a Bronze Spearman" do
    scenario "founding a city, mining its Copper, and training a Bronze Spearman there and player-wide" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a city is founded with a real Copper tile in its own territory", context do
        copper_tile =
          Enum.find(0..(Fixtures.tile_count(context.world) - 1), fn t ->
            Fixtures.resource_at(context.world, t) == :copper
          end)

        refute is_nil(copper_tile), "this world's own placement rolled no Copper anywhere"

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        # Prefer a NEIGHBOR of the Copper tile as the founding spot (so
        # Copper lands as an ordinary, non-center territory tile), and
        # only fall back to founding directly on it if no neighboring
        # land tile exists (e.g. an isolated Copper hill surrounded by
        # ocean) — either way the founded city's territory ends up
        # containing the Copper tile, which is all this criterion needs.
        founding_tile =
          context.world
          |> Fixtures.adjacent_tiles(copper_tile)
          |> Enum.find(land?) || copper_tile

        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "queue_move", %{
          "unit_id" => settler.id,
          "to_tile" => founding_tile
        })

        Enum.reduce_while(1..30, :ok, fn _, :ok ->
          [s] =
            for u <- Fixtures.player_units(context.world, context.user), u.id == settler.id, do: u

          if s.tile_id == founding_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)

        assert copper_tile in city.territory,
               "the founded city's own territory doesn't include the Copper tile it was founded next to"

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:copper_tile, copper_tile)}
      end

      given_ "a Mine is built on the Copper tile", context do
        improvement = Fixtures.complete_improvement(context.world, context.copper_tile, :mine)

        assert improvement.status == :complete,
               "the Mine on the Copper tile should be instantly completed by this test-only bridge"

        {:ok, context}
      end

      given_ "the player reaches the Bronze Age (Mining, then Bronze Working)", context do
        render_hook(context.play_live, "toggle_tech_panel", %{})
        render_hook(context.play_live, "select_research", %{"tech" => "mining"})

        Enum.reduce_while(1..60, :ok, fn _, :ok ->
          if has_element?(context.play_live, "[data-test='tech-completed-mining']") do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        render_hook(context.play_live, "select_research", %{"tech" => "bronze_working"})
        render_hook(context.play_live, "bronze_working_confirm", %{})

        for _ <- 1..60, do: Fixtures.advance_turn(context.world)

        assert has_element?(context.play_live, "[data-test='tech-completed-bronze_working']")
        {:ok, context}
      end

      when_ "the player queues a Bronze Spearman in the mined city", context do
        render_hook(context.play_live, "select_city", %{"city_id" => context.city.id})

        render_hook(context.play_live, "queue_production", %{
          "city_id" => context.city.id,
          "item" => "bronze_spearman"
        })

        {:ok, context}
      end

      then_ "the Bronze Spearman is accepted into the production queue", context do
        [city] =
          for c <- Fixtures.player_cities(context.world, context.user),
              c.id == context.city.id,
              do: c

        assert Enum.any?(city.queue, &(&1.type == :bronze_spearman)),
               "Bronze Spearman was refused — the player has a completed Mine on a Copper tile and the Bronze Age, it should be accepted"

        {:ok, context}
      end

      given_ "a second city, with NO Copper anywhere in its own territory, is also founded",
             context do
        {:ok, player} = Fixtures.join_world(context.world, context.user)

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        copper? = fn t -> Fixtures.resource_at(context.world, t) == :copper end

        no_copper_nearby? = fn t ->
          land?.(t) and not copper?.(t) and
            context.world |> Fixtures.adjacent_tiles(t) |> Enum.all?(&(not copper?.(&1)))
        end

        candidates =
          0..(Fixtures.tile_count(context.world) - 1)
          |> Enum.filter(no_copper_nearby?)

        refute candidates == [],
               "every land tile on this world sits next to Copper — can't isolate a second, Copper-free spot"

        # Tries each Copper-free candidate in turn (spawning a fresh
        # settler right on it and attempting the real `"found_city"`
        # hook), halting at the first one the game's own founding rules
        # (terrain, 4-hex spacing from the first city) actually accept
        # — the same "try, don't assume" discipline `criterion_7705`'s
        # own moduledoc documents, extended here because unlike that
        # scenario this one ALSO needs the spot far enough from the
        # first city's own territory, which this criterion has no
        # sanctioned way to compute directly (`WorldServer`'s own
        # founding-spacing math stays internal).
        second_city =
          Enum.reduce_while(candidates, nil, fn tile_id, nil ->
            settler = Fixtures.spawn_unit(context.world, player.id, :settler, tile_id)
            render_hook(context.play_live, "found_city", %{"unit_id" => settler.id})

            case for c <- Fixtures.player_cities(context.world, context.user),
                     c.id != context.city.id,
                     do: c do
              [found] -> {:halt, found}
              [] -> {:cont, nil}
            end
          end)

        refute is_nil(second_city),
               "couldn't found a second city anywhere far enough from the first, real-Copper-free spot"

        refute Enum.any?(second_city.territory, &copper?.(&1)),
               "the second city's own territory unexpectedly contains a Copper tile"

        {:ok, Map.put(context, :second_city, second_city)}
      end

      when_ "the player queues a Bronze Spearman in the SECOND city instead", context do
        render_hook(context.play_live, "select_city", %{"city_id" => context.second_city.id})

        render_hook(context.play_live, "queue_production", %{
          "city_id" => context.second_city.id,
          "item" => "bronze_spearman"
        })

        {:ok, context}
      end

      then_ "the Bronze Spearman is STILL accepted — Copper access is player-wide", context do
        [city] =
          for c <- Fixtures.player_cities(context.world, context.user),
              c.id == context.second_city.id,
              do: c

        assert Enum.any?(city.queue, &(&1.type == :bronze_spearman)),
               "Bronze Spearman was refused in a city with no Copper of its own — the player already has " <>
                 "Copper access via the OTHER city's Mine, and access is meant to be player-wide"

        {:ok, context}
      end
    end
  end
end
