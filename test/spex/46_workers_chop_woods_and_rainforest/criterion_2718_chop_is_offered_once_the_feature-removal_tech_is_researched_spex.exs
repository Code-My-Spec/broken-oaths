defmodule BrokenOathsSpex.Story948.Criterion2718Spex do
  @moduledoc """
  Story 948 — Workers chop woods and rainforest
  Criterion 2718 — chop IS offered once the feature-removal tech
  (Mining, for Woods) is researched — the mirror image of Criterion2719
  (blocked before).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Chop is offered once the feature-removal tech is researched" do
    scenario "the Chop button renders for a worker on a woods tile once Mining is researched" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "a worker stands on a woods tile in the city's own territory, Mining researched",
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

        {:ok, Map.put(context, :worker, worker)}
      end

      when_ "the worker is selected", context do
        render_hook(context.play_live, "select_unit", %{"unit_id" => context.worker.id})
        {:ok, context}
      end

      then_ "the Chop Woods button renders", context do
        assert has_element?(context.play_live, "[data-test='chop-woods']")
        {:ok, context}
      end
    end
  end
end
