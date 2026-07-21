defmodule BrokenOathsSpex.Story894.Criterion7560Spex do
  @moduledoc """
  Story 894 — Camp Assault
  Criterion 7560 — reducing a camp to 0 HP destroys it: the destroying
  unit's owner receives a 30 gold reward, and the hex reverts to
  normal, buildable terrain (an improvement can be started there).

  Surface note: see `BrokenOathsSpex.Story894.Criterion7558Spex`'s
  moduledoc for the inferred `"attack"` + `target_camp_id` surface.
  Gold is read from the existing `data-test="player-gold"` badge
  `GameLive.Play` already renders (`{@gold}`, backed by `Game.gold/2`
  per the Fixtures/Play surface list) — no new read invented.

  Ten hits land the killing blow: criterion 7559 pins a full-HP
  Warrior's damage at exactly 10 per hit with no random roll, so ten
  consecutive hits against a 100 HP camp are the deterministic way to
  drive it to exactly 0 without a test-only HP setter (no such setter
  exists for camps — `Fixtures.set_unit_hp/3` is documented as a unit-
  only, narrow exception).

  Scope note: "reverts to normal terrain" is demonstrated here through
  the Worker/Improvement path only. Asserts `build-farm` specifically
  (not `build-road`, this criterion's original witness): this world's
  own seed (424242) deterministically places the camp on flat,
  featureless Plains, so Farm's own terrain gate
  (`Improvement.allowed?(:farm, _)`) is satisfied with no extra setup
  — Road stopped being a terrain-only, always-legal witness once
  playtest issue eb5ec4f9 gated it behind The Wheel, and researching
  that tech here would mean hundreds of extra live `advance_turn`s (no
  `isolate_camp_for_test` guard in this scenario), reintroducing
  exactly the barbarian-interference flakiness this criterion's own
  "Setup-hardening" note below already went out of its way to avoid.
  Founding a *second* city on the former camp hex is not separately
  exercised: it would additionally require producing and marching a
  Settler, and risks tripping the unrelated `:too_close`
  founding-distance rule (`Production.validate_founding/3` requires
  4+ hexes from every existing city) for an in-region camp, which
  would fail the scenario for a reason unrelated to this criterion.
  Both paths are gated by the same "is this hex ordinary land" fact,
  so the Worker path stands in for both.

  Setup-hardening (not in the original contract): both the warrior and
  the worker used to WALK to their targets via `queue_move` + 40-turn
  wait loops. `Fixtures.relocate_unit/3` places them instantly instead
  (the same narrow, documented-bridge status story 893's restructured
  criteria already established); `clear_tile/2` evicts any real,
  camp-driven squatter already sitting on a target tile.

  Recharging BETWEEN the warrior's TEN strikes is the one place a real
  `advance_turn` turned out unsafe — see criterion 7559's own moduledoc
  for the full story: a live tick's worth of exposure to a nearby
  camp's natural spawn cadence, repeated nine times across this
  criterion's longer ten-swing sequence, risks the warrior taking
  incidental damage or dying outright well before the killing blow.
  `Fixtures.recharge_unit/2` restores movement directly with no live
  tick at all. The post-loop `advance_turn` the original version ran
  once more after the tenth strike was also removed: `do_attack_camp`
  destroys the camp and pays the bounty synchronously within that same
  attack (`apply_camp_damage/3`), broadcasting `:units_changed`
  immediately — the `then_` block's own "game:camps"/"game:cities"
  pushes are already fresh without an extra boundary, and skipping it
  removes one more turn's worth of unrelated exposure.

  "game:camps" is content-diffed against its last-pushed value (QA
  issue dbcbd478); "game:cities" is not (it pushes unconditionally on
  every board refresh, same as "game:units"/"game:window"). `drain/1`
  below reflects that split: it flushes whatever "game:camps" pushes
  DID accumulate (`drain_events/2`, no assertion — a quiet action
  legitimately produces none) while still asserting exactly one fresh
  "game:cities" push per action (still guaranteed, so still safe to
  block on). The `then_` block's own "game:camps" read uses
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

  spex "the camp falls and the land opens" do
    scenario "a camp reduced to 0 HP is destroyed, pays out gold, and frees its hex" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my warrior stands adjacent to an already-visible barbarian camp, and a worker is on the way",
             context do
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
        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "worker"})
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

        gold0 = player_gold(play_live)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:camp, camp)
         |> Map.put(:city, city)
         |> Map.put(:gold0, gold0)}
      end

      when_ "my warrior strikes the camp ten times, recharging between each hit", context do
        for i <- 1..10 do
          render_hook(context.play_live, "attack", %{
            "unit_id" => to_string(context.warrior.id),
            "target_camp_id" => to_string(context.camp.id)
          })

          # Every attack broadcasts `:units_changed` — a fresh
          # "game:cities"/"game:units" push (unconditional) plus a
          # "game:camps" push IF the camp's hp actually changed (it
          # does, every hit) — drain the first nine so the `then_`
          # block's own `assert_push_event` sees the TENTH (killing)
          # blow's fresh state, not a stale mid-fight one.
          if i < 10 do
            drain(context.play_live)

            # `Fixtures.recharge_unit/2`, not a real `advance_turn` —
            # see criterion 7559's moduledoc: a live tick's worth of
            # exposure to this camp's own (or any nearby camp's)
            # natural spawn cadence risks the warrior taking incidental
            # damage or dying outright partway through a TEN-swing
            # sequence, well before the killing blow — recharging
            # directly needs no live tick at all, so there's nothing
            # left to be exposed to.
            Fixtures.recharge_unit(context.world, context.warrior.id)
          end
        end

        {:ok, context}
      end

      then_ "the camp is gone from the board", context do
        camps_after = settle_camps(context.play_live)
        assert_push_event(context.play_live, "game:cities", %{cities: cities_after}, 500)

        # Anchor: the push pipeline itself is healthy (my own city still
        # renders) — not a stale/empty payload that would pass the
        # refute below vacuously.
        assert Enum.any?(cities_after, &(&1.id == context.city.id))
        refute Enum.any?(camps_after, &(&1.id == context.camp.id))
        {:ok, context}
      end

      then_ "my gold increases by exactly 30", context do
        assert player_gold(context.play_live) == context.gold0 + 30
        {:ok, context}
      end

      then_ "the former camp hex now accepts a normal improvement", context do
        worker =
          Enum.reduce_while(1..20, nil, fn _, _ ->
            case for u <- Fixtures.player_units(context.world, context.user),
                     u.type == :worker,
                     do: u do
              [w | _] ->
                {:halt, w}

              [] ->
                Fixtures.advance_turn(context.world)
                {:cont, nil}
            end
          end)

        refute is_nil(worker)

        clear_tile(context.world, context.camp.tile_id)
        :ok = Fixtures.relocate_unit(context.world, worker.id, context.camp.tile_id)

        render_hook(context.play_live, "select_unit", %{"unit_id" => worker.id})
        assert has_element?(context.play_live, "[data-test='build-farm']")
        {:ok, context}
      end
    end
  end

  # `Phoenix.LiveViewTest.assert_push_event/3,4` always matches the
  # OLDEST message still sitting in the mailbox for its event — every
  # `queue_production`/`advance_turn`/"attack" broadcasts its own fresh
  # "game:cities" push (`refresh_board/1` fires on `:cities_changed`/
  # `{:turn_advanced, _}`/`:units_changed` alike, and "game:cities"
  # pushes unconditionally, unlike content-diffed "game:camps" — QA
  # issue dbcbd478), so leaving it undrained would make this
  # criterion's own `then_` assertions see stale, pre-fight state
  # instead of the fresh one their own action produced. "game:camps"
  # only pushes when the camp set itself changed, so it's flushed
  # (`drain_events/2`, no assertion) rather than asserted.
  defp drain(play_live) do
    drain_events(play_live, "game:camps")
    assert_push_event(play_live, "game:cities", %{cities: _}, 500)
  end

  # The gold badge renders the icon component (no digits) followed by
  # the plain integer — the last digit run in the fragment is always
  # the gold total, regardless of the icon's own markup.
  defp player_gold(play_live) do
    html = play_live |> element("[data-test='player-gold']") |> render()

    ~r/\d+/
    |> Regex.scan(html)
    |> List.last()
    |> List.first()
    |> String.to_integer()
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
