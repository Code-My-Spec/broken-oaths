defmodule BrokenOathsSpex.Story952.Criterion2767Spex do
  @moduledoc """
  Story 952 — Scout — early recon unit
  Criterion 2767 — a Scout's 3 movement points let it cross three
  open (non-difficult) tiles in a single order, all within the SAME
  turn — movement is immediate (story 875's own locked model: an order
  spends available movement the instant it lands, the turn boundary
  only recharges), so no `advance_turn` is needed between queueing the
  move and observing the Scout three hexes out with 0 movement left.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Scout crosses three open tiles in one turn" do
    scenario "a queued three-hex path over open ground completes immediately" do
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

      given_ "a destination exactly three open (non-difficult) hexes away is known", context do
        open? = fn tile ->
          Fixtures.tile_class(context.world, tile) == :land and
            Fixtures.tile_terrain(context.world, tile).relief != :hills and
            Fixtures.tile_terrain(context.world, tile).feature == nil
        end

        occupied =
          MapSet.new(for u <- Fixtures.player_units(context.world, context.user), do: u.tile_id)

        grow = fn frontier, seen ->
          next =
            frontier
            |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
            |> Enum.uniq()
            |> Enum.reject(&(MapSet.member?(seen, &1) or MapSet.member?(occupied, &1)))
            |> Enum.filter(open?)

          {next, MapSet.union(seen, MapSet.new(next))}
        end

        seen = MapSet.new([context.scout.tile_id])
        {l1, seen} = grow.([context.scout.tile_id], seen)
        {l2, seen} = grow.(l1, seen)
        {l3, _seen} = grow.(l2, seen)

        [target | _] = l3
        {:ok, Map.put(context, :target, target)}
      end

      when_ "the player queues the three-hex move", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.scout.id,
          "to_tile" => context.target
        })

        {:ok, context}
      end

      then_ "the Scout arrives at the destination immediately, with movement fully spent",
            context do
        [scout] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == context.scout.id,
            do: u

        assert scout.tile_id == context.target
        assert scout.movement == 0
        {:ok, context}
      end
    end
  end
end
