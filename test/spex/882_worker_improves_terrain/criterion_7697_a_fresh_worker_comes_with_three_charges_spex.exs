defmodule BrokenOathsSpex.Story882.Criterion7697Spex do
  @moduledoc """
  Story 882 — Worker Improves Terrain
  Criterion 7697 — playtest update (issue 1caa87e9, worker build
  charges): a newly built worker starts with 3 build charges. Mirrors
  `Criterion7481Spex`'s own production-completion flow exactly, just
  asserting `charges` instead of hp/combat actions.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a fresh worker comes with three charges" do
    scenario "a city finishes producing a worker for 60 production" do
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

        {:ok, Map.put(context, :play_live, play_live)}
      end

      when_ "the worker appears on the map", context do
        # Worker (60) at the flat 5/turn base rate (story 879) completes
        # in exactly 12 turns.
        for _ <- 1..12, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "it has 3 build charges available", context do
        [worker] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :worker, do: u

        assert worker.charges == 3
        {:ok, context}
      end
    end
  end
end
