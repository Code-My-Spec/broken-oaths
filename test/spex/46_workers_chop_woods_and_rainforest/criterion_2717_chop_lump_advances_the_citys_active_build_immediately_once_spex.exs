defmodule BrokenOathsSpex.Story948.Criterion2717Spex do
  @moduledoc """
  Story 948 — Workers chop woods and rainforest
  Criterion 2717 — the chop lump advances the city's active build
  IMMEDIATELY (same render as the click, no turn boundary needed) and
  ONLY ONCE (a second turn boundary with no further chop doesn't bank
  another lump).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Chop lump advances the city's active build immediately, once" do
    scenario "the queue banks the lump on the chop's own click, and a later turn boundary banks nothing extra" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "a worker stands on a choppable woods tile in the city's own territory, Mining researched",
             context do
        [city] = Fixtures.player_cities(context.world, context.user)

        render_hook(context.play_live, "queue_production", %{
          "city_id" => city.id,
          "item" => "worker"
        })

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

        woods? = fn t ->
          Fixtures.tile_class(context.world, t) == :land and t in city.territory and
            Fixtures.tile_terrain(context.world, t).feature in [:woods, :rainforest]
        end

        woods_tile = Enum.find(city.territory, woods?)

        assert woods_tile,
               "expected a woods/rainforest tile inside the founded city's own territory"

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => worker.id,
          "to_tile" => woods_tile
        })

        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [w] = for u <- Fixtures.player_units(context.world, context.user), u.id == worker.id, do: u

          if w.tile_id == woods_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        # Settler (100 production), not Warrior (40) — the observation
        # window below (chop lump + 2 ordinary turns of accrual) can
        # plausibly finish a 40-cost item outright, which would empty
        # the queue and crash the `[item | _] = city.queue` reads below
        # with an unrelated MatchError. A 100-cost item can't complete
        # within this window regardless of exact lump/income numbers,
        # so the queue head being observed is guaranteed to still be
        # this same item throughout.
        render_hook(context.play_live, "queue_production", %{
          "city_id" => city.id,
          "item" => "settler"
        })

        {:ok, context |> Map.put(:worker, worker) |> Map.put(:city_id, city.id)}
      end

      when_ "the worker chops the tile", context do
        render_hook(context.play_live, "chop", %{"unit_id" => context.worker.id})
        {:ok, context}
      end

      then_ "the lump is already banked before any turn boundary passes", context do
        [city] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id == context.city_id,
            do: c

        [item | _] = city.queue
        assert item.banked > 0, "expected the chop's lump to be banked immediately, no wait needed"
        {:ok, Map.put(context, :banked_right_after_chop, item.banked)}
      end

      then_ "a later turn boundary with no further chop banks nothing extra from this chop", context do
        # `Production.accrue/4`'s real per-turn income is
        # `flat_production + worked_production(...) + bonuses` — NOT a
        # bare flat constant (a founded city's own worked tile(s)
        # contribute too), so asserting against a hardcoded "flat 5"
        # ceiling is wrong regardless of whether a chop-repeat bug
        # exists. Instead, compare TWO CONSECUTIVE ordinary turn deltas
        # to EACH OTHER: if the first post-chop turn banked the same
        # amount as the next ordinary turn, only steady per-turn income
        # happened — a second, chop-lump-sized jump on just the first
        # turn would break that equality regardless of what the real
        # steady-state income actually is.
        Fixtures.advance_turn(context.world)

        [city_after_turn_1] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id == context.city_id,
            do: c

        [item_after_turn_1 | _] = city_after_turn_1.queue
        banked_after_turn_1 = item_after_turn_1.banked

        Fixtures.advance_turn(context.world)

        [city_after_turn_2] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id == context.city_id,
            do: c

        [item_after_turn_2 | _] = city_after_turn_2.queue
        banked_after_turn_2 = item_after_turn_2.banked

        first_turn_delta = banked_after_turn_1 - context.banked_right_after_chop
        second_turn_delta = banked_after_turn_2 - banked_after_turn_1

        assert first_turn_delta == second_turn_delta,
               "expected only the ordinary per-turn production accrual (#{second_turn_delta}) on the first post-chop turn too, got #{first_turn_delta} — a repeated chop lump would inflate just that first turn's delta"

        {:ok, context}
      end
    end
  end
end
