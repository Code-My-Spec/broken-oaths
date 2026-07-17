defmodule BrokenOathsSpex.Story894.Criterion7558Spex do
  @moduledoc """
  Story 894 — Camp Assault
  Criterion 7558 — a military unit standing adjacent to a barbarian
  camp can attack it, and the camp never strikes back: the camp loses
  HP, but the attacker's own HP is untouched, no matter how many times
  it swings.

  Surface note: attacking a camp is inferred to reuse the same
  `"attack"` hook story 891 established for unit-vs-unit combat
  (criterion 7533), swapping `target_unit_id` for `target_camp_id`
  since a camp is not a `Game.Unit` — `BrokenOaths.Game.Camps` doesn't
  exist yet, so this is this spec's judgment call for the event shape,
  the same status story 892's `"game:camps"` push inference carries.
  Combat resolution is likewise assumed to reuse the `"game:combat"`
  push criterion 7540 established (`damage_dealt`/`damage_taken`
  keys) — `combat.spec.md` names "flat-strength damage against camps"
  and "combat-result reporting" as the same `Game.Combat` module's
  responsibility, so the same result event is the natural fit.

  The target camp is one of the 1-2 in-region camps guaranteed visible
  immediately on founding the first city (story 892, criterion 7543)
  — no march through fog is needed here, unlike story 892's discovery
  criteria.

  Setup-hardening (not in the original contract): the warrior used to
  WALK to the camp's doorstep via `queue_move` + a 40-turn wait loop.
  `Fixtures.relocate_unit/3` places it instantly instead (the same
  narrow, documented-bridge status story 893's restructured criteria
  already established) — and since relocation never touches
  `movement` (unlike a real `queue_move`, which always spends it
  arriving), the extra turn boundary the old version needed just to
  recharge before attacking is no longer necessary either. `clear_tile/2`
  evicts any real, camp-driven squatter already sitting on the
  warrior's target tile.

  Also fixed (not a restructuring change, a genuine pre-existing bug in
  this spec): `queue_production` and each of the setup's 8 production-wait
  `advance_turn` calls broadcast their own fresh "game:camps" push
  (`refresh_board/1` fires on `:cities_changed` and `{:turn_advanced, _}`
  alike) — left undrained, the `then_` block's own `assert_push_event`
  matched the STALE, pre-attack push instead of the fresh post-attack
  one (the exact same "first-match-in-mailbox" hazard already documented
  and fixed across story 893's restructured criteria), making
  `camp_after.hp` read as unchanged even though the attack landed.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "free hits on the tents" do
    scenario "attacking a camp costs the camp HP but never the attacker's" do
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

        # `queue_production` broadcasts `:cities_changed`, and every
        # `advance_turn` broadcasts `{:turn_advanced, _}` — both trigger
        # `refresh_board/1`, which pushes a FRESH "game:camps" every
        # time. `assert_push_event` always matches the FIRST matching
        # message still in the mailbox, so leaving these nine pushes
        # undrained would make the `then_` block's own `assert_push_event`
        # see the camp's UNDAMAGED, pre-attack state from here instead
        # of the fresh state its own attack produces.
        assert_push_event(play_live, "game:camps", %{camps: _}, 500)

        for _ <- 1..8 do
          Fixtures.advance_turn(context.world)
          assert_push_event(play_live, "game:camps", %{camps: _}, 500)
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
         |> Map.put(:warrior_hp0, warrior.hp)
         |> Map.put(:camp, camp)}
      end

      when_ "I order my warrior to attack the camp", context do
        render_hook(context.play_live, "attack", %{
          "unit_id" => to_string(context.warrior.id),
          "target_camp_id" => to_string(context.camp.id)
        })

        {:ok, context}
      end

      then_ "the camp loses HP but my warrior takes no counter-damage", context do
        assert_push_event(
          context.play_live,
          "game:combat",
          %{damage_dealt: dealt, damage_taken: taken},
          500
        )

        assert is_integer(dealt) and dealt > 0
        assert taken == 0

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        assert warrior.hp == context.warrior_hp0

        assert_push_event(context.play_live, "game:camps", %{camps: camps_after}, 500)
        camp_after = Enum.find(camps_after, &(&1.id == context.camp.id))

        assert camp_after != nil
        assert camp_after.hp < context.camp.hp
        {:ok, context}
      end
    end
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
