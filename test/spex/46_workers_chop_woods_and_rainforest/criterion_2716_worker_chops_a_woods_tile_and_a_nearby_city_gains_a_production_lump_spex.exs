defmodule BrokenOathsSpex.Story948.Criterion2716Spex do
  @moduledoc """
  Story 948 — Workers chop woods and rainforest
  Criterion 2716 — a worker chops a woods tile and a nearby city gains
  a one-time production lump (`Improvement.chop_yield/2`, credited to
  whichever of the chopper's own cities holds the tile in its
  territory).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Worker chops a woods tile and a nearby city gains a production lump" do
    scenario "the city's queued build banks extra production after the chop" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "a worker exists, Mining is researched, and a woods tile in the city's own territory is known",
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

        render_hook(context.play_live, "queue_production", %{
          "city_id" => city.id,
          "item" => "warrior"
        })

        [city_before] = Fixtures.player_cities(context.world, context.user)
        [item_before | _] = city_before.queue

        {:ok,
         context
         |> Map.put(:worker, worker)
         |> Map.put(:city_id, city.id)
         |> Map.put(:banked_before, item_before.banked)}
      end

      when_ "the worker chops the woods tile", context do
        render_hook(context.play_live, "chop", %{"unit_id" => context.worker.id})
        {:ok, context}
      end

      then_ "the city's active build immediately banks a production lump", context do
        [city_after] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id == context.city_id,
            do: c

        [item_after | _] = city_after.queue

        assert item_after.banked > context.banked_before,
               "expected the chop to credit the city's active build with a production lump"

        {:ok, context}
      end
    end
  end
end
