defmodule BrokenOathsSpex.Story911.Criterion7706Spex do
  @moduledoc """
  Story 911 — Strategic Resources: Bronze for Bronze Spearmen
  Criterion 7706 — Copper access is a pure ACCESS GATE: a Copper tile
  merely lying within a city's owned territory is enough, whether or
  not a citizen is actually WORKING it (no stockpile, no consumption,
  no improvement requirement — story 911's own locked design, "A city
  has access when a Copper tile lies within that city's owned
  territory (worked or not)").

  This scenario deliberately keeps the Copper tile UNWORKED throughout
  — it never appears in `city.worked_tiles`, is never the city center
  either (`city.tile_id`), and the city's single starting citizen is
  confirmed working somewhere else — yet the Bronze Spearman is still
  accepted into the queue, proving access never depended on the tile
  being worked.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Copper in the borders counts even when unworked" do
    scenario "an unworked Copper tile in a city's territory still grants Bronze Spearman access" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a city is founded with a Copper tile in its territory, never worked", context do
        copper_tile =
          Enum.find(0..(Fixtures.tile_count(context.world) - 1), fn t ->
            Fixtures.resource_at(context.world, t) == :copper
          end)

        refute is_nil(copper_tile), "this world's own placement rolled no Copper anywhere"

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        # A NEIGHBOR of the Copper tile, never the Copper tile itself —
        # this criterion's own subject is Copper as an ordinary,
        # non-center, unworked territory tile, not the always-free
        # center (which this spec would otherwise trivially satisfy
        # without proving anything about "unworked").
        founding_tile =
          context.world
          |> Fixtures.adjacent_tiles(copper_tile)
          |> Enum.reject(&(&1 == copper_tile))
          |> Enum.find(land?)

        refute is_nil(founding_tile), "no land tile adjacent to Copper (other than itself) exists to found on"

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

        assert copper_tile != city.tile_id, "Copper landed on the city center — this scenario needs it non-center"
        refute copper_tile in city.worked_tiles, "Copper is already worked — this scenario needs it unworked"

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

      when_ "the player queues a Bronze Spearman without ever working the Copper tile", context do
        [city] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id == context.city.id, do: c

        refute context.copper_tile in city.worked_tiles,
               "Copper became worked on its own between founding and this check — the scenario has drifted"

        render_hook(context.play_live, "select_city", %{"city_id" => context.city.id})

        render_hook(context.play_live, "queue_production", %{
          "city_id" => context.city.id,
          "item" => "bronze_spearman"
        })

        {:ok, context}
      end

      then_ "the Bronze Spearman is still accepted into the queue", context do
        [city] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id == context.city.id, do: c

        assert Enum.any?(city.queue, &(&1.type == :bronze_spearman)),
               "Bronze Spearman was refused despite the (unworked) Copper tile sitting in the city's own territory"

        refute context.copper_tile in city.worked_tiles,
               "the assertion above should hold with Copper STILL unworked, not because it got auto-assigned"

        {:ok, context}
      end
    end
  end
end
