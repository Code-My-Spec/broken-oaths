defmodule BrokenOathsSpex.Story953.Criterion2795Spex do
  @moduledoc """
  Story 953 — Unit movement, pathfinding and turn resolution
  Criterion 2795 — a tile claimed earlier the same round blocks a
  later mover: once the ascending-id winner's step lands in
  `Turn.Movement.run_rounds/8`'s own live `positions` map, the very
  next mover to attempt that same tile in the SAME round sees it as
  occupied and halts — its order `:interrupted`, path preserved, not
  lost — while the winner's own order (its path now empty) is dropped
  entirely, an arrival.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a mover's step arrives at an already-claimed hex the same round" do
    scenario "the later mover is interrupted with its path intact; the winner's order simply vanishes" do
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

      given_ "two units are already resting with zero movement, each one hex from a shared tile",
             context do
        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        shared =
          context.world
          |> Fixtures.adjacent_tiles(lord.tile_id)
          |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
          |> Enum.uniq()
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 == lord.tile_id))
          |> List.first() || raise "no candidate shared tile exists for this seed"

        land_neighbors = context.world |> Fixtures.adjacent_tiles(shared) |> Enum.filter(land?)

        [rest_a, rest_b | _] =
          if length(land_neighbors) >= 2,
            do: land_neighbors,
            else: raise("shared tile needs at least two land neighbors for this seed")

        second_spawn =
          context.world
          |> Fixtures.adjacent_tiles(lord.tile_id)
          |> Enum.filter(land?)
          |> List.last() || raise "no second spawn tile exists for this seed"

        {:ok, player} = Fixtures.join_world(context.world, context.user)
        second = Fixtures.spawn_unit(context.world, player.id, :warrior, second_spawn)

        burn_out_movement(context.play_live, context.world, lord)
        burn_out_movement(context.play_live, context.world, second)

        :ok = Fixtures.relocate_unit(context.world, lord.id, rest_a)
        :ok = Fixtures.relocate_unit(context.world, second.id, rest_b)

        [lord_now] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == lord.id, do: u

        [second_now] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == second.id, do: u

        assert lord_now.movement == 0
        assert second_now.movement == 0

        {:ok,
         context
         |> Map.put(:winner, lord_now)
         |> Map.put(:loser, second_now)
         |> Map.put(:shared, shared)}
      end

      when_ "both units are ordered onto the shared hex and the boundary resolves", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.winner.id,
          "to_tile" => context.shared
        })

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.loser.id,
          "to_tile" => context.shared
        })

        Fixtures.advance_turn(context.world)

        {:ok, context}
      end

      then_ "the later mover halts interrupted with its path intact; the winner's order is simply gone",
            context do
        units = Fixtures.player_units(context.world, context.user)
        [winner] = for u <- units, u.id == context.winner.id, do: u
        [loser] = for u <- units, u.id == context.loser.id, do: u

        assert winner.tile_id == context.shared
        assert winner.order == nil

        refute loser.tile_id == context.shared
        assert loser.tile_id == context.loser.tile_id
        assert loser.order.status == :interrupted
        assert loser.order.path == [context.shared]
        {:ok, context}
      end
    end
  end

  # Same burn-then-relocate idiom criterion 2792 already establishes:
  # spend `unit`'s movement fully via a real, immediate order to some
  # tile two rings out (direction irrelevant — the caller relocates it
  # to its real scenario tile afterward, free of movement/pathing).
  defp burn_out_movement(play_live, world, unit) do
    land? = fn t -> Fixtures.tile_class(world, t) == :land end

    burn_tile =
      world
      |> Fixtures.adjacent_tiles(unit.tile_id)
      |> Enum.flat_map(&Fixtures.adjacent_tiles(world, &1))
      |> Enum.uniq()
      |> Enum.filter(land?)
      |> Enum.reject(&(&1 == unit.tile_id))
      |> List.first() || raise "no tile two rings out from unit #{unit.id} for this seed"

    render_hook(play_live, "queue_move", %{"unit_id" => unit.id, "to_tile" => burn_tile})
    :ok
  end
end
