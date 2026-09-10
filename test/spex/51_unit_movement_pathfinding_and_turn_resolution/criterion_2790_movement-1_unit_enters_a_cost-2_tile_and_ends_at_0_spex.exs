defmodule BrokenOathsSpex.Story953.Criterion2790Spex do
  @moduledoc """
  Story 953 — Unit movement, pathfinding and turn resolution
  Criterion 2790 — a movement-1 unit (a Warrior) entering a cost-2
  (difficult-terrain) tile still enters it, ending at 0 rather than
  being refused — `Turn.Movement.attempt_step/8`'s own
  `active_movers/1` gate is `movement_left > 0`, never
  `movement_left >= entry_cost`, and the spend itself is clamped at 0
  (`max(mover.movement_left - cost, 0)`), never negative.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a movement-1 unit enters a cost-2 tile" do
    scenario "the Warrior still enters the difficult tile, ending at exactly 0 movement" do
      given_(:a_world)
      given_(:registered_player)

      given_ "I have joined the world and opened the game board", context do
        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")
        {:ok, Map.put(context, :play_live, play_live)}
      end

      given_ "a Warrior stands adjacent to a difficult-terrain tile", context do
        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        difficult? = fn t ->
          terrain = Fixtures.tile_terrain(context.world, t)

          Fixtures.tile_class(context.world, t) == :land and
            (terrain.relief == :hills or terrain.feature in [:woods, :rainforest, :marsh])
        end

        difficult_tile =
          find_tile_near(context.world, lord.tile_id, difficult?) ||
            raise "expected a difficult-terrain tile to exist within 8 rings for this seed"

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        stand =
          context.world
          |> Fixtures.adjacent_tiles(difficult_tile)
          |> Enum.filter(land?)
          |> List.first() ||
            raise "no land tile adjacent to the difficult tile for this seed"

        {:ok, player} = Fixtures.join_world(context.world, context.user)
        warrior = Fixtures.spawn_unit(context.world, player.id, :warrior, stand)

        assert warrior.max_movement == 1

        {:ok, context |> Map.put(:warrior, warrior) |> Map.put(:difficult_tile, difficult_tile)}
      end

      when_ "the Warrior is ordered onto the difficult-terrain tile", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.warrior.id,
          "to_tile" => context.difficult_tile
        })

        {:ok, context}
      end

      then_ "the Warrior enters the tile, its movement spent and clamped at zero", context do
        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        assert warrior.tile_id == context.difficult_tile
        assert warrior.movement == 0
        {:ok, context}
      end
    end
  end

  # Breadth-first search outward from `start` for the nearest tile
  # matching `pred` — same helper criteria 2772/2773 already
  # established, duplicated here per this spec tree's own convention.
  defp find_tile_near(world, start, pred, max_rings \\ 8) do
    Enum.reduce_while(1..max_rings, {[start], MapSet.new([start])}, fn _, {frontier, seen} ->
      next =
        frontier
        |> Enum.flat_map(&Fixtures.adjacent_tiles(world, &1))
        |> Enum.uniq()
        |> Enum.reject(&MapSet.member?(seen, &1))

      case Enum.find(next, pred) do
        nil -> {:cont, {next, MapSet.union(seen, MapSet.new(next))}}
        found -> {:halt, found}
      end
    end)
    |> case do
      {_frontier, _seen} -> nil
      found -> found
    end
  end
end
