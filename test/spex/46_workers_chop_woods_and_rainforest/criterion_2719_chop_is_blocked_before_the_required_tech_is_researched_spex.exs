defmodule BrokenOathsSpex.Story948.Criterion2719Spex do
  @moduledoc """
  Story 948 — Workers chop woods and rainforest
  Criterion 2719 — chop is BLOCKED before the feature-removal tech
  (Mining, for Woods — `Research.chop_woods_enabled?/1`) is researched:
  `PlayView.worker_choppable_feature/5` never offers the button, so it
  never renders on the worker's own panel.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Chop is blocked before the required tech is researched" do
    scenario "no Chop button renders for a worker on a woods tile before Mining is researched" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "a worker stands on a woods tile in the city's own territory, with no research done yet",
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

      then_ "no Chop button appears anywhere on the unit panel", context do
        # Anchor: the unit panel really did render for this worker (its
        # own Fortify affordance, which every worker-type unit carries
        # regardless of research) — without this, an empty panel would
        # also satisfy both refutes below for the wrong reason.
        assert has_element?(context.play_live, "[data-test='fortify']")

        refute has_element?(context.play_live, "[data-test='chop-woods']")
        refute has_element?(context.play_live, "[data-test='chop-rainforest']")

        {:ok, context}
      end
    end
  end
end
