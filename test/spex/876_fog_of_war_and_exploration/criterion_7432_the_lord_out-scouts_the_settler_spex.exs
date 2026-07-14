defmodule BrokenOathsSpex.Story876.Criterion7432Spex do
  @moduledoc """
  Story 876 — Fog of War and Exploration
  Criterion 7432 — vision radius is 3 around the Lord and 2 around other units.

  Fog truth surfaces (board doctrine): the fog-filtered board pushes —
  "game:visibility" (visible/explored tile ids), "game:window" (tile
  geometry, fog-filtered), "game:units" (visible units only). The
  canvas paint is never asserted.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the lord out-scouts the settler" do
    scenario "vision follows each unit's range" do
      given_ :a_world
      given_ :registered_player

      given_ "the player joined the world and is on the board", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :play_live, play_live)}
      end

      when_ "the visibility set arrives", context do
        assert_push_event(context.play_live, "game:visibility", %{visible: visible})
        {:ok, Map.put(context, :visible, visible)}
      end

      then_ "every tile within 3 of the Lord and within 2 of the Settler is visible", context do
        ring = fn start, depth ->
          Enum.reduce(1..depth, {[start], [start]}, fn _, {frontier, seen} ->
            next =
              frontier
              |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
              |> Enum.uniq()
              |> Enum.reject(&(&1 in seen))

            {next, seen ++ next}
          end)
          |> elem(1)
        end

        units = Fixtures.player_units(context.world, context.user)
        [lord | _] = for u <- units, u.type == :lord, do: u
        [settler | _] = for u <- units, u.type == :settler, do: u

        for tile <- ring.(lord.tile_id, 3), do: assert(tile in context.visible)
        for tile <- ring.(settler.tile_id, 2), do: assert(tile in context.visible)
        {:ok, context}
      end
    end
  end
end
