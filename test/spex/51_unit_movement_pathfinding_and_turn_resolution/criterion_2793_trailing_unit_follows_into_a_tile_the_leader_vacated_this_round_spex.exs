defmodule BrokenOathsSpex.Story953.Criterion2793Spex do
  @moduledoc """
  Story 953 — Unit movement, pathfinding and turn resolution
  Criterion 2793 — a trailing unit follows into a tile the leader
  vacated this very round: `Turn.Movement.run_rounds/8` threads a
  LIVE `positions` map through its own `Enum.reduce` (ascending unit
  id), so once the lower-id leader's step frees its old tile within a
  round, the higher-id trailing mover's OWN step later in that SAME
  round already sees it as free — a real round-by-round resolution,
  not a frozen pre-round snapshot.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a leader steps off a tile and a trailing unit steps into it the same round" do
    scenario "the trailing unit occupies the tile the leader vacated this same round" do
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

      given_ "a leader and a trailing unit rest with zero movement, in line: leader ahead, trailing behind",
             context do
        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        a_neighbors = context.world |> Fixtures.adjacent_tiles(lord.tile_id) |> Enum.filter(land?)

        [b, z | _] =
          if length(a_neighbors) >= 2,
            do: a_neighbors,
            else: raise("tile A needs at least two land neighbors for this seed")

        second_spawn =
          context.world
          |> Fixtures.adjacent_tiles(lord.tile_id)
          |> Enum.filter(land?)
          |> List.last() || raise "no trailing spawn tile exists for this seed"

        {:ok, player} = Fixtures.join_world(context.world, context.user)
        trailing = Fixtures.spawn_unit(context.world, player.id, :settler, second_spawn)

        assert lord.id < trailing.id,
               "expected the freshly spawned trailing unit to get a higher id than the lord"

        a = lord.tile_id

        burn_out_movement(context.play_live, context.world, lord)
        burn_out_movement(context.play_live, context.world, trailing)

        :ok = Fixtures.relocate_unit(context.world, lord.id, a)
        :ok = Fixtures.relocate_unit(context.world, trailing.id, z)

        [leader_now] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == lord.id, do: u

        [trailing_now] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == trailing.id,
              do: u

        assert leader_now.movement == 0
        assert trailing_now.movement == 0

        {:ok,
         context
         |> Map.put(:leader, leader_now)
         |> Map.put(:trailing, trailing_now)
         |> Map.put(:a, a)
         |> Map.put(:b, b)}
      end

      when_ "both are ordered to advance along the line and the boundary resolves", context do
        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.leader.id,
          "to_tile" => context.b
        })

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.trailing.id,
          "to_tile" => context.a
        })

        Fixtures.advance_turn(context.world)

        {:ok, context}
      end

      then_ "the trailing unit occupies the tile the leader vacated this same round", context do
        units = Fixtures.player_units(context.world, context.user)
        [leader] = for u <- units, u.id == context.leader.id, do: u
        [trailing] = for u <- units, u.id == context.trailing.id, do: u

        assert leader.tile_id == context.b
        assert trailing.tile_id == context.a
        {:ok, context}
      end
    end
  end

  # Same burn-then-relocate idiom criteria 2792/2795 already establish:
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
