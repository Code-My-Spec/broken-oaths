defmodule BrokenOathsSpex.Story891.Criterion7575Spex do
  @moduledoc """
  Story 891 — Unit Combat
  Criterion 7575 — a wounded unit fights at reduced effective strength,
  falling linearly from 100% at full HP to 50% near death, and all
  combat math consumes effective strength. A warrior at 20/100 HP
  (effective strength ≈ 10 × (0.5 + 0.5 × 0.2) = 6) should deal
  visibly less damage than an identical warrior at full HP (effective
  strength 10), against identical barbarian opponents.

  Barbarian-fixture note: see `BrokenOathsSpex.Story891.Criterion7533Spex`'s
  moduledoc — both barbarians here are real, ownerless units placed via
  `Fixtures.spawn_barbarian/2`; both are `:barbarian_warrior`s with
  identical stats, so they satisfy "an identical barbarian" for each
  side without further engineering.

  The wounded HP is set with `Fixtures.set_unit_hp/3` — the same
  documented, narrow exception story 881's healing criteria already
  rely on.

  KNOWN LIMITATION (statistical): the two damage bands (fresh ~18-31,
  wounded ~16-26, per the formula's own math) overlap, so a single
  random roll per side cannot conclusively separate them the way many
  trials could. This spec asserts the literal, most direct reading of
  "a visibly lower band" — a same-scenario relative comparison
  (wounded < fresh) — plus the individual bands as a secondary sanity
  check.

  Setup-hardening (not in the original contract): `ensure_lord_away/6`
  used to WALK the lord clear via `queue_move` + a turn-boundary wait
  loop when it landed too close. Now that story 892/893 seed real,
  roaming camps at first founding, that march (however short) is
  exposed to a real, correctly-aggressive barbarian actually finding
  and killing the lord before this scenario's own setup even finishes
  — nothing to do with what this criterion tests (wounded-vs-fresh
  damage bands). `Fixtures.relocate_unit/3` places it directly instead.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a dying warrior swings soft", fail_on_error_logs: false do
    scenario "a wounded warrior's attack lands softer than a fresh one's" do
      given_(:a_world)
      given_(:registered_player)

      given_ "one warrior at full HP and another at 20 of 100 HP, each attacking an identical barbarian",
             context do
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
        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "warrior"})

        for _ <- 1..16, do: Fixtures.advance_turn(context.world)

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        [fresh_warrior, wounded_warrior | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        # Both then_ bands assume no lord aura on either warrior —
        # spawn placement gives no guarantee the lord DOESN'T land
        # adjacent to one of them, which would silently add its +2
        # aura and push that side's roll out of its plain-strength
        # band. Move it out of range of both first if it does.
        lord =
          ensure_lord_away(
            context.world,
            play_live,
            context.user,
            lord,
            [fresh_warrior.tile_id, wounded_warrior.tile_id],
            city.tile_id
          )

        occupied = [city.tile_id, lord.tile_id, fresh_warrior.tile_id, wounded_warrior.tile_id]

        [fresh_target_tile | _] =
          context.world
          |> Fixtures.adjacent_tiles(fresh_warrior.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in occupied))

        fresh_barbarian = Fixtures.spawn_barbarian(context.world, fresh_target_tile)

        [wounded_target_tile | _] =
          context.world
          |> Fixtures.adjacent_tiles(wounded_warrior.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in occupied ++ [fresh_target_tile]))

        wounded_barbarian = Fixtures.spawn_barbarian(context.world, wounded_target_tile)

        Fixtures.set_unit_hp(context.world, wounded_warrior.id, 20)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:fresh_warrior, fresh_warrior)
         |> Map.put(:wounded_warrior, wounded_warrior)
         |> Map.put(:fresh_barbarian, fresh_barbarian)
         |> Map.put(:wounded_barbarian, wounded_barbarian)
         |> Map.put(:fresh_barbarian_hp0, fresh_barbarian.hp)
         |> Map.put(:wounded_barbarian_hp0, wounded_barbarian.hp)}
      end

      when_ "both combats resolve", context do
        fresh_result =
          attempt_attack(context.play_live, context.fresh_warrior.id, context.fresh_barbarian.id)

        wounded_result =
          attempt_attack(
            context.play_live,
            context.wounded_warrior.id,
            context.wounded_barbarian.id
          )

        {:ok,
         context
         |> Map.put(:fresh_attack_result, fresh_result)
         |> Map.put(:wounded_attack_result, wounded_result)}
      end

      then_ "the wounded warrior's damage comes from a visibly lower band than the fresh warrior's (roughly strength 6 versus strength 10)",
            context do
        assert context.fresh_attack_result == :ok,
               "the \"attack\" event crashed the LiveView (no handler implemented yet)"

        assert context.wounded_attack_result == :ok,
               "the \"attack\" event crashed the LiveView (no handler implemented yet)"

        [fresh_barbarian] =
          for u <- Fixtures.visible_units(context.world, context.user),
              u.id == context.fresh_barbarian.id,
              do: u

        [wounded_barbarian] =
          for u <- Fixtures.visible_units(context.world, context.user),
              u.id == context.wounded_barbarian.id,
              do: u

        fresh_damage = context.fresh_barbarian_hp0 - fresh_barbarian.hp
        wounded_damage = context.wounded_barbarian_hp0 - wounded_barbarian.hp

        assert wounded_damage < fresh_damage
        assert fresh_damage >= 18 and fresh_damage <= 31
        assert wounded_damage >= 16 and wounded_damage <= 26
        {:ok, context}
      end
    end
  end

  # If `lord` already stands adjacent to any tile in `avoid_tiles`,
  # walks it to a free land tile two hexes out from all of them and
  # returns the lord's up-to-date unit map; otherwise returns `lord`
  # unchanged. See this spec's moduledoc note on why an unplanned aura
  # would corrupt the plain-strength bands this criterion asserts.
  defp ensure_lord_away(world, _live_view, user, lord, avoid_tiles, city_tile) do
    danger =
      avoid_tiles
      |> Enum.flat_map(&[&1 | Fixtures.adjacent_tiles(world, &1)])
      |> MapSet.new()

    if MapSet.member?(danger, lord.tile_id) do
      land? = fn t -> Fixtures.tile_class(world, t) == :land end

      [safe_tile | _] =
        danger
        |> Enum.flat_map(&Fixtures.adjacent_tiles(world, &1))
        |> Enum.uniq()
        |> Enum.reject(&(MapSet.member?(danger, &1) or &1 in [city_tile, lord.tile_id]))
        |> Enum.filter(land?)

      :ok = Fixtures.relocate_unit(world, lord.id, safe_tile)
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
