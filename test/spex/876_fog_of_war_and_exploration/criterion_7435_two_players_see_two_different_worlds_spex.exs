defmodule BrokenOathsSpex.Story876.Criterion7435Spex do
  @moduledoc """
  Story 876 — Fog of War and Exploration
  Criterion 7435 — exploration is per player — each sees their own area, not the other\u2019s.

  Fog truth surfaces (board doctrine): the fog-filtered board pushes —
  "game:visibility" (visible/explored tile ids), "game:window" (tile
  geometry, fog-filtered), "game:units" (visible units only). The
  canvas paint is never asserted.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "two players see two different worlds" do
    scenario "each spawn bubble is private" do
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

      when_ "both players look at their boards", context do
        {:ok, mine, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        {:ok, theirs, _html} = live(context.other_conn, ~p"/play/#{context.world.id}")

        assert_push_event(mine, "game:visibility", %{visible: my_visible, explored: my_explored})
        assert_push_event(theirs, "game:visibility", %{visible: their_visible, explored: their_explored})

        context =
          context
          |> Map.put(:my_known, Enum.uniq(my_visible ++ my_explored))
          |> Map.put(:their_known, Enum.uniq(their_visible ++ their_explored))

        {:ok, context}
      end

      then_ "neither player's map covers the other's spawn", context do
        [my_unit | _] = Fixtures.player_units(context.world, context.user)
        [their_unit | _] = Fixtures.player_units(context.world, context.other_user)

        assert my_unit.tile_id in context.my_known
        refute their_unit.tile_id in context.my_known
        assert their_unit.tile_id in context.their_known
        refute my_unit.tile_id in context.their_known
        {:ok, context}
      end
    end
  end
end
