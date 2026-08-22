defmodule BrokenOathsSpex.Story948.Criterion2727Spex do
  @moduledoc """
  Story 948 — Workers chop woods and rainforest
  Criterion 2727 — a worker with no charges left cannot chop: after
  spending all 3 of its own starting build charges on 3 REAL chops (one
  per distinct woods/rainforest tile, matching Criterion2726's
  one-charge-per-chop fact), there is no worker left able to chop at
  all. Per `BrokenOaths.Units.Unit`'s own moduledoc, a worker's last
  charge spent removes the unit OUTRIGHT — the same removal path a
  combat death already uses — mirroring Civ 6's Builder-consumption
  convention (story 882, issue 1caa87e9). So "cannot chop" isn't a
  disabled/hidden button on a still-standing worker; there is no
  worker left to select at all. Selecting its old id after the 3rd
  chop and asserting the panel/button state (the original shape of
  this spec) would be asserting nothing, since nothing renders for a
  unit id that no longer exists — asserting the unit's own absence
  from `player_units` is the faithful, strongest form of "cannot
  chop" the real implementation actually guarantees.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "A worker with no charges left cannot chop" do
    scenario "the worker itself is removed once its 3 starting charges are all spent" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player's city is founded with 3 choppable tiles in its own ring", context do
        {:ok,
         found_city_with_enough_feature(context, 3, &(&1.feature in [:woods, :rainforest]))}
      end

      given_ "a worker has chopped 3 separate woods/rainforest tiles, exhausting its own charges",
             context do
        # This scenario advances well over 100 turns total (production
        # queue + tech research + 3 separate marches) — by far the
        # longest-running setup in this story's batch. Left unguarded,
        # a wandering barbarian could kill the tracked worker mid-setup
        # (the same interference `clear_all_camps/1`'s own moduledoc
        # warns every long-running scenario about).
        clear_all_camps(context.world)

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

        three_tiles =
          context.world
          |> Fixtures.adjacent_tiles(city.tile_id)
          |> Enum.filter(choppable?)
          |> Enum.take(3)

        assert length(three_tiles) == 3,
               "expected at least 3 distinct woods/rainforest tiles inside the founded city's own ring (guaranteed by found_city_with_enough_feature/4)"

        for tile <- three_tiles do
          render_hook(context.play_live, "queue_move", %{
            "unit_id" => worker.id,
            "to_tile" => tile
          })

          Enum.reduce_while(1..10, :ok, fn _, :ok ->
            [w] = for u <- Fixtures.player_units(context.world, context.user), u.id == worker.id, do: u

            if w.tile_id == tile do
              {:halt, :ok}
            else
              Fixtures.advance_turn(context.world)
              {:cont, :ok}
            end
          end)

          render_hook(context.play_live, "chop", %{"unit_id" => worker.id})
        end

        {:ok, Map.put(context, :worker, worker)}
      end

      when_ "the player's units are checked after the worker's 3rd and final chop", context do
        {:ok, context}
      end

      then_ "the worker no longer exists — its last charge removed it, the same removal path a combat death uses, so nothing is left able to chop",
            context do
        remaining =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.worker.id,
              do: u

        assert remaining == [],
               "expected the worker to have been removed once its last charge was spent " <>
                 "(Unit's own moduledoc: charges hitting 0 removes the unit outright, the " <>
                 "same path a combat death uses) — found it still present instead"

        {:ok, context}
      end
    end
  end
end
