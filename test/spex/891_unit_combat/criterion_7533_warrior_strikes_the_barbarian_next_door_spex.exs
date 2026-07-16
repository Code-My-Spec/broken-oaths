defmodule BrokenOathsSpex.Story891.Criterion7533Spex do
  @moduledoc """
  Story 891 — Unit Combat
  Criterion 7533 — a military unit or lord can attack a hostile unit
  standing on an adjacent tile; both combatants lose HP.

  Barbarian-fixture note: story 892 (`Game.Camps`) — the system that
  spawns real barbarian units — is not implemented yet, and there is
  no faction/hostility concept anywhere in the schema
  (`Game.Unit.player_id` is a required FK to a real `Game.Player`,
  same as any player-owned unit; no nullable-owner or flag exists).
  The board's canonical state also lives entirely inside
  `WorldServer`'s in-memory process, so a unit only becomes real,
  attackable board state by being produced/moved through the real
  game surface — a raw schema insert would not even be visible to it.

  Until Camps lands and supplies real barbarian identity, "the
  barbarian" here is mechanically just a second real player's warrior,
  produced and walked into place through the ordinary
  `GameLive.Play` surface (found city, queue Warrior production, walk
  it adjacent) — narrated as a barbarian for readability, the same
  documented-workaround status as `Fixtures.set_unit_hp/3`. This is
  NOT the same thing as criterion 7542 ("no friendly fire"), which
  tests genuine cross-player hostility and needs no stand-in at all.
  Revisit — swap this for real Camps-spawned barbarians — once story
  892 lands.

  No `"attack"` clause exists in `GameLive.Play.handle_event/3` yet,
  so driving it crashes the LiveView (`FunctionClauseError`) until
  `Game.Combat` lands. `attempt_attack/3` catches that crash so the
  RED here is a clean, informative `then_` assertion failure instead
  of an uncaught process EXIT taking down the test; `fail_on_error_logs:
  false` disables the separate all-error-logs-fail-the-spex check
  (see `SexySpex.ErrorCapture`) for the same expected-crash reason —
  the GenServer's own crash log is a known, accepted consequence of
  driving a not-yet-implemented event, not a bug in this spec.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "warrior strikes the barbarian next door", fail_on_error_logs: false do
    scenario "an adjacent barbarian trades blows with my warrior" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my warrior stands adjacent to a barbarian warrior", context do
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

        [barbarian] =
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
          "unit_id" => barbarian.id,
          "to_tile" => target
        })

        Enum.reduce_while(1..40, :ok, fn _, :ok ->
          [b] =
            for u <- Fixtures.player_units(context.world, context.other_user),
                u.id == barbarian.id,
                do: u

          if b.tile_id == target do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [barbarian] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == barbarian.id,
              do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:barbarian, barbarian)
         |> Map.put(:warrior_hp0, warrior.hp)
         |> Map.put(:barbarian_hp0, barbarian.hp)}
      end

      when_ "I order my warrior to attack the barbarian", context do
        result = attempt_attack(context.play_live, context.warrior.id, context.barbarian.id)
        {:ok, Map.put(context, :attack_result, result)}
      end

      then_ "both units lose HP", context do
        assert context.attack_result == :ok,
               "the \"attack\" event crashed the LiveView (no handler implemented yet)"

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        [barbarian] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.barbarian.id,
              do: u

        assert warrior.hp < context.warrior_hp0
        assert barbarian.hp < context.barbarian_hp0
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
