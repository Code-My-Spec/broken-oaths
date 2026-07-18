defmodule BrokenOathsSpex.Story905.Criterion7647Spex do
  @moduledoc """
  Story 905 — Tile Resources
  Criterion 7647 — a completed Pasture on a Cattle tile stacks its own
  +2 Food on top of the tile's already-bonused yield, for 5 Food total.
  Canonical worked example: `.code_my_spec/knowledge/civ6_resources.md`
  §4/§5 — "Cattle on grassland with a Pasture = 2F + 1F + 2F = 5F".
  Criterion 7645 guarantees every Cattle tile sits on flat, featureless
  grassland (2F 0P terrain), so 5F is exact.

  Reuses criterion 7646's isolate-delta measurement (unassign, measure
  a bare turn; assign, measure a worked turn; subtract) — the same
  Cattle tile, but this time with a completed Pasture already on it, so
  the isolated delta is the tile's FULLY-improved contribution.

  The research half of this setup reuses story 902's OWN established
  `TechPanel` surface contract exactly (`"toggle_tech_panel"` +
  `"select_research"`, `[data-test='tech-completed-<name>']`) — see
  `BrokenOathsSpex.Story902.Criterion7625Spex`'s moduledoc for the full
  contract and `BrokenOathsSpex.Story902.Criterion7643Spex`, which
  explicitly defers "placing a Pasture on an actual animal-resource
  tile" to this story. 25 turns is that same spec's own turn math:
  Animal Husbandry costs 50 science, a lone size->=1 city already earns
  >=2/turn, so 25 turns is a safe lower bound regardless of any growth
  along the way (growth only completes it sooner).

  The remaining assumed contract — unique to story 905, since story 902
  explicitly defers it — is `"start_improvement"` accepting
  `"kind" => "pasture"`; the improvement itself doesn't exist yet
  (`BrokenOaths.Game.Improvement` only knows `:farm | :mine | :road`
  today). No duration is specified anywhere yet; 6 turns is a generous,
  documented upper bound (matching the existing 2-5 turn improvement
  range) rather than a guessed exact number.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a Pasture on Cattle stacks to five food" do
    scenario "a completed Pasture on a worked Cattle tile banks 5 food" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a city has founded next to a Cattle tile, with that tile in its territory", context do
        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        cattle_tile =
          Enum.find(0..(Fixtures.tile_count(context.world) - 1), fn t ->
            Fixtures.resource_at(context.world, t) == :cattle
          end)

        founding_tile = Fixtures.adjacent_tiles(context.world, cattle_tile) |> Enum.find(land?)

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

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:cattle_tile, cattle_tile)}
      end

      given_ "the player has opened the tech panel and researched Animal Husbandry", context do
        render_hook(context.play_live, "toggle_tech_panel", %{})
        render_hook(context.play_live, "select_research", %{"tech" => "animal_husbandry"})
        for _ <- 1..25, do: Fixtures.advance_turn(context.world)
        assert has_element?(context.play_live, "[data-test='tech-completed-animal_husbandry']")
        {:ok, context}
      end

      given_ "a worker has built a Pasture on the Cattle tile", context do
        render_hook(context.play_live, "queue_production", %{
          "city_id" => context.city.id,
          "item" => "worker"
        })

        for _ <- 1..12, do: Fixtures.advance_turn(context.world)

        [worker] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :worker, do: u

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => worker.id,
          "to_tile" => context.cattle_tile
        })

        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [w] = for u <- Fixtures.player_units(context.world, context.user), u.id == worker.id, do: u

          if w.tile_id == context.cattle_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        render_hook(context.play_live, "select_unit", %{"unit_id" => worker.id})

        render_hook(context.play_live, "start_improvement", %{
          "unit_id" => worker.id,
          "kind" => "pasture"
        })

        for _ <- 1..6, do: Fixtures.advance_turn(context.world)
        {:ok, Map.put(context, :worker, worker)}
      end

      when_ "the Cattle tile's own per-turn food contribution is isolated", context do
        # Targets `context.cattle_tile` directly rather than
        # `List.first(worked_tiles)` — by this point in the scenario
        # (research + worker production + movement + a Pasture build,
        # dozens of turns) the city may well have grown past size 1, and
        # `worked_tiles` is no longer guaranteed to list the Cattle tile
        # first (unlike criterion 7646's own version of this isolation,
        # which runs immediately post-founding while the city is still
        # a guaranteed size-1/one-worked-tile city — see criterion
        # 7650's own doc). Unassigning the WRONG tile here would leave
        # Cattle still worked through the "baseline" turn too, making
        # both deltas identical and silently zeroing out the measurement.
        [current_city] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id == context.city.id, do: c

        assert context.cattle_tile in current_city.worked_tiles

        render_hook(context.play_live, "assign_worked_tile", %{
          "city_id" => context.city.id,
          "from_tile_id" => context.cattle_tile,
          "to_tile_id" => nil
        })

        [before_baseline] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id == context.city.id, do: c

        Fixtures.advance_turn(context.world)

        [after_baseline] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id == context.city.id, do: c

        baseline_delta = after_baseline.food - before_baseline.food

        render_hook(context.play_live, "assign_worked_tile", %{
          "city_id" => context.city.id,
          "from_tile_id" => nil,
          "to_tile_id" => context.cattle_tile
        })

        [before_measurement] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id == context.city.id, do: c

        Fixtures.advance_turn(context.world)

        [after_measurement] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id == context.city.id, do: c

        measurement_delta = after_measurement.food - before_measurement.food

        {:ok,
         context
         |> Map.put(:cattle_food_delta, measurement_delta - baseline_delta)
         |> Map.put(:worked_city, after_measurement)}
      end

      then_ "the Pasture is complete on the Cattle tile", context do
        assert Fixtures.tile_improvement(context.world, context.cattle_tile) == :pasture
        {:ok, context}
      end

      then_ "the worked, Pasture-improved Cattle tile contributes 5 food — 2 terrain + 1 resource + 2 pasture",
            context do
        assert context.cattle_tile in context.worked_city.worked_tiles
        assert context.cattle_food_delta == 5
        {:ok, context}
      end
    end
  end
end
