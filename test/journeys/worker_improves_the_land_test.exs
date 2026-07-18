defmodule BrokenOaths.Journeys.WorkerImprovesTheLandTest do
  @moduledoc """
  Journey regression test — `worker_improves_the_land`
  (`.code_my_spec/qa/journey_plan.md` / `journey_result.md`, PASS). A
  worker builds a Farm, the build completes and a duplicate build is
  refused, and working the farmed tile raises the city's food income —
  crossing stories 875/879/880/882.

  Also codifies QA issue `7509c453` as an explicit regression: a city
  already working as many tiles as its size REJECTS an unpaired
  `assign_worked_tile` call and stays at its current worked-tile count
  — fixed in `WorldServer.validate_assign/3`'s `:size_exceeded` clause
  (`lib/broken_oaths/game/world_server.ex:1800-1819`); a *paired*
  reassignment (swapping one worked tile for another) stays allowed
  even at the cap.

  Drives the real `BrokenOathsWeb.GameLive.Play` in-process via
  `Phoenix.LiveViewTest` — see `NewPlayerSettlesTest`'s moduledoc for
  why this is the right harness and not Wallaby.

  Grows the city to the Stone Age population cap (size 4,
  `Yields.capped?/2`) BEFORE any of the timing-sensitive food-delta
  measurements below: once capped, growth never fires again (food just
  accrues monotonically, `Yields.threshold/2` returns `nil`), so
  isolating the Farm's own +2 food yield across turn boundaries can
  never race a same-tick growth/food-reset event the way it would on a
  still-growing city.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  test "a worker farms a tile (refusing a duplicate build) and the city's food income rises; an already-capped city rejects an unpaired worked-tile assign" do
    {:ok, context} = a_world(%{})
    {:ok, context} = registered_player(context)

    {:ok, join_live, _html} = live(context.conn, ~p"/play")

    join_live
    |> element("[data-test='join-world-#{context.world.id}']")
    |> render_click()

    {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

    [settler | _] =
      for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

    render_hook(play_live, "found_city", %{"unit_id" => settler.id})
    [city] = Fixtures.player_cities(context.world, context.user)

    # Grow to the Stone Age cap (size 4) before anything else — freezes
    # growth permanently, so every later measurement is race-free.
    Enum.reduce_while(1..300, :ok, fn _, :ok ->
      if current_city(context.world, context.user, city.id).size >= 4 do
        {:halt, :ok}
      else
        Fixtures.advance_turn(context.world)
        {:cont, :ok}
      end
    end)

    capped_city = current_city(context.world, context.user, city.id)
    assert capped_city.size == 4
    assert length(capped_city.worked_tiles) == 4

    # --- Regression 7509c453: already at the population cap (4 worked
    # tiles for a size-4 city), an unpaired assign is rejected and the
    # worked-tile set is left exactly as it was.
    unassignable =
      (capped_city.territory -- [capped_city.tile_id | capped_city.worked_tiles])
      |> Enum.find(&workable?(context.world, &1))

    assert unassignable != nil,
           "no candidate territory tile left to attempt the over-cap assign against"

    render_hook(play_live, "assign_worked_tile", %{
      "city_id" => capped_city.id,
      "to_tile_id" => unassignable
    })

    assert has_element?(play_live, "[data-test='city-error']")

    unchanged_city = current_city(context.world, context.user, city.id)
    assert length(unchanged_city.worked_tiles) == 4
    assert MapSet.new(unchanged_city.worked_tiles) == MapSet.new(capped_city.worked_tiles)

    # --- Get a worker: queue one and wait for it to spawn.
    render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "worker"})

    Enum.reduce_while(1..30, :ok, fn _, :ok ->
      if Enum.any?(Fixtures.player_units(context.world, context.user), &(&1.type == :worker)) do
        {:halt, :ok}
      else
        Fixtures.advance_turn(context.world)
        {:cont, :ok}
      end
    end)

    [worker] =
      for u <- Fixtures.player_units(context.world, context.user), u.type == :worker, do: u

    # --- Find a flat grassland/plains territory tile: not the center,
    # not already worked, and not occupied by another unit.
    occupied =
      for u <- Fixtures.player_units(context.world, context.user), u.id != worker.id, do: u.tile_id

    candidate =
      (capped_city.territory -- [capped_city.tile_id | capped_city.worked_tiles])
      |> Enum.reject(&(&1 in occupied))
      |> Enum.find(fn t ->
        terrain = Fixtures.tile_terrain(context.world, t)
        terrain.relief == :flat and terrain.feature == nil and terrain.base in [:grassland, :plains]
      end)

    assert candidate != nil, "no flat grassland/plains territory tile found for the farm"

    render_hook(play_live, "queue_move", %{"unit_id" => worker.id, "to_tile" => candidate})

    Enum.reduce_while(1..15, :ok, fn _, :ok ->
      [w] = for u <- Fixtures.player_units(context.world, context.user), u.id == worker.id, do: u

      if w.tile_id == candidate do
        {:halt, :ok}
      else
        Fixtures.advance_turn(context.world)
        {:cont, :ok}
      end
    end)

    # --- Bring the candidate tile into work first (a PAIRED swap —
    # allowed even at the cap), so the raw/farmed measurements below
    # isolate the SAME worked tile's own yield before vs. after the
    # Farm completes.
    [old_worked | _] = current_city(context.world, context.user, city.id).worked_tiles

    render_hook(play_live, "assign_worked_tile", %{
      "city_id" => city.id,
      "from_tile_id" => old_worked,
      "to_tile_id" => candidate
    })

    assert candidate in current_city(context.world, context.user, city.id).worked_tiles

    render_hook(play_live, "select_unit", %{"unit_id" => worker.id})
    render_hook(play_live, "start_improvement", %{"unit_id" => worker.id, "kind" => "farm"})
    assert has_element?(play_live, "[data-test='dig-progress']")

    food_before_raw = current_city(context.world, context.user, city.id).food
    Fixtures.advance_turn(context.world)
    food_after_raw = current_city(context.world, context.user, city.id).food
    raw_delta = food_after_raw - food_before_raw

    # Two more turns complete the 3-turn Farm.
    for _ <- 1..2, do: Fixtures.advance_turn(context.world)
    assert Fixtures.tile_improvement(context.world, candidate) == :farm

    # A second build on the same, now-complete tile is refused.
    render_hook(play_live, "start_improvement", %{"unit_id" => worker.id, "kind" => "farm"})
    assert has_element?(play_live, "[data-test='improvement-error']")

    # Measure the Farm's steady-state contribution over the next, clean
    # (already-complete) turn boundary.
    food_before_farmed = current_city(context.world, context.user, city.id).food
    Fixtures.advance_turn(context.world)
    food_after_farmed = current_city(context.world, context.user, city.id).food
    farmed_delta = food_after_farmed - food_before_farmed

    assert farmed_delta - raw_delta == 2

    # --- The city panel shows the farmed tile as worked.
    render_hook(play_live, "select_city", %{"city_id" => city.id})
    assert has_element?(play_live, "[data-test='city-worked-tile-#{candidate}']")
  end

  defp current_city(world, user, city_id) do
    [city] = for c <- Fixtures.player_cities(world, user), c.id == city_id, do: c
    city
  end

  defp workable?(world, tile_id) do
    terrain = Fixtures.tile_terrain(world, tile_id)
    terrain.relief != :mountains and terrain.feature != :ice
  end
end
