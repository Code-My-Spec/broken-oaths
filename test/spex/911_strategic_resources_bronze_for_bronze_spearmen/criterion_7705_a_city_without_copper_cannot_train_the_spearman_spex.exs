defmodule BrokenOathsSpex.Story911.Criterion7705Spex do
  @moduledoc """
  Story 911 — Strategic Resources: Bronze for Bronze Spearmen
  Criterion 7705 — a city WITHOUT Copper access sees the Bronze
  Spearman disabled in its production menu with a clear reason
  ("Requires Copper"), and an attempt to queue one anyway is refused.

  Deliberately founds a city whose own founding territory (the tile
  itself plus its six neighbors — `Production.founding_territory/2`)
  contains NO Copper tile at all, verified directly rather than left
  to chance — the same "search for the right tile, don't assume"
  discipline `Criterion7704Spex`'s own moduledoc documents for the
  WITH-Copper case.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a city without Copper cannot train the Spearman" do
    scenario "a city founded away from any Copper tile is refused a Bronze Spearman, with a clear reason" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a city is founded with NO Copper tile anywhere in its own territory", context do
        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        copper? = fn t -> Fixtures.resource_at(context.world, t) == :copper end

        founding_tile =
          Enum.find(0..(Fixtures.tile_count(context.world) - 1), fn t ->
            land?.(t) and not copper?.(t) and
              context.world |> Fixtures.adjacent_tiles(t) |> Enum.all?(&(not copper?.(&1)))
          end)

        refute is_nil(founding_tile), "every land tile on this world sits next to Copper — can't isolate one"

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

        refute Enum.any?(city.territory, &copper?.(&1)),
               "the founded city's own territory unexpectedly contains a Copper tile"

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:city, city)}
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

      when_ "the player opens the city panel and looks at the Bronze Spearman option", context do
        render_hook(context.play_live, "select_city", %{"city_id" => context.city.id})
        {:ok, context}
      end

      then_ "the Bronze Spearman is offered but disabled, with a clear \"Requires Copper\" reason", context do
        assert has_element?(context.play_live, "[data-test='production-option-bronze_spearman']"),
               "the Bronze Spearman option should still be OFFERED once the Bronze Age is reached — only DISABLED"

        assert has_element?(
                 context.play_live,
                 "[data-test='production-option-bronze_spearman'][data-disabled='true']"
               )

        assert has_element?(
                 context.play_live,
                 "[data-test='production-requirement-bronze_spearman'][data-copper-met='false']",
                 "Requires Copper"
               )

        {:ok, context}
      end

      when_ "the player attempts to queue one anyway", context do
        render_hook(context.play_live, "queue_production", %{
          "city_id" => context.city.id,
          "item" => "bronze_spearman"
        })

        {:ok, context}
      end

      then_ "the attempt is refused and no Bronze Spearman enters the queue", context do
        [city] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id == context.city.id, do: c

        refute Enum.any?(city.queue, &(&1.type == :bronze_spearman)),
               "a Bronze Spearman was queued despite the city having no Copper access"

        {:ok, context}
      end
    end
  end
end
