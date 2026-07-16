defmodule BrokenOathsSpex.Story891.Criterion7539Spex do
  @moduledoc """
  Story 891 — Unit Combat
  Criterion 7539 — a unit reduced to 0 HP is destroyed and removed
  from the world: it disappears from the board and its owner's unit
  list, and its tile frees up for movement.

  Barbarian-fixture note: see `BrokenOathsSpex.Story891.Criterion7533Spex`'s
  moduledoc — the barbarian is a real, ownerless unit placed via
  `Fixtures.spawn_barbarian/2`.

  The lethal setup uses `Fixtures.set_unit_hp/3` (same documented,
  narrow exception as story 881's healing criteria) to guarantee the
  hit is fatal regardless of the random damage roll.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "zero HP means gone", fail_on_error_logs: false do
    scenario "a destroyed unit leaves the board and frees its tile" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a combat where one unit's HP falls to 0", context do
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

        [target | _] =
          context.world
          |> Fixtures.adjacent_tiles(warrior.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in my_occupied))

        barbarian = Fixtures.spawn_barbarian(context.world, target)

        # Weak enough that any real hit is lethal, regardless of the
        # random damage roll.
        Fixtures.set_unit_hp(context.world, barbarian.id, 1)

        [barbarian] =
          for u <- Fixtures.visible_units(context.world, context.user),
              u.id == barbarian.id,
              do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:barbarian, barbarian)
         |> Map.put(:barbarian_tile, barbarian.tile_id)}
      end

      when_ "the combat resolves", context do
        result = attempt_attack(context.play_live, context.warrior.id, context.barbarian.id)
        {:ok, Map.put(context, :attack_result, result)}
      end

      then_ "that unit disappears from the board and from its owner's unit list, and its tile becomes free for movement",
            context do
        assert context.attack_result == :ok,
               "the \"attack\" event crashed the LiveView (no handler implemented yet)"

        surviving_barbarian =
          for u <- Fixtures.visible_units(context.world, context.user),
              u.id == context.barbarian.id,
              do: u

        assert surviving_barbarian == []

        # The tile frees up: a turn boundary recharges my warrior's
        # spent-on-attack movement, then it can be ordered onto the
        # vacated tile without an "occupied" refusal.
        Fixtures.advance_turn(context.world)

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => context.warrior.id,
          "to_tile" => context.barbarian_tile
        })

        refute has_element?(context.play_live, "[data-test='order-error']")

        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [w] =
            for u <- Fixtures.player_units(context.world, context.user),
                u.id == context.warrior.id,
                do: u

          if w.tile_id == context.barbarian_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        assert warrior.tile_id == context.barbarian_tile
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
