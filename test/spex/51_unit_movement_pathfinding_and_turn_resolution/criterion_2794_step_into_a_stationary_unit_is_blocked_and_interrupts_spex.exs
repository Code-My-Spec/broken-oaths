defmodule BrokenOathsSpex.Story953.Criterion2794Spex do
  @moduledoc """
  Story 953 — Unit movement, pathfinding and turn resolution
  Criterion 2794 — stepping into a tile a stationary unit already
  holds is blocked: `Turn.Movement.blocked?/6` refuses the step (no
  field-stacking allowance between two same-class combat units), and
  the mover's order becomes `:interrupted` in place rather than being
  lost — its preserved path (including the blocked step) auto-resumes
  next turn.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a unit steps toward a tile a stationary unit already holds" do
    scenario "the mover halts, blocked, its order interrupted rather than lost" do
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

      given_ "a Warrior rests one hex short of its own two-hex order, movement fully spent", context do
        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        ring1 = context.world |> Fixtures.adjacent_tiles(lord.tile_id) |> Enum.filter(land?)

        candidates =
          for m <- ring1,
              x <- Fixtures.adjacent_tiles(context.world, m),
              land?.(x),
              x != lord.tile_id,
              x not in ring1,
              do: {m, x}

        {resting_tile, x} =
          List.first(candidates) ||
            raise "no two-hex construction exists near the lord for this seed"

        {:ok, player} = Fixtures.join_world(context.world, context.user)
        warrior = Fixtures.spawn_unit(context.world, player.id, :warrior, lord.tile_id)
        assert warrior.max_movement == 1

        render_hook(context.play_live, "queue_move", %{"unit_id" => warrior.id, "to_tile" => x})

        [warrior_now] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == warrior.id,
            do: u

        assert warrior_now.tile_id == resting_tile
        assert warrior_now.movement == 0
        assert warrior_now.order.status == :pending
        assert warrior_now.order.path == [x]

        blocker = Fixtures.spawn_unit(context.world, player.id, :warrior, x)

        {:ok,
         context
         |> Map.put(:warrior, warrior_now)
         |> Map.put(:resting_tile, resting_tile)
         |> Map.put(:blocker, blocker)
         |> Map.put(:x, x)}
      end

      when_ "the boundary recharges movement and the Warrior tries its next step", context do
        Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "the Warrior halts, blocked, its order interrupted rather than lost", context do
        units = Fixtures.player_units(context.world, context.user)
        [warrior] = for u <- units, u.id == context.warrior.id, do: u
        [blocker] = for u <- units, u.id == context.blocker.id, do: u

        assert warrior.tile_id == context.resting_tile
        assert blocker.tile_id == context.x
        assert warrior.order.status == :interrupted
        assert warrior.order.path == [context.x]
        {:ok, context}
      end
    end
  end
end
