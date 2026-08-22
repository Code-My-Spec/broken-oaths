defmodule BrokenOathsSpex.Story948.Criterion2728Spex do
  @moduledoc """
  Story 948 — Workers chop woods and rainforest
  Criterion 2728 — a later-game chop yields a larger lump than an early
  one: `chop_yield/2` scales `20 + 8 * completed_tech_count`, so the
  SAME player's second chop (after researching a further tech) banks
  more than their first did.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "A later-game chop yields a larger lump than an early one" do
    scenario "a chop made after researching a second tech banks more than the first chop did" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player's city is founded with 2 choppable tiles in its own ring", context do
        {:ok,
         found_city_with_enough_feature(context, 2, &(&1.feature in [:woods, :rainforest]))}
      end

      given_ "a worker has chopped one woods tile with only Mining researched", context do
        city = context.city

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

        choppable? = fn t -> Fixtures.tile_terrain(context.world, t).feature in [:woods, :rainforest] end

        two_tiles =
          context.world |> Fixtures.adjacent_tiles(city.tile_id) |> Enum.filter(choppable?) |> Enum.take(2)

        assert length(two_tiles) == 2,
               "expected at least 2 distinct woods/rainforest tiles inside the founded city's own ring (guaranteed by found_city_with_enough_feature/4)"

        [first_tile, second_tile] = two_tiles

        # A Warrior (40 production), NOT a Settler: `can_queue?/3` refuses
        # `:settler` outright for a size-1 city (`{:error, :size_one}`,
        # story 883 criterion 7487) — every city here is freshly founded
        # at size 1, so queuing "settler" never lands an item at all and
        # every `[item | _] = queue` read below crashes on `[]` from the
        # very first one, not from completion. A Warrior queues fine at
        # size 1. Its own 40 cost comfortably exceeds either chop lump
        # (20 + 8*completed_tech_count = 28 with Mining, 36 with Mining +
        # Bronze Working — see this spec's own moduledoc), so a FRESH
        # Warrior can't complete from a single chop; it's re-queued again
        # after the long Bronze Working wait below, which is the actual
        # window where ordinary per-turn accrual (not the chop itself)
        # could otherwise complete a long-lived item and empty the queue.
        render_hook(context.play_live, "queue_production", %{
          "city_id" => city.id,
          "item" => "warrior"
        })

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => worker.id,
          "to_tile" => first_tile
        })

        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [w] = for u <- Fixtures.player_units(context.world, context.user), u.id == worker.id, do: u

          if w.tile_id == first_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [city_before_first] = Fixtures.player_cities(context.world, context.user)
        [item_before_first | _] = city_before_first.queue

        render_hook(context.play_live, "chop", %{"unit_id" => worker.id})

        [city_after_first] = Fixtures.player_cities(context.world, context.user)
        [item_after_first | _] = city_after_first.queue
        first_lump = item_after_first.banked - item_before_first.banked

        render_hook(context.play_live, "select_research", %{"tech" => "bronze_working"})
        render_hook(context.play_live, "bronze_working_confirm", %{})

        Enum.reduce_while(1..120, :ok, fn _, :ok ->
          if has_element?(context.play_live, "[data-test='tech-completed-bronze_working']") do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => worker.id,
          "to_tile" => second_tile
        })

        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [w] = for u <- Fixtures.player_units(context.world, context.user), u.id == worker.id, do: u

          if w.tile_id == second_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok, context |> Map.put(:worker, worker) |> Map.put(:first_lump, first_lump)}
      end

      when_ "the worker chops the second tile, now with a further tech completed", context do
        # Guard against the original Warrior having completed somewhere
        # during the 120-turn Bronze Working wait in the given_ block
        # above (ordinary per-turn accrual, not this chop) — re-queue a
        # fresh one so there's guaranteed to be a non-empty, non-complete
        # item to measure the banked delta against.
        [city_before_requeue] = Fixtures.player_cities(context.world, context.user)

        if city_before_requeue.queue == [] do
          render_hook(context.play_live, "queue_production", %{
            "city_id" => context.city.id,
            "item" => "warrior"
          })
        end

        [city_before_second] = Fixtures.player_cities(context.world, context.user)
        [item_before_second | _] = city_before_second.queue

        render_hook(context.play_live, "chop", %{"unit_id" => context.worker.id})

        [city_after_second] = Fixtures.player_cities(context.world, context.user)
        [item_after_second | _] = city_after_second.queue
        second_lump = item_after_second.banked - item_before_second.banked

        {:ok, Map.put(context, :second_lump, second_lump)}
      end

      then_ "the second, later-game lump is bigger than the first", context do
        assert context.second_lump > context.first_lump,
               "expected a chop made after a further tech to yield a bigger lump"

        {:ok, context}
      end
    end
  end
end
