defmodule BrokenOathsSpex.Story891.Criterion7536Spex do
  @moduledoc """
  Story 891 — Unit Combat
  Criterion 7536 — a unit with 0 movement remaining cannot attack; the
  order is refused with a human-readable reason, and the very same
  attack succeeds once the next turn boundary recharges movement.

  Barbarian-fixture note: see `BrokenOathsSpex.Story891.Criterion7533Spex`'s
  moduledoc — the barbarian is a real, ownerless unit placed via
  `Fixtures.spawn_barbarian/2`, at the two-hexes-out tile directly (no
  march needed for an ownerless unit).

  My warrior's 0 movement is real, spent movement: it spends its one
  point of movement closing the final hex to the barbarian's doorstep —
  landing it adjacent with nothing left, exactly like any other move
  consumes movement.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "spent units cannot swing", fail_on_error_logs: false do
    scenario "an out-of-movement attacker is refused, then succeeds after recharge" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my warrior has 0 movement remaining and stands adjacent to a barbarian", context do
        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)
        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "warrior"})

        for _ <- 1..8, do: Fixtures.advance_turn(context.world)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        my_occupied = [city.tile_id, lord.tile_id, warrior.tile_id]

        depth1 =
          context.world
          |> Fixtures.adjacent_tiles(warrior.tile_id)
          |> Enum.filter(land?)

        depth2 =
          depth1
          |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
          |> Enum.uniq()
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in depth1))
          |> Enum.reject(&(&1 == warrior.tile_id))
          |> Enum.reject(&(&1 in my_occupied))

        # For each depth-2 candidate, the hex that bridges my warrior's
        # tile and it — the one hex my warrior itself will walk to
        # close the gap and spend its only movement point. `depth1`
        # alone (unlike `depth2`) was never filtered against
        # `my_occupied` — my own lord can easily be standing on one of
        # my warrior's OTHER neighbors, so the first depth-2 candidate
        # isn't guaranteed to have a free bridge; try each until one
        # does.
        {barbarian_target, bridge} =
          Enum.find_value(depth2, fn candidate ->
            case Enum.filter(depth1, &(candidate in Fixtures.adjacent_tiles(context.world, &1) and &1 not in my_occupied)) do
              [bridge | _] -> {candidate, bridge}
              [] -> nil
            end
          end)

        barbarian = Fixtures.spawn_barbarian(context.world, barbarian_target)

        # My warrior's own single hex of movement, spent closing the
        # gap — a real move, not a fixture trick, leaving it adjacent
        # with 0 movement remaining.
        render_hook(play_live, "queue_move", %{"unit_id" => warrior.id, "to_tile" => bridge})

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == warrior.id, do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:barbarian, barbarian)
         |> Map.put(:warrior_hp0, warrior.hp)
         |> Map.put(:barbarian_hp0, barbarian.hp)}
      end

      when_ "I order the attack", context do
        result = attempt_attack(context.play_live, context.warrior.id, context.barbarian.id)
        {:ok, Map.put(context, :attack_result, result)}
      end

      then_ "the attack is refused with a human-readable reason", context do
        assert context.attack_result == :ok,
               "the \"attack\" event crashed the LiveView (no handler implemented yet)"

        assert has_element?(context.play_live, "[data-test='combat-error']")

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        [barbarian] =
          for u <- Fixtures.visible_units(context.world, context.user),
              u.id == context.barbarian.id,
              do: u

        assert warrior.hp == context.warrior_hp0
        assert barbarian.hp == context.barbarian_hp0
        {:ok, context}
      end

      when_ "a turn boundary recharges movement and I order the same attack again", context do
        Fixtures.advance_turn(context.world)
        result = attempt_attack(context.play_live, context.warrior.id, context.barbarian.id)
        {:ok, Map.put(context, :attack_result, result)}
      end

      then_ "the attack succeeds", context do
        assert context.attack_result == :ok,
               "the \"attack\" event crashed the LiveView (no handler implemented yet)"

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        [barbarian] =
          for u <- Fixtures.visible_units(context.world, context.user),
              u.id == context.barbarian.id,
              do: u

        assert barbarian.hp < context.barbarian_hp0
        assert warrior.hp < context.warrior_hp0
        {:ok, context}
      end
    end
  end
  # The "attack" event has no handler yet, so calling it crashes the
  # LiveView (`FunctionClauseError` in `handle_event/3`) — expected
  # until `Game.Combat` lands. That crash reaches this (linked) test
  # process as a genuine process EXIT signal, not a value `render_hook`
  # itself raises — plain `try/rescue`/`catch :exit` around the call
  # does not intercept it. Trapping exits around the call converts it
  # into an ordinary `{:EXIT, pid, reason}` message instead, so the RED
  # here is a clean `then_` assertion failure instead of an uncaught
  # process EXIT taking down the whole test.
  defp attempt_attack(live_view, unit_id, target_unit_id) do
    original_trap = Process.flag(:trap_exit, true)

    result =
      try do
        render_hook(live_view, "attack", %{
          "unit_id" => to_string(unit_id),
          "target_unit_id" => to_string(target_unit_id)
        })

        :ok
      rescue
        _ -> :crashed
      catch
        :exit, _ -> :crashed
      end

    result =
      receive do
        {:EXIT, _pid, _reason} -> :crashed
      after
        100 -> result
      end

    Process.flag(:trap_exit, original_trap)
    result
  end
end
