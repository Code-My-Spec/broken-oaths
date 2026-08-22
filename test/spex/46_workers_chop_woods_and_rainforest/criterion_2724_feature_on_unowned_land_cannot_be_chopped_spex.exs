defmodule BrokenOathsSpex.Story948.Criterion2724Spex do
  @moduledoc """
  Story 948 — Workers chop woods and rainforest
  Criterion 2724 — a feature on unowned land cannot be chopped: a
  worker standing on a woods/rainforest tile OUTSIDE any of its own
  owner's cities' territory gets no Chop button
  (`worker_choppable_feature/5`'s own `owns_tile?/2` gate), even with
  the tech researched.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Feature on unowned land cannot be chopped" do
    scenario "no Chop button renders for a worker on a woods tile outside the city's own territory" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "a worker stands on a woods tile OUTSIDE the city's own territory, Mining researched",
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

        unowned_woods? = fn t ->
          Fixtures.tile_class(context.world, t) == :land and t not in city.territory and
            Fixtures.tile_terrain(context.world, t).feature in [:woods, :rainforest]
        end

        outside_tile =
          Enum.find(0..(Fixtures.tile_count(context.world) - 1), unowned_woods?)

        assert outside_tile,
               "expected a woods/rainforest tile somewhere outside the founded city's own territory"

        :ok = Fixtures.relocate_unit(context.world, worker.id, outside_tile)

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
