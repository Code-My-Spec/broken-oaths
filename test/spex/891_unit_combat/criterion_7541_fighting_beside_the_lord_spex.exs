defmodule BrokenOathsSpex.Story891.Criterion7541Spex do
  @moduledoc """
  Story 891 — Unit Combat
  Criterion 7541 — an attacker standing adjacent to its own lord fights
  with +2 strength: my warrior (strength 10, +2 lord aura = effective
  12) attacking a barbarian warrior (strength 15) should deal damage
  from the strength-12 band, not the plain strength-10 band.

  Barbarian-fixture note: see `BrokenOathsSpex.Story891.Criterion7533Spex`'s
  moduledoc — the barbarian is a real, ownerless unit placed via
  `Fixtures.spawn_barbarian/2`.

  KNOWN LIMITATION (statistical): the strength-10 band (~18 to 31, per
  criterion 7537) and the strength-12 band computed here (~20 to 33)
  overlap — a single random combat roll cannot conclusively rule out
  "got lucky within the strength-10 band" the way a wider gap would.
  This spec asserts membership in the strength-12 band, the most
  literal single-scenario encoding of "comes from the strength-12
  band" available without a deterministic-roll test hook; a future
  reviewer may want to strengthen it with repeated trials once combat
  exists for real.

  My lord is walked next to my warrior's landed position — Lord spawn
  adjacency to the settler-turned-city gives no adjacency guarantee to
  wherever the warrior itself lands, so this is engineered with a real
  move (`queue_move`), not a fixture trick.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "fighting beside the lord", fail_on_error_logs: false do
    scenario "the lord's aura raises the attacker's effective strength" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my warrior stands adjacent to both my lord and a barbarian", context do
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

        [barbarian_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(warrior.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in my_occupied))

        barbarian = Fixtures.spawn_barbarian(context.world, barbarian_target)

        # Bring the lord to a free tile adjacent to my warrior — not
        # already the barbarian's tile or the warrior's own tile.
        [lord_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(warrior.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in [city.tile_id, warrior.tile_id, barbarian.tile_id, lord.tile_id]))

        render_hook(play_live, "queue_move", %{"unit_id" => lord.id, "to_tile" => lord_target})

        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [l] =
            for u <- Fixtures.player_units(context.world, context.user),
                u.id == lord.id,
                do: u

          if l.tile_id == lord_target do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:barbarian, barbarian)
         |> Map.put(:warrior_hp0, warrior.hp)
         |> Map.put(:barbarian_hp0, barbarian.hp)}
      end

      when_ "my warrior attacks the barbarian", context do
        result = attempt_attack(context.play_live, context.warrior.id, context.barbarian.id)
        {:ok, Map.put(context, :attack_result, result)}
      end

      then_ "the damage dealt comes from the strength-12 band, not the strength-10 band",
            context do
        assert context.attack_result == :ok,
               "the \"attack\" event crashed the LiveView (no handler implemented yet)"

        [barbarian] =
          for u <- Fixtures.visible_units(context.world, context.user),
              u.id == context.barbarian.id,
              do: u

        dealt = context.barbarian_hp0 - barbarian.hp

        # 30 * e^(0.04 * (12 - 15)) ± 25% ≈ [19.96, 33.26]
        assert dealt >= 20 and dealt <= 33
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
