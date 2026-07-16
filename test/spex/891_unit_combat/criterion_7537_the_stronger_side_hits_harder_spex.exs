defmodule BrokenOathsSpex.Story891.Criterion7537Spex do
  @moduledoc """
  Story 891 — Unit Combat
  Criterion 7537 — combat damage follows the Civ VI curve: 30 base
  damage at equal strength, scaled ~4% per point of strength
  difference, with a ±25% random roll. A Warrior (strength 10)
  attacking a barbarian Warrior (strength 15) should land the
  barbarian in the weaker damage band (~18 to 31) and take the
  stronger band (~27 to 46) in return.

  Barbarian-fixture note: see `BrokenOathsSpex.Story891.Criterion7533Spex`'s
  moduledoc — the barbarian is a real, ownerless `:barbarian_warrior`
  unit placed via `Fixtures.spawn_barbarian/2`, whose strength (15) is
  `Game.Combat.base_strength(:barbarian_warrior)` — the same value
  these damage bands were derived from.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the stronger side hits harder", fail_on_error_logs: false do
    scenario "a weaker attacker still lands a hit, but takes the heavier one back" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my warrior (strength 10) attacks a barbarian warrior (strength 15)", context do
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

        # This criterion asserts the plain, no-aura strength-10 band —
        # spawn placement gives no guarantee the lord DOESN'T land
        # adjacent to the warrior, which would silently add its +2
        # aura and push the roll into (or past) the strength-12 band.
        # Move it out of range first if it does.
        lord = ensure_lord_away(context.world, play_live, context.user, lord, warrior.tile_id, city.tile_id)

        my_occupied = [city.tile_id, lord.tile_id, warrior.tile_id]

        [target | _] =
          context.world
          |> Fixtures.adjacent_tiles(warrior.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in my_occupied))

        barbarian = Fixtures.spawn_barbarian(context.world, target)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:barbarian, barbarian)
         |> Map.put(:warrior_hp0, warrior.hp)
         |> Map.put(:barbarian_hp0, barbarian.hp)}
      end

      when_ "the combat resolves", context do
        result = attempt_attack(context.play_live, context.warrior.id, context.barbarian.id)
        {:ok, Map.put(context, :attack_result, result)}
      end

      then_ "the barbarian loses damage in the weaker band (roughly 18 to 31) and my warrior loses damage in the stronger band (roughly 27 to 46)",
            context do
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

        barbarian_damage = context.barbarian_hp0 - barbarian.hp
        warrior_damage = context.warrior_hp0 - warrior.hp

        assert barbarian_damage >= 18 and barbarian_damage <= 31
        assert warrior_damage >= 27 and warrior_damage <= 46
        {:ok, context}
      end
    end
  end
  # If `lord` already stands adjacent to `avoid_tile`, walks it to a
  # free land tile two hexes out and returns the lord's up-to-date
  # unit map; otherwise returns `lord` unchanged. See this spec's
  # moduledoc note on why an unplanned aura would corrupt the
  # no-aura band this criterion asserts.
  defp ensure_lord_away(world, live_view, user, lord, avoid_tile, city_tile) do
    ring1 = world |> Fixtures.adjacent_tiles(avoid_tile) |> MapSet.new()

    if MapSet.member?(ring1, lord.tile_id) do
      land? = fn t -> Fixtures.tile_class(world, t) == :land end

      [safe_tile | _] =
        ring1
        |> Enum.flat_map(&Fixtures.adjacent_tiles(world, &1))
        |> Enum.uniq()
        |> Enum.reject(&(MapSet.member?(ring1, &1) or &1 in [avoid_tile, city_tile, lord.tile_id]))
        |> Enum.filter(land?)

      render_hook(live_view, "queue_move", %{"unit_id" => lord.id, "to_tile" => safe_tile})

      Enum.reduce_while(1..10, :ok, fn _, :ok ->
        [l] = for u <- Fixtures.player_units(world, user), u.id == lord.id, do: u

        if l.tile_id == safe_tile do
          {:halt, :ok}
        else
          Fixtures.advance_turn(world)
          {:cont, :ok}
        end
      end)

      [l] = for u <- Fixtures.player_units(world, user), u.id == lord.id, do: u
      l
    else
      lord
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
