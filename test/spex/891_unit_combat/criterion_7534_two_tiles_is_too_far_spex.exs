defmodule BrokenOathsSpex.Story891.Criterion7534Spex do
  @moduledoc """
  Story 891 — Unit Combat
  Criterion 7534 — a target two tiles away is out of attack range: the
  order is refused with a human-readable reason and neither combatant
  loses HP.

  Barbarian-fixture note: see `BrokenOathsSpex.Story891.Criterion7533Spex`'s
  moduledoc — "the barbarian" here is mechanically a second real
  player's warrior, produced through the ordinary `GameLive.Play`
  surface. This is a documented, temporary stand-in for story 892
  (`Game.Camps`), which doesn't exist yet.

  Setup-hardening (not in the original contract): the stand-in warrior
  used to be WALKED into place via `queue_move` + a turn-boundary wait
  loop. Now that story 892/893 seed real, roaming camps the moment
  EITHER player founds their first city, that multi-turn march (however
  short — two hexes) is exposed to a real, correctly-aggressive
  barbarian actually finding and killing it before this scenario's own
  setup even finishes, which has nothing to do with what this criterion
  tests (range refusal). `Fixtures.relocate_unit/3` places it directly
  — same instant, no-march status `Fixtures.spawn_barbarian/2` already
  has for the barbarian identity itself in criterion 7533.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "two tiles is too far", fail_on_error_logs: false do
    scenario "an out-of-range attack is refused and nobody takes damage" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my warrior stands two tiles from a barbarian warrior", context do
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

        [target | _] = depth2

        :ok = Fixtures.relocate_unit(context.world, barbarian.id, target)

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

      then_ "the attack is refused with a human-readable reason and neither unit loses HP",
            context do
        assert context.attack_result == :ok,
               "the \"attack\" event crashed the LiveView (no handler implemented yet)"

        assert has_element?(context.play_live, "[data-test='combat-error']")

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        [barbarian] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.barbarian.id,
              do: u

        assert warrior.hp == context.warrior_hp0
        assert barbarian.hp == context.barbarian_hp0
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
