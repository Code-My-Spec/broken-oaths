defmodule BrokenOathsSpex.Story948.Criterion2730Spex do
  @moduledoc """
  Story 948 — Workers chop woods and rainforest
  Criterion 2730 — a tile an enemy unit holds cannot be chopped. Unlike
  tech/territory/charges (pre-filtered out of the button entirely, see
  Criterion2719/2724/2727), `worker_choppable_feature/5`'s own doc says
  the hostile co-occupant refusal is deliberately left to the real
  `chop/3` command's own error toast — so here the Chop button DOES
  render, but clicking it surfaces `chop-error` instead of clearing the
  tile.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Cannot chop a tile an enemy unit holds" do
    scenario "chopping refuses with an error when a rival player's unit shares the tile" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)
      given_(:a_founded_city)

      given_ "a worker stands on a woods tile in the city's own territory, Mining researched, sharing the tile with a rival's unit",
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

        {:ok, other_player} = Fixtures.join_world(context.world, context.other_user)

        # A freshly-joined player spawns with more than one starting
        # unit (a Lord AND a Settler) — this criterion only needs ONE
        # of them holding the tile, so pick a specific, deterministic
        # one (the Lord) rather than assuming there's exactly one unit
        # to destructure.
        [rival | _] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :lord,
              do: u

        # `relocate_unit/3`'s own occupancy guard refuses this on
        # purpose — our own worker already stands on `woods_tile` (just
        # marched there above), and every test-only placement path
        # enforces "one unit per hex" the same way real movement does.
        # But that's exactly the precondition this criterion needs to
        # construct: a hostile unit sharing the worker's own tile
        # (`Improvement.validate_chop_not_hostile_occupied/2` explicitly
        # anticipates this as a reachable state to detect and refuse) —
        # nothing in normal gameplay can walk a unit onto an
        # already-occupied tile either, so there's no "real" path to
        # this state to drive instead. `force_relocate_unit/3` is the
        # deliberate, narrow bypass built for exactly this case.
        :ok = Fixtures.force_relocate_unit(context.world, rival.id, woods_tile)

        _ = other_player

        {:ok, context |> Map.put(:worker, worker) |> Map.put(:woods_tile, woods_tile)}
      end

      when_ "the worker attempts to chop the tile", context do
        render_hook(context.play_live, "chop", %{"unit_id" => context.worker.id})
        {:ok, context}
      end

      then_ "a chop error appears and the tile keeps its feature", context do
        assert has_element?(context.play_live, "[data-test='chop-error']")

        terrain = Fixtures.tile_terrain(context.world, context.woods_tile)
        assert terrain.feature in [:woods, :rainforest]

        {:ok, context}
      end
    end
  end
end
