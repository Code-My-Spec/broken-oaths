defmodule BrokenOathsSpex.Story911.Criterion7704Spex do
  @moduledoc """
  Story 911 — Strategic Resources: Bronze for Bronze Spearmen
  Criterion 7704 — a city with Copper access (a Copper tile anywhere
  in its own territory) can queue a Bronze Spearman once the Bronze
  Age is reached.

  ## Access rule under test

  "A city has access when a Copper tile lies within that city's owned
  territory" (story 911's own locked design). This scenario founds a
  city with a REAL Copper tile among its founding territory (the tile
  itself plus its six neighbors — `Production.founding_territory/2`),
  reaches the Bronze Age the same way `SharedGivens.player_reached_
  bronze_age` does (Mining, then Bronze Working — story 902's expanded
  tree), and queues a Bronze Spearman through the real
  `"queue_production"` hook. Doesn't reuse `player_reached_bronze_age`
  itself, since that given founds the city wherever the starting
  settler happens to be — this criterion's own SUBJECT is a city
  deliberately placed so Copper falls within its territory.

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
    scenario "founding a city with Copper in its territory lets it train a Bronze Spearman" do
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

        render_hook(play_live, "queue_move", %{"unit_id" => settler.id, "to_tile" => founding_tile})

        Enum.reduce_while(1..30, :ok, fn _, :ok ->
          [s] = for u <- Fixtures.player_units(context.world, context.user), u.id == settler.id, do: u

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

      when_ "the player queues a Bronze Spearman in that city", context do
        render_hook(context.play_live, "select_city", %{"city_id" => context.city.id})

        render_hook(context.play_live, "queue_production", %{
          "city_id" => context.city.id,
          "item" => "bronze_spearman"
        })

        {:ok, context}
      end

      then_ "the Bronze Spearman is accepted into the production queue", context do
        [city] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id == context.city.id, do: c

        assert Enum.any?(city.queue, &(&1.type == :bronze_spearman)),
               "Bronze Spearman was refused — city has Copper access and the Bronze Age, it should be accepted"

        {:ok, context}
      end
    end
  end
end
