defmodule BrokenOathsSpex.Story894.Criterion7561Spex do
  @moduledoc """
  Story 894 — Camp Assault
  Criterion 7561 — barbarian warriors a camp already spawned are not
  deleted when the camp is destroyed: they remain on the board as live,
  hostile units and are still legal attack targets ("barbarians only
  in the Stone Age" — `combat.spec.md`'s own target-legality rule).

  Surface note: see `BrokenOathsSpex.Story894.Criterion7558Spex`'s
  moduledoc for the inferred `"attack"` + `target_camp_id` surface.
  `Fixtures.list_camps/1` (sanctioned ground truth, same status as
  `region_partition`) is used only to plan the scenario — to know
  *when* a warrior has already spawned and *which* id to track — never
  to assert the outcome. The outcome itself is asserted purely through
  the real "game:units" push (fog-filtered, mirrors "game:cities")
  and a live re-attack through the same `"attack"` hook story 891
  established, exactly the technique criterion 7539 (story 891, "zero
  HP means gone") used to prove a destroyed unit leaves the board —
  mirrored here to prove a surviving one doesn't.

  Ten hits land the killing blow, per the same reasoning as criterion
  7560's moduledoc (criterion 7559 pins a full-HP Warrior at exactly
  10 flat damage per hit, no random roll).

  Setup-hardening (not in the original contract): the warrior used to
  WALK to the camp's doorstep via `queue_move` + a 40-turn wait loop,
  and the tracked "orphan" used to be waited for via a 15-turn
  natural-spawn-cadence loop. `Fixtures.relocate_unit/3` places the
  warrior instantly; `Fixtures.spawn_barbarian/3` (tied to the same
  REAL, revealed camp — see criterion 7551's moduledoc) places the
  orphan-to-be directly, since this criterion's SUBJECT is what happens
  to an already-spawned warrior once its camp is destroyed, not the
  spawn cadence itself. `clear_tile/2` evicts any real, camp-driven
  squatter already sitting on a target tile. Recharging between the
  warrior's TEN strikes (and before the final re-attack on the orphan)
  uses `Fixtures.recharge_unit/2`, not a real `advance_turn` — see
  criterion 7559's moduledoc for why a live tick's worth of exposure to
  nearby camps' natural spawn cadence isn't safe across a long combat
  sequence.

  "game:camps" is content-diffed against its last-pushed value (QA
  issue dbcbd478); "game:units" is not (it pushes unconditionally on
  every board refresh, same as "game:cities"/"game:window"). `drain/1`
  reflects that split: it flushes whatever "game:camps" pushes DID
  accumulate (`drain_events/2`, no assertion — a quiet action
  legitimately produces none) while still asserting exactly one fresh
  "game:units" push per action (still guaranteed, so still safe to
  block on). The first `then_` block's own "game:camps" read uses
  `settle_camps/1` rather than a bare `assert_push_event`: under load,
  a single action has occasionally been observed to produce a stale,
  pre-mutation "game:camps" push immediately followed by the fresh,
  post-mutation one (an artifact of the async broadcast -> LiveView ->
  test-process relay) — `assert_push_event` would match the OLDEST
  (stale) one; `settle_camps/1` coalesces forward to the LAST one
  actually pushed, so the killing blow's own final state is what gets
  read even if attack #10 produced two.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "orphans keep fighting" do
    scenario "a warrior the camp already spawned survives its camp's destruction" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my warrior stands adjacent to an already-visible barbarian camp", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        assert_push_event(play_live, "game:camps", %{camps: pushed_camps}, 500)

        [camp | _] = pushed_camps
        [city] = Fixtures.player_cities(context.world, context.user)
        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "warrior"})
        drain(play_live)

        for _ <- 1..8 do
          Fixtures.advance_turn(context.world)
          drain(play_live)
        end

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        my_occupied = [city.tile_id, lord.tile_id, warrior.tile_id]

        [target | _] =
          context.world
          |> Fixtures.adjacent_tiles(camp.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in my_occupied))

        clear_tile(context.world, target)
        :ok = Fixtures.relocate_unit(context.world, warrior.id, target)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == warrior.id, do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:camp, camp)}
      end

      given_ "the camp has already spawned at least one barbarian warrior", context do
        # Direct placement (`Fixtures.spawn_barbarian/3`, tied to the
        # REAL camp), not a 15-turn natural-cadence wait loop — the
        # same narrow, documented-bridge status story 893's restructured
        # criteria already established (see criterion 7551's moduledoc).
        # This criterion's SUBJECT is what happens to an ALREADY-spawned
        # warrior once its camp is destroyed, not the spawn cadence
        # itself (that's story 892's job).
        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        my_occupied = [
          context.warrior.tile_id,
          Enum.find(Fixtures.player_units(context.world, context.user), &(&1.type == :lord)).tile_id
        ]

        [orphan_tile | _] =
          context.world
          |> Fixtures.adjacent_tiles(context.camp.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in my_occupied))

        clear_tile(context.world, orphan_tile)
        orphan = Fixtures.spawn_barbarian(context.world, orphan_tile, context.camp.id)
        {:ok, Map.put(context, :orphan_id, orphan.id)}
      end

      when_ "my warrior strikes the camp ten times, recharging between each hit, destroying it",
            context do
        for i <- 1..10 do
          render_hook(context.play_live, "attack", %{
            "unit_id" => to_string(context.warrior.id),
            "target_camp_id" => to_string(context.camp.id)
          })

          # Every attack broadcasts `:units_changed` — a fresh
          # "game:units" push (unconditional) plus a "game:camps" push
          # IF the camp's hp actually changed (it does, every hit) —
          # drain the first nine so the `then_` block's own
          # `assert_push_event` sees the TENTH (killing) blow's fresh
          # state, not a stale mid-fight one.
          if i < 10 do
            drain(context.play_live)

            # `Fixtures.recharge_unit/2`, not a real `advance_turn` —
            # see criterion 7559's moduledoc: a live tick's worth of
            # exposure to this camp's own (or any nearby camp's)
            # natural spawn cadence risks the warrior taking incidental
            # damage or dying outright partway through a TEN-swing
            # sequence, well before the killing blow.
            Fixtures.recharge_unit(context.world, context.warrior.id)
          end
        end

        {:ok, context}
      end

      then_ "the camp is destroyed but the previously-spawned warrior still stands on the board",
            context do
        camps_after = settle_camps(context.play_live)
        refute Enum.any?(camps_after, &(&1.id == context.camp.id))

        assert_push_event(context.play_live, "game:units", %{units: units_after}, 500)
        orphan_unit = Enum.find(units_after, &(&1.id == context.orphan_id))

        assert orphan_unit != nil
        assert orphan_unit.hp > 0
        {:ok, Map.put(context, :orphan_unit, orphan_unit)}
      end

      then_ "the orphaned warrior is still a legal, hostile attack target", context do
        orphan = context.orphan_unit

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        unless warrior.tile_id == orphan.tile_id or
                 orphan.tile_id in Fixtures.adjacent_tiles(context.world, warrior.tile_id) do
          [bridge | _] =
            context.world
            |> Fixtures.adjacent_tiles(orphan.tile_id)
            |> Enum.filter(&(Fixtures.tile_class(context.world, &1) == :land))

          clear_tile(context.world, bridge)
          :ok = Fixtures.relocate_unit(context.world, warrior.id, bridge)
        end

        # The ten-attack `when_` step above always leaves the warrior's
        # movement spent (its own tenth, killing blow) — recharge
        # directly (see criterion 7559's moduledoc) regardless of
        # whether the bridge relocation above ran, so this final attack
        # never refuses with `:out_of_movement`.
        Fixtures.recharge_unit(context.world, warrior.id)

        render_hook(context.play_live, "attack", %{
          "unit_id" => to_string(warrior.id),
          "target_unit_id" => to_string(orphan.id)
        })

        assert_push_event(context.play_live, "game:combat", %{damage_dealt: dealt}, 500)
        assert is_integer(dealt) and dealt > 0
        {:ok, context}
      end
    end
  end

  # `Phoenix.LiveViewTest.assert_push_event/3,4` always matches the
  # OLDEST message still sitting in the mailbox for its event — every
  # `queue_production`/`advance_turn`/"attack" broadcasts its own fresh
  # "game:units" push (`refresh_board/1` fires on `:cities_changed`/
  # `{:turn_advanced, _}`/`:units_changed` alike, and "game:units"
  # pushes unconditionally, unlike content-diffed "game:camps" — QA
  # issue dbcbd478), so leaving it undrained would make this
  # criterion's own `then_` assertions see stale, pre-fight state
  # instead of the fresh one their own action produced. "game:camps"
  # only pushes when the camp set itself changed, so it's flushed
  # (`drain_events/2`, no assertion) rather than asserted.
  defp drain(play_live) do
    drain_events(play_live, "game:camps")
    assert_push_event(play_live, "game:units", %{units: _}, 500)
  end

  # Deliberate, narrow exception, same status as story 893's restructured
  # criteria (see criterion 7556's own `clear_tile/2`): a real, active
  # camp may have already spawned a warrior of its own onto a tile this
  # criterion needs to place something ELSE on exactly — relocate it out
  # of the way first. A no-op if `tile_id` is already clear.
  defp clear_tile(world, tile_id) do
    occupant =
      world
      |> Fixtures.list_camps()
      |> Enum.flat_map(& &1.warriors)
      |> Enum.find(&(&1.tile_id == tile_id))

    if occupant do
      parking =
        Fixtures.adjacent_tiles(world, tile_id)
        |> Enum.filter(&(Fixtures.tile_class(world, &1) == :land and &1 != tile_id))

      Enum.find_value(parking, fn t -> Fixtures.relocate_unit(world, occupant.id, t) == :ok end)
    end

    :ok
  end
end
