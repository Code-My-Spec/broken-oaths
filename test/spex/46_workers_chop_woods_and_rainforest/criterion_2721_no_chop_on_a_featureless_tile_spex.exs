defmodule BrokenOathsSpex.Story948.Criterion2721Spex do
  @moduledoc """
  Story 948 — Workers chop woods and rainforest
  Criterion 2721 — no Chop button on a featureless tile (bare
  grassland/plains/etc, no woods or rainforest), even with the tech
  researched and the worker inside its own borders — every OTHER
  legality condition met, only the feature itself missing.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "No chop on a featureless tile" do
    scenario "no Chop button renders for a worker standing on bare land with Mining already researched" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "a worker stands on a featureless tile in the city's own territory, Mining researched",
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

        featureless? = fn t ->
          Fixtures.tile_class(context.world, t) == :land and t in city.territory and
            is_nil(Fixtures.tile_terrain(context.world, t).feature)
        end

        bare_tile = Enum.find(city.territory, featureless?)

        assert bare_tile,
               "expected a featureless land tile inside the founded city's own territory"

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => worker.id,
          "to_tile" => bare_tile
        })

        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [w] = for u <- Fixtures.player_units(context.world, context.user), u.id == worker.id, do: u

          if w.tile_id == bare_tile do
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

      then_ "no Chop button appears, though the panel itself renders", context do
        assert has_element?(context.play_live, "[data-test='fortify']")
        refute has_element?(context.play_live, "[data-test='chop-woods']")
        refute has_element?(context.play_live, "[data-test='chop-rainforest']")
        {:ok, context}
      end
    end
  end
end
