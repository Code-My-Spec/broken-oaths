defmodule BrokenOathsSpex.Story953.Criterion2792Spex do
  @moduledoc """
  Story 953 — Unit movement, pathfinding and turn resolution
  Criterion 2792 — one step per round, movers ordered by ascending
  unit id: when two movers both become active in the same
  `resolve_orders/1` round and contest the same hex,
  `Turn.Movement.active_movers/1`'s own `Enum.sort/1` always resolves
  the LOWER unit id first — a property of unit id, not of which move
  was actually issued/queued first in real time.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "two units contest the same hex in the same round" do
    scenario "the lower unit id always claims the hex, even when the higher id is queued first" do
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

        # A DIFFERENT starting tile than the lord's own — sharing one
        # would make both units' own "two rings out" burn target below
        # resolve identically, so the second unit's own burn walk
        # would immediately collide with wherever the lord's burn just
        # sent it.
        second_spawn =
          context.world
          |> Fixtures.adjacent_tiles(lord.tile_id)
          |> Enum.filter(land?)
          |> List.last() || raise "no second spawn tile exists for this seed"

        {:ok, player} = Fixtures.join_world(context.world, context.user)
        # A Warrior, not a Settler: same combat class as the Lord, so
        # the field-stacking allowance (opposite classes may share a
        # field tile) never masks the contest this criterion is about
        # — two same-class movers can never both end up on `shared`.
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
         |> Map.put(:lord, lord_now)
         |> Map.put(:second, second_now)
         |> Map.put(:shared, shared)}
      end

      when_ "the higher-id unit is ordered onto the shared hex first, then the lower-id unit, and the boundary resolves",
            context do
        {higher, lower} =
          if context.lord.id > context.second.id,
            do: {context.lord, context.second},
            else: {context.second, context.lord}

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => higher.id,
          "to_tile" => context.shared
        })

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => lower.id,
          "to_tile" => context.shared
        })

        Fixtures.advance_turn(context.world)

        {:ok, context |> Map.put(:higher, higher) |> Map.put(:lower, lower)}
      end

      then_ "the lower unit id holds the hex even though the higher id was issued first", context do
        units = Fixtures.player_units(context.world, context.user)
        [lower] = for u <- units, u.id == context.lower.id, do: u
        [higher] = for u <- units, u.id == context.higher.id, do: u

        assert lower.tile_id == context.shared
        refute higher.tile_id == context.shared
        assert higher.tile_id == context.higher.tile_id
        {:ok, context}
      end
    end
  end

  # Burns `unit`'s movement fully via a real, immediate two-hex order
  # to some tile two rings out (direction doesn't matter — the caller
  # relocates it to its real starting tile for the scenario afterward,
  # `Fixtures.relocate_unit/3` bypassing movement/pathing entirely, the
  # same "burn then relocate" idiom other criteria in this spec tree
  # use to construct a unit resting at 0 movement at a chosen tile).
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
