defmodule BrokenOathsSpex.Story891.Criterion7542Spex do
  @moduledoc """
  Story 891 — Unit Combat
  Criterion 7542 — attacks against another player's units are refused
  in the Stone Age; only barbarians are attackable.

  Unlike this story's other criteria, this scenario needs no
  barbarian stand-in at all: "another player's warrior" is exactly
  what a second real player's warrior already is — no narrative
  substitution, no documented workaround. This is deliberately the
  one criterion in this story that is NOT affected by story 892
  (`Game.Camps`) being unimplemented.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "no friendly fire in the Stone Age", fail_on_error_logs: false do
    scenario "attacking another player's unit is refused" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my warrior stands adjacent to another player's warrior", context do
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

        {:ok, other_join_live, _html} = live(context.other_conn, "/play")

        other_join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, other_play_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        [other_settler | _] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :settler,
              do: u

        render_hook(other_play_live, "found_city", %{"unit_id" => other_settler.id})
        [other_city] = Fixtures.player_cities(context.world, context.other_user)

        render_hook(other_play_live, "queue_production", %{
          "city_id" => other_city.id,
          "item" => "warrior"
        })

        for _ <- 1..8, do: Fixtures.advance_turn(context.world)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        [other_warrior] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :warrior,
              do: u

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        my_occupied = [city.tile_id, lord.tile_id, warrior.tile_id]

        [target | _] =
          context.world
          |> Fixtures.adjacent_tiles(warrior.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in my_occupied))

        render_hook(other_play_live, "queue_move", %{
          "unit_id" => other_warrior.id,
          "to_tile" => target
        })

        Enum.reduce_while(1..40, :ok, fn _, :ok ->
          [o] =
            for u <- Fixtures.player_units(context.world, context.other_user),
                u.id == other_warrior.id,
                do: u

          if o.tile_id == target do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [other_warrior] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == other_warrior.id,
              do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:other_warrior, other_warrior)
         |> Map.put(:warrior_hp0, warrior.hp)
         |> Map.put(:other_warrior_hp0, other_warrior.hp)}
      end

      when_ "I order an attack on that unit", context do
        result = attempt_attack(context.play_live, context.warrior.id, context.other_warrior.id)
        {:ok, Map.put(context, :attack_result, result)}
      end

      then_ "the attack is refused with a reason explaining Stone Age players cannot fight each other",
            context do
        assert context.attack_result == :ok,
               "the \"attack\" event crashed the LiveView (no handler implemented yet)"

        assert has_element?(context.play_live, "[data-test='combat-error']")

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        [other_warrior] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.other_warrior.id,
              do: u

        assert warrior.hp == context.warrior_hp0
        assert other_warrior.hp == context.other_warrior_hp0
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
