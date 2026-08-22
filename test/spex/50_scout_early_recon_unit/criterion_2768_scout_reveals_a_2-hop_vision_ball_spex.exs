defmodule BrokenOathsSpex.Story952.Criterion2768Spex do
  @moduledoc """
  Story 952 — Scout — early recon unit
  Criterion 2768 — a Scout reveals a 2-hop vision ball around itself
  (`Visibility.vision_radius(:scout) == 2`, the same default every
  non-Lord unit gets). Mirrors story 876's own established vision-ring
  pattern (`BrokenOathsSpex.Story876.Criterion7432Spex`): the fog truth
  surface is the "game:visibility" push (`visible` tile ids), never the
  canvas paint.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Scout reveals a 2-hop vision ball" do
    scenario "every tile within 2 hops of the Scout is visible" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "a Scout has been built", context do
        render_hook(context.play_live, "queue_production", %{
          "city_id" => context.city.id,
          "item" => "scout"
        })

        Enum.reduce_while(1..15, :ok, fn _, :ok ->
          if Enum.any?(Fixtures.player_units(context.world, context.user), &(&1.type == :scout)) do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [scout] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :scout, do: u

        {:ok, Map.put(context, :scout, scout)}
      end

      when_ "the visibility set arrives", context do
        assert_push_event(context.play_live, "game:visibility", %{visible: visible})
        {:ok, Map.put(context, :visible, visible)}
      end

      then_ "every tile within 2 hops of the Scout is in the visible set", context do
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

        for tile <- ring.(context.scout.tile_id, 2), do: assert(tile in context.visible)
        {:ok, context}
      end
    end
  end
end
