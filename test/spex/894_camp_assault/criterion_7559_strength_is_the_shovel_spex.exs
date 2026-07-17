defmodule BrokenOathsSpex.Story894.Criterion7559Spex do
  @moduledoc """
  Story 894 — Camp Assault
  Criterion 7559 — damage against a camp is the attacker's flat
  effective strength, with no random roll: a Warrior deals exactly 10
  per hit, a Lord exactly 12, every time — unlike unit-vs-unit combat,
  which rolls a ±25% Civ VI curve around a strength-derived band
  (story 891, criterion 7537).

  Surface note: see `BrokenOathsSpex.Story894.Criterion7558Spex`'s
  moduledoc for the inferred `"attack"` + `target_camp_id` surface and
  the `"game:combat"` push (`damage_dealt`/`damage_taken`) this spec
  reads the exact per-hit number from.

  "No random roll" is demonstrated by striking the same camp with the
  same warrior three separate times (recharging its spent movement
  between each, per story 891 criterion 7536) and showing every single
  hit lands the identical number — a ±25% roll could not produce three
  identical results.

  Structure note: the Warrior and Lord facts are independently
  verifiable claims, so each gets its own `spex`/`scenario` pair rather
  than two `scenario` blocks sharing one `spex`. `SexySpex.DSL.spex/2`
  compiles to exactly one `ExUnit` `test`, and `scenario/1` only
  resets the step context inside that same test — it does not start a
  new one. A second `scenario` nested in the same `spex` therefore
  never runs as its own test: if the first scenario's first step
  raises (as it does here, since `"game:camps"` isn't implemented
  yet), the exception propagates straight out of the enclosing `spex`
  test and the second scenario's body never executes at all, silently
  losing that coverage. Two `spex` blocks avoid that trap and give each
  fact its own independently-reported pass/fail.

  Setup-hardening (not in the original contract): the warrior/lord used
  to WALK to the camp's doorstep via `queue_move` + a 40-turn wait
  loop. `Fixtures.relocate_unit/3` places them instantly instead (the
  same narrow, documented-bridge status story 893's restructured
  criteria already established) — relocation never touches `movement`
  (unlike a real `queue_move`, which always spends it arriving), so the
  Warrior scenario's first strike needs no recharge turn beforehand.
  `clear_tile/2` evicts any real, camp-driven squatter already sitting
  on the target tile. Both `then_` blocks read only the "game:combat"
  push (pushed directly from the same `handle_event` call, not via a
  broadcast+refresh), so unlike criterion 7558 there's no "game:camps"
  mailbox-staleness risk here to guard against.

  Recharging BETWEEN the Warrior's three strikes is the one place this
  spec still needed to restore spent movement, and a real `advance_turn`
  turned out not to be safe for it: `Combat.effective_strength/2` scales
  damage by the attacker's own current hp/max_hp ratio
  (`wounded_multiplier/1`) — real, but unrelated to the "±25% random
  roll" this criterion is actually about — and a full tick's worth of
  exposure to this camp's own (or any nearby camp's) natural spawn
  cadence risked incidental damage that would legitimately knock later
  hits below 10, or even (confirmed empirically) kill the warrior
  outright, which no HP fixture can undo after the fact.
  `Fixtures.recharge_unit/2` (new, narrow, documented-bridge status —
  see `BrokenOaths.Game.WorldServer`'s `:recharge_unit_for_test`
  handler) restores movement directly with no live tick at all, so
  there's nothing left for the warrior to be exposed to between swings.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "strength is the shovel: a warrior's blows are always exactly its strength" do
    scenario "a warrior's blows against the tents are always exactly its strength" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my full-HP warrior stands adjacent to an already-visible barbarian camp", context do
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

        for _ <- 1..8, do: Fixtures.advance_turn(context.world)

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

      when_ "my warrior strikes the camp three separate times, recharging between each",
            context do
        damages =
          Enum.map(1..3, fn i ->
            render_hook(context.play_live, "attack", %{
              "unit_id" => to_string(context.warrior.id),
              "target_camp_id" => to_string(context.camp.id)
            })

            assert_push_event(context.play_live, "game:combat", %{damage_dealt: dealt}, 500)

            # `Fixtures.recharge_unit/2`, not a real `advance_turn` — see
            # this module's doc: `Combat.effective_strength/2` scales
            # damage by the ATTACKER's own current hp/max_hp ratio
            # (`wounded_multiplier/1`), so a real turn boundary's worth
            # of exposure to this camp's own natural spawn cadence (or
            # any OTHER nearby camp's) risks incidental damage that
            # would legitimately (if irrelevantly) knock every
            # SUBSEQUENT number below 10 — confirmed empirically to
            # sometimes outright kill the warrior, which no HP fixture
            # can undo. Recharging directly needs no live tick at all,
            # so there's nothing left to be exposed to.
            if i < 3, do: Fixtures.recharge_unit(context.world, context.warrior.id)

            dealt
          end)

        {:ok, Map.put(context, :damages, damages)}
      end

      then_ "every single hit deals exactly 10 damage", context do
        assert context.damages == [10, 10, 10]
        {:ok, context}
      end
    end
  end

  spex "strength is the shovel: the lord's blows land at its own strength" do
    scenario "the lord's blows land at its own strength, not the warrior's" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my lord stands adjacent to an already-visible barbarian camp", context do
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

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        my_occupied = [city.tile_id, lord.tile_id]

        [target | _] =
          context.world
          |> Fixtures.adjacent_tiles(camp.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in my_occupied))

        clear_tile(context.world, target)
        :ok = Fixtures.relocate_unit(context.world, lord.id, target)

        [lord] = for u <- Fixtures.player_units(context.world, context.user), u.id == lord.id, do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:lord, lord)
         |> Map.put(:camp, camp)}
      end

      when_ "my lord attacks the camp", context do
        render_hook(context.play_live, "attack", %{
          "unit_id" => to_string(context.lord.id),
          "target_camp_id" => to_string(context.camp.id)
        })

        {:ok, context}
      end

      then_ "the hit deals exactly 12 damage", context do
        assert_push_event(context.play_live, "game:combat", %{damage_dealt: dealt}, 500)
        assert dealt == 12
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
