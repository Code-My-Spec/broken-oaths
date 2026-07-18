defmodule BrokenOaths.Journeys.NewPlayerSettlesTest do
  @moduledoc """
  Journey regression test — `new_player_settles`
  (`.code_my_spec/qa/journey_plan.md` / `journey_result.md`, PASS,
  2026-07-18). A fresh, logged-in player joins a world, selects their
  settler, issues a move order, founds their first city, and queues a
  Warrior — crossing stories 873/875/876/877/878/879.

  Authenticates by building a logged-in conn directly
  (`BrokenOathsSpex.SharedGivens.registered_player/1`), the same seam
  every existing spex file already uses, rather than walking the
  magic-link registration UI — story 873's own dedicated coverage
  already exercises that flow end to end.

  Drives the real `BrokenOathsWeb.GameLive.Play` in-process via
  `Phoenix.LiveViewTest` (`render_hook`/`render_click`/`has_element?`),
  exactly like the 66 existing spex files under `test/spex/` — this is
  a deliberate choice, NOT Wallaby: Wallaby isn't a dependency here,
  there's no `FeatureCase`, game state lives in `WorldServer` GenServers
  + the DB (which fights Wallaby's real-browser/HTTP/SQL-sandbox
  model), and the board is a canvas driven by PointerEvents with no
  tile DOM for a real browser driver to click. `Phoenix.LiveViewTest`
  drives the exact same `handle_event/3` clauses a browser click would
  reach, with none of that friction.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  test "a fresh player joins, moves their settler, founds a city, and queues a Warrior" do
    {:ok, context} = a_world(%{})
    {:ok, context} = registered_player(context)

    {:ok, join_live, _html} = live(context.conn, ~p"/play")

    join_live
    |> element("[data-test='join-world-#{context.world.id}']")
    |> render_click()

    {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

    # Step 3: the spawn shows a lord and a settler, gold badge 50.
    assert has_element?(play_live, "[data-test='player-gold']", "50")

    units = Fixtures.player_units(context.world, context.user)
    assert length(units) == 2
    assert Enum.any?(units, &(&1.type == :lord))
    [settler] = for u <- units, u.type == :settler, do: u

    # Step 4: selecting the settler opens the unit panel with a Found
    # City button.
    render_hook(play_live, "select_unit", %{"unit_id" => settler.id})
    assert has_element?(play_live, "[data-test='unit-type']", "Settler")
    assert has_element?(play_live, "[data-test='unit-hp']", "50/50")
    assert has_element?(play_live, "[data-test='unit-movement']", "2/2")
    assert has_element?(play_live, "[data-test='found-city']")

    # Step 5: right-clicking a nearby land tile (queue_move) moves the
    # settler immediately, spending movement.
    exclude = MapSet.new(for u <- units, u.id != settler.id, do: u.tile_id)
    target = nearest_land_tile(context.world, settler.tile_id, exclude)

    render_hook(play_live, "queue_move", %{"unit_id" => settler.id, "to_tile" => target})

    [moved_settler] =
      for u <- Fixtures.player_units(context.world, context.user), u.id == settler.id, do: u

    assert moved_settler.tile_id == target
    assert moved_settler.movement < moved_settler.max_movement

    # Step 6/7: founding trades the settler for a working size-1 city
    # on that exact tile; the settler is gone.
    render_hook(play_live, "found_city", %{"unit_id" => moved_settler.id})

    refute Enum.any?(Fixtures.player_units(context.world, context.user), &(&1.type == :settler))

    [city] = Fixtures.player_cities(context.world, context.user)
    assert city.tile_id == target
    assert city.size == 1
    assert city.name == "City 1"

    # Step 8: queuing a Warrior shows a current-production row reading
    # "Warrior 0/40" with a progress bar.
    render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "warrior"})
    render_hook(play_live, "select_city", %{"city_id" => city.id})

    assert has_element?(play_live, "[data-test='city-production-current']", "Warrior 0/40")
    assert has_element?(play_live, "[data-test='city-production-progress']")

    [city_after] =
      for c <- Fixtures.player_cities(context.world, context.user), c.id == city.id, do: c

    [current | _] = city_after.queue
    assert current.type == :warrior
    assert current.banked == 0
    assert current.cost == 40
  end

  # BFS outward from `from_tile` for the nearest unoccupied land tile —
  # the same route/seed-agnostic idiom `criterion_7425`/`criterion_7462`
  # use for movement destinations, widened a couple of rings in case
  # the settler's immediate neighbors are all ocean or occupied.
  defp nearest_land_tile(world, from_tile, exclude) do
    land? = fn t -> Fixtures.tile_class(world, t) == :land end

    grow = fn frontier, seen ->
      next =
        frontier
        |> Enum.flat_map(&Fixtures.adjacent_tiles(world, &1))
        |> Enum.uniq()
        |> Enum.reject(&(MapSet.member?(seen, &1) or MapSet.member?(exclude, &1)))
        |> Enum.filter(land?)

      {next, MapSet.union(seen, MapSet.new(next))}
    end

    seen = MapSet.new([from_tile])
    {l1, seen} = grow.([from_tile], seen)
    {l2, seen} = grow.(l1, seen)
    {l3, _seen} = grow.(l2, seen)

    case l1 ++ l2 ++ l3 do
      [t | _] -> t
      [] -> flunk("no reachable land tile found near tile #{from_tile}")
    end
  end
end
