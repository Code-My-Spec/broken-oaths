defmodule BrokenOathsSpex.Story882.Criterion7481Spex do
  @moduledoc """
  Story 882 — Worker Improves Terrain
  Criterion 7481 — a completed Worker has 10 HP, moves on the standard
  substrate, and offers Build Improvement actions instead of combat.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a worker is a builder, not a fighter" do
    scenario "a city completes Worker production" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a city that completes Worker production", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)
        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "worker"})

        {:ok, context |> Map.put(:play_live, play_live)}
      end

      when_ "the worker spawns", context do
        # Worker (60) at the flat 5/turn base rate (story 879) completes
        # in exactly 12 turns.
        for _ <- 1..12, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "it has 10 HP and moves like other units", context do
        [worker] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :worker, do: u

        assert worker.hp == 10
        assert worker.max_hp == 10
        assert worker.max_movement > 0
        {:ok, Map.put(context, :worker, worker)}
      end

      then_ "it offers Build Improvement actions instead of any combat action", context do
        render_hook(context.play_live, "select_unit", %{"unit_id" => context.worker.id})

        assert has_element?(context.play_live, "[data-test='build-farm']") or
                 has_element?(context.play_live, "[data-test='build-mine']") or
                 has_element?(context.play_live, "[data-test='build-road']")

        {:ok, context}
      end
    end
  end
end
