defmodule BrokenOathsSpex.Story952.Criterion2773Spex do
  @moduledoc """
  Story 952 — Scout — early recon unit
  Criterion 2773 — a Scout and a Warrior pay different movement costs
  for the very same woods tile: the Scout's `entry_cost/5` clause
  ignores difficult terrain (costs 1), while an ordinary land unit pays
  the standard difficult-terrain cost (2). The Warrior's own max
  movement is 1, so per story 953's own locked model ("Movement-1 unit
  enters a cost-2 tile and ends at 0") it still enters the SAME tile,
  ending at 0 rather than being refused — that contrast (Scout ends at
  2 remaining, Warrior ends at 0) is what demonstrates the differing
  cost on the identical tile.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Scout and Warrior pay different costs for the same woods tile" do
    scenario "the Scout spends 1 movement where the Warrior's own move is consumed by the same tile" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "a Scout and a Warrior have both been built", context do
        render_hook(context.play_live, "queue_production", %{
          "city_id" => context.city.id,
          "item" => "scout"
        })

        render_hook(context.play_live, "queue_production", %{
          "city_id" => context.city.id,
          "item" => "warrior"
        })

        Enum.reduce_while(1..20, :ok, fn _, :ok ->
          scout_ready? =
            Enum.any?(Fixtures.player_units(context.world, context.user), &(&1.type == :scout))

          warrior_ready? =
            Enum.any?(
              Fixtures.player_units(context.world, context.user),
              &(&1.type == :warrior)
            )

          if scout_ready? and warrior_ready? do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [scout] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :scout, do: u

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        {:ok, context |> Map.put(:scout, scout) |> Map.put(:warrior, warrior)}
      end

      given_ "a difficult-terrain (woods/rainforest/marsh) tile adjacent to both units is known",
             context do
        # A difficult-terrain tile is not guaranteed to fall within the
        # tiny intersection of both units' own immediate 1-hex rings —
        # terrain placement is organic world-gen, not something spawn
        # position controls. Search outward (same ring-widening BFS
        # criterion 2772 already established) for the nearest difficult
        # tile from the Scout's own position, then RELOCATE both units
        # to land tiles adjacent to whatever is found — a real in-game
        # action (`Fixtures.relocate_unit/3`), same sanctioned bridge
        # story 893's specs already use — rather than hoping spawn
        # placement happened to put both units next to the same one.
        difficult? = fn t ->
          terrain = Fixtures.tile_terrain(context.world, t)
          Fixtures.tile_class(context.world, t) == :land and
            terrain.feature in [:woods, :rainforest, :marsh]
        end

        woods_tile =
          find_difficult_tile_near(context.world, context.scout.tile_id, difficult?)

        assert woods_tile, "expected a difficult-terrain tile to exist within 8 rings"

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        candidates =
          context.world
          |> Fixtures.adjacent_tiles(woods_tile)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 == woods_tile))

        # Don't blindly take the first two candidates — one may already
        # be occupied (the city, the lord, or anything else standing on
        # a neighbor of the found tile), and `relocate_unit/3` errors
        # rather than silently succeeding on an occupied tile. Try each
        # candidate in turn for the Scout, then exclude whichever tile
        # it landed on before trying candidates for the Warrior, so the
        # two units never end up targeting the same stand tile.
        scout_stand = relocate_to_first_free(context.world, context.scout.id, candidates)

        _warrior_stand =
          relocate_to_first_free(
            context.world,
            context.warrior.id,
            Enum.reject(candidates, &(&1 == scout_stand))
          )

        {:ok, context |> Map.put(:woods_tile, woods_tile) |> Map.put(:scout_stand, scout_stand)}
      end

      when_ "the Scout is ordered onto the woods tile", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.scout.id,
          "to_tile" => context.woods_tile
        })

        {:ok, context}
      end

      then_ "the Scout arrives having spent only 1 movement point", context do
        [scout] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == context.scout.id,
            do: u

        assert scout.tile_id == context.woods_tile
        assert scout.movement == context.scout.movement - 1
        {:ok, Map.put(context, :scout_final_movement, scout.movement)}
      end

      when_ "the Scout is relocated clear and the Warrior is ordered onto the SAME woods tile",
            context do
        # `context.scout.tile_id` is stale — bound once in the very
        # first given_ block, before either relocation this spec
        # performs. `scout_stand` was free when the Scout first landed
        # there, but nothing guarantees it's STILL free now (whatever
        # else may have moved since) — recompute a fresh set of free
        # land tiles adjacent to the woods tile right now, excluding
        # wherever the Warrior currently stands, rather than trusting a
        # stale single tile. Any of them clears the Scout off the woods
        # tile equally well; which one doesn't matter to this criterion.
        [warrior_now] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        fresh_candidates =
          context.world
          |> Fixtures.adjacent_tiles(context.woods_tile)
          |> Enum.filter(&(Fixtures.tile_class(context.world, &1) == :land))
          |> Enum.reject(&(&1 in [context.woods_tile, warrior_now.tile_id]))

        _scout_stand_now = relocate_to_first_free(context.world, context.scout.id, fresh_candidates)

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.warrior.id,
          "to_tile" => context.woods_tile
        })

        {:ok, context}
      end

      then_ "the Warrior also arrives, but its own movement is fully exhausted", context do
        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        assert warrior.tile_id == context.woods_tile
        assert warrior.movement == 0

        assert context.scout_final_movement > warrior.movement,
               "expected the Scout to have movement left where the Warrior's own was fully spent by the same tile"

        {:ok, context}
      end
    end
  end

  # Breadth-first search outward from `start` for the nearest tile
  # matching `pred` — a difficult-terrain tile may not sit directly
  # adjacent to either unit's own spawn point, so this widens the
  # search ring by ring rather than assuming one exists within a fixed
  # hop. Same helper criterion 2772 already established.
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

  # Try each candidate tile in order, relocating `unit_id` onto the
  # first one that isn't already occupied by something else. Returns
  # the tile it landed on. Raises if every candidate is occupied — a
  # clear setup failure rather than a silent bad state.
  defp relocate_to_first_free(world, unit_id, candidates) do
    Enum.find_value(candidates, fn tile ->
      case Fixtures.relocate_unit(world, unit_id, tile) do
        :ok -> tile
        {:error, _reason} -> nil
      end
    end) ||
      raise "no free candidate tile for unit #{unit_id} among #{inspect(candidates)}"
  end
end
