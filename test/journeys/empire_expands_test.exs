defmodule BrokenOaths.Journeys.EmpireExpandsTest do
  @moduledoc """
  Journey regression test — `empire_expands`
  (`.code_my_spec/qa/journey_plan.md` / `journey_result.md`, PASS —
  re-verified 2026-07-18 after issue `63300098` was fixed). A well-fed
  size-2+ city completes a Settler, paying its population cost; the
  settler survives a too-close founding attempt and bootstraps a
  second city farther out — crossing stories 875/876/878/879/883.

  Also codifies QA issue `63300098` as an explicit regression: a
  completed settler's population cost must be OBSERVABLE at the exact
  completion boundary (`city.size` really drops by one), never masked
  by same-tick growth refilling it — fixed in `Turn.tick/1`'s phase
  ordering (`lib/broken_oaths/game/turn.ex`): `grow_cities/2` now skips
  growth for any city that paid a settler's population cost THIS SAME
  tick, so the drop is deterministically observable one tick at a time.

  Drives the real `BrokenOathsWeb.GameLive.Play` in-process via
  `Phoenix.LiveViewTest` — see `NewPlayerSettlesTest`'s moduledoc for
  why this is the right harness and not Wallaby.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  test "a settler pays its population cost, survives a too-close founding attempt, and bootstraps a second city" do
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

    # Grow to size 2+ — a size-1 city cannot even queue a Settler
    # (story 883).
    Enum.reduce_while(1..100, :ok, fn _, :ok ->
      if current_city(context.world, context.user, city.id).size >= 2 do
        {:halt, :ok}
      else
        Fixtures.advance_turn(context.world)
        {:cont, :ok}
      end
    end)

    render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "settler"})

    original_unit_ids =
      MapSet.new(for u <- Fixtures.player_units(context.world, context.user), do: u.id)

    # --- The crux (issue 63300098): step turn-by-turn so the exact
    # completion tick is captured, and assert the population cost is a
    # real, observable -1 — never masked by same-tick growth.
    {city_before, city_after} =
      Enum.reduce_while(1..60, nil, fn _, _ ->
        before = current_city(context.world, context.user, city.id)
        Fixtures.advance_turn(context.world)

        new_settler? =
          Fixtures.player_units(context.world, context.user)
          |> Enum.any?(&(&1.type == :settler and &1.id not in original_unit_ids))

        if new_settler? do
          {:halt, {before, current_city(context.world, context.user, city.id)}}
        else
          {:cont, nil}
        end
      end) || flunk("settler never spawned within 60 turns")

    assert city_after.size == city_before.size - 1

    [new_settler] =
      for u <- Fixtures.player_units(context.world, context.user),
          u.type == :settler,
          u.id not in original_unit_ids,
          do: u

    # --- Too close: founding right where the settler landed (touching
    # the capital) is refused with a human-readable reason, and the
    # settler survives untouched.
    render_hook(play_live, "found_city", %{"unit_id" => new_settler.id})
    assert has_element?(play_live, "[data-test='city-error']", "Too close to an existing city.")

    [surviving_settler] =
      for u <- Fixtures.player_units(context.world, context.user), u.id == new_settler.id, do: u

    assert surviving_settler.tile_id == new_settler.tile_id
    assert surviving_settler.hp == new_settler.hp
    assert length(Fixtures.player_cities(context.world, context.user)) == 1

    # --- March 4+ hexes out (orders into the fog are legal) and found
    # a second city there.
    target = ring(context.world, city.tile_id, 4) |> List.first()
    assert target != nil, "no land tile found exactly 4 hexes from the capital"

    render_hook(play_live, "queue_move", %{"unit_id" => new_settler.id, "to_tile" => target})

    Enum.reduce_while(1..30, :ok, fn _, :ok ->
      [s] =
        for u <- Fixtures.player_units(context.world, context.user), u.id == new_settler.id, do: u

      if s.tile_id == target do
        {:halt, :ok}
      else
        Fixtures.advance_turn(context.world)
        {:cont, :ok}
      end
    end)

    [arrived_settler] =
      for u <- Fixtures.player_units(context.world, context.user), u.id == new_settler.id, do: u

    assert arrived_settler.tile_id == target

    # found_city doesn't tick the turn clock, so the capital's state
    # immediately before this call is the right "unchanged by the act"
    # anchor, whatever it organically grew to while the settler
    # produced and marched.
    city1_before_founding = current_city(context.world, context.user, city.id)

    render_hook(play_live, "found_city", %{"unit_id" => arrived_settler.id})

    cities = Fixtures.player_cities(context.world, context.user)
    assert length(cities) == 2

    [city2] = for c <- cities, c.id != city.id, do: c
    assert city2.tile_id == target
    assert city2.size == 1

    expected_ring =
      MapSet.new([city2.tile_id | Fixtures.adjacent_tiles(context.world, city2.tile_id)])

    assert MapSet.new(city2.territory) == expected_ring
    assert length(city2.territory) == 7

    [city1_after_founding] = for c <- cities, c.id == city.id, do: c
    assert city1_after_founding == city1_before_founding
  end

  defp current_city(world, user, city_id) do
    [city] = for c <- Fixtures.player_cities(world, user), c.id == city_id, do: c
    city
  end

  # Land tiles exactly `n` hexes from `from_tile` — the same BFS-ring
  # idiom `criterion_7489` uses for a route/seed-agnostic 4+-hex
  # founding destination.
  defp ring(world, from_tile, n) do
    land? = fn t -> Fixtures.tile_class(world, t) == :land end

    grow = fn frontier, seen ->
      next =
        frontier
        |> Enum.flat_map(&Fixtures.adjacent_tiles(world, &1))
        |> Enum.uniq()
        |> Enum.reject(&MapSet.member?(seen, &1))
        |> Enum.filter(land?)

      {next, MapSet.union(seen, MapSet.new(next))}
    end

    {final_frontier, _seen} =
      Enum.reduce(1..n, {[from_tile], MapSet.new([from_tile])}, fn _, {frontier, seen} ->
        grow.(frontier, seen)
      end)

    final_frontier
  end
end
