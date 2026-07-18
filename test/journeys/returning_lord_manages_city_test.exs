defmodule BrokenOaths.Journeys.ReturningLordManagesCityTest do
  @moduledoc """
  Journey regression test — `returning_lord_manages_city`
  (`.code_my_spec/qa/journey_plan.md` / `journey_result.md`, PASS —
  re-verified 2026-07-18 after issue `b8f4ce10` was fixed). An
  established lord renames their city, reorders and abandons queued
  production, and lives through one live turn boundary — crossing
  stories 873/874/879/880.

  Also codifies QA issue `b8f4ce10` as an explicit regression: selecting
  a `:bronze_spearman` unit used to crash `GameLive.Play` with a
  `FunctionClauseError` in `UnitPanel.unit_type_label/1` (no clause for
  that type) — fixed by adding an explicit `:bronze_spearman` clause
  plus a catch-all fallback
  (`lib/broken_oaths_web/live/game_live/unit_panel.ex:150-163`).

  Drives the real `BrokenOathsWeb.GameLive.Play` in-process via
  `Phoenix.LiveViewTest`, exactly like the existing `test/spex/` suite
  — see `NewPlayerSettlesTest`'s moduledoc for why this is the right
  harness and not Wallaby.

  The city-management steps run EARLY, on a freshly founded (still
  size-1) city, specifically to keep every measurement below the
  city's own first-growth threshold (`Yields.threshold(1, _) == 20`
  food) — `criterion_7469`'s own moduledoc establishes that this
  world's fixed seed (424242, via `SharedGivens.a_world/1`) grows a
  fresh city from size 1 to 2 around turn 5, so the two turn
  boundaries advanced here land comfortably before any growth-driven
  food reset could make "food rose" or "banked production rose"
  non-deterministic. The bronze_spearman crash-check runs LAST, after
  many more turns, once none of the remaining assertions depend on
  exact per-turn timing any more.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  test "an established lord manages their city through a full turn boundary, and selecting a bronze_spearman never crashes the view (QA issue b8f4ce10)" do
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

    render_hook(play_live, "select_city", %{"city_id" => city.id})
    assert has_element?(play_live, "[data-test='city-panel']")

    # Step 4: rename the city — the header updates and survives a full
    # reload.
    render_hook(play_live, "rename_city", %{"city" => %{"name" => "Oakhaven"}})
    assert has_element?(play_live, "[data-test='city-name']", "Oakhaven")

    {:ok, reloaded_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
    render_hook(reloaded_live, "select_city", %{"city_id" => city.id})
    assert has_element?(reloaded_live, "[data-test='city-name']", "Oakhaven")

    # Step 5: queue Warrior then Worker; a turn boundary banks progress
    # onto the current (Warrior) item, then the Worker's move-up arrow
    # swaps the order without touching either item's banked value.
    render_hook(reloaded_live, "queue_production", %{"city_id" => city.id, "item" => "warrior"})
    render_hook(reloaded_live, "queue_production", %{"city_id" => city.id, "item" => "worker"})

    [%{type: :warrior} = warrior_item, %{type: :worker} = worker_item] =
      current_city(context.world, context.user, city.id).queue

    Fixtures.advance_turn(context.world)

    [current_before | _] = current_city(context.world, context.user, city.id).queue
    assert current_before.id == warrior_item.id
    assert current_before.banked > 0
    banked_before = current_before.banked

    render_hook(reloaded_live, "reorder_production_item", %{
      "city_id" => city.id,
      "item_id" => worker_item.id
    })

    [head, tail] = current_city(context.world, context.user, city.id).queue
    assert head.id == worker_item.id
    assert head.banked == 0
    assert tail.id == warrior_item.id
    assert tail.banked == banked_before

    # Step 6: abandoning the current (now Worker) item forfeits its
    # (zero) progress; the Warrior becomes current again at its OWN
    # already-banked value, not reset to zero.
    render_hook(reloaded_live, "cancel_production_item", %{
      "city_id" => city.id,
      "item_id" => head.id
    })

    [current] = current_city(context.world, context.user, city.id).queue
    assert current.id == warrior_item.id
    assert current.banked == banked_before

    # Step 7: one live turn boundary — food and the current build's
    # banked value both increase, and the top-bar turn counter ticks.
    turn_before = turn_number(render(reloaded_live))
    food_before = current_city(context.world, context.user, city.id).food

    Fixtures.advance_turn(context.world)

    turn_after = turn_number(render(reloaded_live))
    city_after = current_city(context.world, context.user, city.id)

    assert turn_after == turn_before + 1
    assert city_after.food > food_before

    [current_after | _] = city_after.queue
    assert current_after.id == warrior_item.id
    assert current_after.banked > banked_before

    # --- The crux: selecting a bronze_spearman must never crash the
    # view. Clear the queue, reach the Bronze Age, queue one, and
    # select it once it spawns.
    render_hook(reloaded_live, "cancel_production_item", %{
      "city_id" => city.id,
      "item_id" => current_after.id
    })

    # Story 902 (expanded per issue 133b4893): Bronze Working now
    # requires Mining first, so it's researched to completion before
    # Bronze Working can even be selected.
    render_hook(reloaded_live, "toggle_tech_panel", %{})
    render_hook(reloaded_live, "select_research", %{"tech" => "mining"})

    Enum.reduce_while(1..60, :ok, fn _, :ok ->
      if has_element?(reloaded_live, "[data-test='tech-completed-mining']") do
        {:halt, :ok}
      else
        Fixtures.advance_turn(context.world)
        {:cont, :ok}
      end
    end)

    render_hook(reloaded_live, "select_research", %{"tech" => "bronze_working"})
    render_hook(reloaded_live, "bronze_working_confirm", %{})

    for _ <- 1..60, do: Fixtures.advance_turn(context.world)

    render_hook(reloaded_live, "queue_production", %{
      "city_id" => city.id,
      "item" => "bronze_spearman"
    })

    for _ <- 1..30, do: Fixtures.advance_turn(context.world)

    spearman =
      Enum.find(
        Fixtures.player_units(context.world, context.user),
        &(&1.type == :bronze_spearman)
      )

    assert spearman != nil,
           "no Bronze Spearman ever spawned — cannot exercise the b8f4ce10 regression"

    render_hook(reloaded_live, "select_unit", %{"unit_id" => spearman.id})

    assert Process.alive?(reloaded_live.pid),
           "selecting the bronze_spearman crashed GameLive.Play (QA issue b8f4ce10)"

    assert has_element?(reloaded_live, "[data-test='unit-panel']")
    assert has_element?(reloaded_live, "[data-test='unit-type']", "Bronze Spearman")
  end

  defp current_city(world, user, city_id) do
    [city] = for c <- Fixtures.player_cities(world, user), c.id == city_id, do: c
    city
  end

  defp turn_number(html) do
    [turn] = Regex.run(~r/data-test="turn-number"[^>]*>(\d+)</, html, capture: :all_but_first)
    String.to_integer(turn)
  end
end
