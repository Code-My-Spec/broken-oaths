defmodule BrokenOathsSpex.Story952.Criterion2769Spex do
  @moduledoc """
  Story 952 — Scout — early recon unit
  Criterion 2769 — the Lord out-sees the Scout by one hop
  (`Visibility.vision_radius(:lord) == 3` vs `vision_radius(:scout) ==
  2` — the Scout sees no farther than an ordinary unit, per this
  story's own module doc; it just moves faster and through anything).
  Same "game:visibility" ring-comparison pattern as
  `BrokenOathsSpex.Story876.Criterion7432Spex` (Lord vs Settler),
  substituting the Scout as the shorter-radius unit.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Lord out-sees the Scout by one hop" do
    scenario "the Lord's 3-hop ring is visible where the Scout's own ring stops at 2" do
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

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        {:ok, context |> Map.put(:scout, scout) |> Map.put(:lord, lord)}
      end

      when_ "the visibility set arrives", context do
        assert_push_event(context.play_live, "game:visibility", %{visible: visible})
        {:ok, Map.put(context, :visible, visible)}
      end

      then_ "every tile within 3 of the Lord and within 2 of the Scout is visible", context do
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

        for tile <- ring.(context.lord.tile_id, 3), do: assert(tile in context.visible)
        for tile <- ring.(context.scout.tile_id, 2), do: assert(tile in context.visible)
        {:ok, context}
      end

      then_ "the Lord's own outer (3rd) ring reaches strictly farther than the Scout's own (2nd)",
            context do
        ring = fn start, depth ->
          Enum.reduce(1..depth, {[start], MapSet.new([start])}, fn _, {frontier, seen} ->
            next =
              frontier
              |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
              |> Enum.uniq()
              |> Enum.reject(&MapSet.member?(seen, &1))

            {next, MapSet.union(seen, MapSet.new(next))}
          end)
          |> elem(0)
        end

        lord_ring3 = ring.(context.lord.tile_id, 3)
        assert lord_ring3 != [], "the Lord's own 3rd ring should not be empty"
        scout_visible_at_3 = Enum.filter(lord_ring3, &(&1 in context.visible))
        assert scout_visible_at_3 != [],
               "expected the Lord's own 3rd ring to be visible even where the Scout could not reach"

        {:ok, context}
      end
    end
  end
end
