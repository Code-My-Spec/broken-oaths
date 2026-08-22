defmodule BrokenOathsSpex.Story952.Criterion2772Spex do
  @moduledoc """
  Story 952 — Scout — early recon unit
  Criterion 2772 — a Scout ignores difficult-terrain movement cost
  entirely (`Unit.entry_cost/5`'s own `:scout` clause): entering a
  woods/rainforest/marsh tile costs it 1 movement point, the same as
  open ground, unlike every other land unit's 2.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Scout enters difficult terrain for 1 movement" do
    scenario "a woods/rainforest/marsh tile costs the Scout only 1 movement point" do
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

      given_ "an adjacent difficult-terrain tile is known", context do
        difficult? = fn t ->
          terrain = Fixtures.tile_terrain(context.world, t)
          Fixtures.tile_class(context.world, t) == :land and terrain.feature in [:woods, :rainforest, :marsh]
        end

        difficult_tile =
          find_difficult_tile_near(context.world, context.scout.tile_id, difficult?)

        {:ok, Map.put(context, :difficult_tile, difficult_tile)}
      end

      when_ "the Scout is ordered onto the difficult tile", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.scout.id,
          "to_tile" => context.difficult_tile
        })

        {:ok, context}
      end

      then_ "the Scout arrives having spent exactly 1 movement point", context do
        [scout] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == context.scout.id,
            do: u

        assert scout.tile_id == context.difficult_tile
        assert scout.movement == context.scout.movement - 1
        {:ok, context}
      end
    end
  end

  # Breadth-first search outward from `start` for the nearest tile
  # matching `pred` — a difficult-terrain tile may not sit directly
  # adjacent to the Scout's own spawn point, so this widens the search
  # ring by ring rather than assuming one exists within a fixed hop.
  defp find_difficult_tile_near(world, start, pred, max_rings \\ 8) do
    Enum.reduce_while(1..max_rings, {[start], MapSet.new([start]), nil}, fn _,
                                                                             {frontier, seen,
                                                                              _found} ->
      next =
        frontier
        |> Enum.flat_map(&Fixtures.adjacent_tiles(world, &1))
        |> Enum.uniq()
        |> Enum.reject(&MapSet.member?(seen, &1))

      case Enum.find(next, pred) do
        nil -> {:cont, {next, MapSet.union(seen, MapSet.new(next)), nil}}
        found -> {:halt, found}
      end
    end)
  end
end
