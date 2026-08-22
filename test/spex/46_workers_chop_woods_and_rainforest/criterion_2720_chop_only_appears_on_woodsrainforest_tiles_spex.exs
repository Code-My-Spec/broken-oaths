defmodule BrokenOathsSpex.Story948.Criterion2720Spex do
  @moduledoc """
  Story 948 — Workers chop woods and rainforest
  Criterion 2720 — chop only appears on woods/RAINFOREST tiles too, not
  just Woods (Criterion2718 already covers the Woods/Mining case) — the
  Chop button generalizes to the second eligible feature type, gated on
  its own tech (Bronze Working, via `chop_rainforest_enabled?/1`).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Chop only appears on woods/rainforest tiles" do
    scenario "the Chop Rainforest button renders once Bronze Working is researched" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player's city is founded with a rainforest tile in its own ring", context do
        {:ok, found_city_with_enough_feature(context, 1, &(&1.feature == :rainforest))}
      end

      given_ "a worker stands on a rainforest tile in the city's own territory, Bronze Working researched",
             context do
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

        rainforest_tile =
          context.world
          |> Fixtures.adjacent_tiles(city.tile_id)
          |> Enum.find(&(Fixtures.tile_terrain(context.world, &1).feature == :rainforest))

        assert rainforest_tile,
               "expected a rainforest tile inside the founded city's own ring (guaranteed by found_city_with_enough_feature/4)"

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => worker.id,
          "to_tile" => rainforest_tile
        })

        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [w] = for u <- Fixtures.player_units(context.world, context.user), u.id == worker.id, do: u

          if w.tile_id == rainforest_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok, Map.put(context, :worker, worker)}
      end

      when_ "the worker is selected", context do
        render_hook(context.play_live, "select_unit", %{"unit_id" => context.worker.id})
        {:ok, context}
      end

      then_ "the Chop Rainforest button renders", context do
        assert has_element?(context.play_live, "[data-test='chop-rainforest']")
        {:ok, context}
      end
    end
  end
end
