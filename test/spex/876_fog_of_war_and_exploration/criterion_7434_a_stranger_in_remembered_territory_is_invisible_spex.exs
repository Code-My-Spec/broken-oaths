defmodule BrokenOathsSpex.Story876.Criterion7434Spex do
  @moduledoc """
  Story 876 — Fog of War and Exploration
  Criterion 7434 — live entities never show on remembered-but-unwatched terrain.

  Fog truth surfaces (board doctrine): the fog-filtered board pushes —
  "game:visibility" (visible/explored tile ids), "game:window" (tile
  geometry, fog-filtered), "game:units" (visible units only). The
  canvas paint is never asserted.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a stranger in remembered territory is invisible" do
    scenario "another player's unit disappears when it leaves your vision" do
      given_ :a_world
      given_ :registered_player
      given_ :second_registered_player

      given_ "both players joined the world", context do
        for conn <- [context.conn, context.other_conn] do
          {:ok, join_live, _html} = live(conn, ~p"/play")

          join_live
          |> element("[data-test='join-world-#{context.world.id}']")
          |> render_click()
        end

        {:ok, context}
      end

      given_ "this player's lord has scouted up to the stranger and seen them", context do
        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [lord | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        [stranger | _] = Fixtures.player_units(context.world, context.other_user)

        render_hook(play_live, "queue_move", %{"unit_id" => lord.id, "to_tile" => stranger.tile_id})

        # walk until the stranger enters vision (bounded)
        seen =
          Enum.reduce_while(1..30, false, fn _, _ ->
            Fixtures.advance_turn(context.world)
            assert_push_event(play_live, "game:units", %{units: units}, 1000)

            if Enum.any?(units, &(&1.id == stranger.id)),
              do: {:halt, true},
              else: {:cont, false}
          end)

        assert seen, "the lord never reached the stranger's area"

        context =
          context
          |> Map.put(:play_live, play_live)
          |> Map.put(:lord, lord)
          |> Map.put(:stranger, stranger)

        {:ok, context}
      end

      when_ "the lord retreats until the stranger's tile is out of vision", context do
        land? = fn tile -> Fixtures.tile_class(context.world, tile) == :land end

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == context.lord.id, do: u

        retreat =
          Enum.reduce(1..5, [lord.tile_id], fn _, [here | _] = acc ->
            next =
              context.world
              |> Fixtures.adjacent_tiles(here)
              |> Enum.reject(&(&1 in acc))
              |> Enum.filter(land?)
              |> List.first()

            [next | acc]
          end)

        render_hook(context.play_live, "queue_move", %{"unit_id" => lord.id, "to_tile" => hd(retreat)})
        for _ <- 1..5, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the stranger's terrain is remembered but the stranger is gone", context do
        assert_push_event(context.play_live, "game:visibility", %{explored: explored})
        assert context.stranger.tile_id in explored

        assert_push_event(context.play_live, "game:units", %{units: units})
        refute Enum.any?(units, &(&1.id == context.stranger.id))
        {:ok, context}
      end
    end
  end
end
