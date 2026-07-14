defmodule BrokenOathsSpex.Story874.Criterion7422Spex do
  @moduledoc """
  Story 874 — Automatic Turn Processing
  Criterion 7422 — queued orders hold until the boundary, then resolve simultaneously.

  Turn boundaries are wall-clock (60s) in production. Specs use the
  sanctioned deterministic tick (`Fixtures.advance_turn/1`) instead of
  sleeping — the tick is exactly what the timer fires.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "nothing moves until the boundary, then everything moves at once" do
    scenario "two players' queued moves resolve in the same tick" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "both players joined the world", context do
        for conn <- [context.conn, context.other_conn] do
          {:ok, join_live, _html} = live(conn, ~p"/play")

          join_live
          |> element("[data-test='join-world-#{context.world.id}']")
          |> render_click()
        end

        {:ok, context}
      end

      given_ "each player queues a move for one of their units", context do
        moves =
          for {conn, user} <- [
                {context.conn, context.user},
                {context.other_conn, context.other_user}
              ] do
            {:ok, play_live, _html} = live(conn, ~p"/play/#{context.world.id}")
            [unit | _] = Fixtures.player_units(context.world, user)
            [target | _] = Fixtures.adjacent_tiles(context.world, unit.tile_id)
            render_hook(play_live, "queue_move", %{"unit_id" => unit.id, "to_tile" => target})
            {user, unit.id, unit.tile_id, target}
          end

        {:ok, Map.put(context, :moves, moves)}
      end

      when_ "the boundary has not yet fired", context do
        for {user, unit_id, from, _target} <- context.moves do
          [unit] = for u <- Fixtures.player_units(context.world, user), u.id == unit_id, do: u
          assert unit.tile_id == from
        end

        {:ok, context}
      end

      then_ "after one tick both moves have resolved together", context do
        Fixtures.advance_turn(context.world)

        for {user, unit_id, _from, target} <- context.moves do
          [unit] = for u <- Fixtures.player_units(context.world, user), u.id == unit_id, do: u
          assert unit.tile_id == target
        end

        {:ok, context}
      end
    end
  end
end
