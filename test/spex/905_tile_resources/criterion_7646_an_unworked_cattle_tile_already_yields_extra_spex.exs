defmodule BrokenOathsSpex.Story905.Criterion7646Spex do
  @moduledoc """
  Story 905 — Tile Resources
  Criterion 7646 — a Cattle tile already yields its +1 Food bonus the
  moment a citizen works it, with no improvement built — the resource
  bonus is not gated behind Pasture/Animal Husbandry the way the
  improvement's OWN extra yield is (that's criterion 7647/7648).
  Canonical worked example: `.code_my_spec/knowledge/civ6_resources.md`
  §4 — "Cattle on grassland worked by a pop = 2F (grassland) + 1F
  (cattle) = 3F", and criterion 7645 guarantees every Cattle tile sits
  on flat, featureless grassland (2F 0P terrain), so 3F is exact, not
  approximate.

  Isolates the Cattle tile's own contribution the same way story 880
  criterion 7490 isolates a single tile's yield: unassign it, measure
  one turn's food delta (center only), assign it, measure another turn
  (center + the tile), and subtract — the difference is exactly what
  that ONE tile contributes, independent of whatever terrain the
  founding/center tile itself happens to be.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "an unworked Cattle tile already yields extra" do
    scenario "a citizen working a Cattle tile with no improvement already banks 3 food" do
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

      when_ "the Cattle tile's own per-turn food contribution is isolated", context do
        [initial_worked | _] = context.city.worked_tiles

        render_hook(context.play_live, "assign_worked_tile", %{
          "city_id" => context.city.id,
          "from_tile_id" => initial_worked,
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

      then_ "no improvement sits on the Cattle tile — this bonus needs none", context do
        assert Fixtures.tile_improvement(context.world, context.cattle_tile) == nil
        {:ok, context}
      end

      then_ "the worked, unimproved Cattle tile contributes 3 food — 2 terrain + 1 resource", context do
        assert context.cattle_tile in context.worked_city.worked_tiles
        assert context.cattle_food_delta == 3
        {:ok, context}
      end
    end
  end
end
