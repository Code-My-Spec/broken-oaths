defmodule BrokenOathsSpex.Story901.Criterion7612Spex do
  @moduledoc """
  Story 901 — Cooperative Barbarian Fighting
  Criterion 7612 — a barbarian camp's damage persists across a real
  turn boundary and across two different players' attackers: neither
  the passage of a turn nor a change of attacker resets or discounts
  the accumulated damage (stone_age.md §8.2, "combined attacks deal
  cumulative damage").

  A camp's HP total is `BrokenOaths.Combat.Camp.max_hp/0` (100 at time of
  writing, read fresh from the pushed camp payload rather than
  hardcoded); a full-HP Warrior's `attack_camp` deals a flat, unrolled
  10 (story 894 criterion 7559 — no counter, no random roll), so ten
  total hits fell it. This scenario splits those ten hits 4-then-6
  across a real `Fixtures.advance_turn/1` boundary and across the two
  players' own warriors, so the felling blow is only reachable if the
  first player's turn-one damage survived into the second player's
  turn-two assault.

  Surface note: see criterion 7611's moduledoc for why this reuses the
  existing `"attack"` + `target_camp_id` hook across two independent
  LiveView connections rather than a new `AlliancePanel`-specific
  event. `Fixtures.recharge_unit/2` restores movement directly between
  same-turn swings (story 894 criterion 7559's documented reasoning:
  a live tick's worth of exposure to this camp's own natural spawn
  cadence, repeated across a long combat sequence, risks a warrior
  taking incidental damage or dying well before the felling blow — the
  ONE real `advance_turn` this criterion's own subject requires is
  therefore kept to exactly once, not once per swing). That one real
  tick still runs `resolve_barbarian_ai` same as any other, and player
  two's warrior stands right next to the very camp under assault — an
  incidental hit there would scale down every one of player two's six
  swings via `wounded_multiplier/1` (irrelevant to this criterion's
  own subject), so `Fixtures.set_unit_hp/3` heals it back to full
  immediately after that boundary if needed, guaranteeing each swing
  still lands the flat, unrolled 10 criterion 7559 pins for a full-HP
  warrior.

  "game:camps" is content-diffed against its last-pushed value (QA
  issue dbcbd478), so the 8-turn setup wait below may leave zero, one,
  or several stale pushes sitting in EITHER connection's mailbox
  (every `:turn_advanced`/`:cities_changed` broadcast reaches BOTH
  players' views) — `drain_events/2` flushes them with no assertion.
  Every per-strike read below uses `settle_camps/1` rather than a
  bare `assert_push_event`: `Phoenix.LiveViewTest.assert_push_event/3,4`
  always matches the OLDEST queued message, so player two's own reads
  must walk past the INTERMEDIATE pushes their own view receives from
  player one's four earlier strikes (cross-broadcast) to reach each
  strike's own fresh result — and, under load, a single attack has
  occasionally been observed to produce a stale, pre-mutation
  "game:camps" push immediately followed by the fresh one.
  `settle_camps/1` coalesces forward through any of that to the LAST
  "game:camps" push actually pushed to that view for that swing.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "combined damage fells a camp over two turns" do
    scenario "damage from turn one, by one ally, survives into turn two, where the other ally finishes the camp off" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "both players have founded cities, and each has a warrior standing beside the same barbarian camp",
             context do
        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        assert_push_event(play_live, "game:camps", %{camps: pushed_camps}, 500)
        [camp | _] = pushed_camps
        [city] = Fixtures.player_cities(context.world, context.user)

        render_hook(play_live, "queue_production", %{
          "city_id" => to_string(city.id),
          "item" => "warrior"
        })

        {:ok, other_join_live, _html} = live(context.other_conn, "/play")

        other_join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, other_play_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        [other_settler | _] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :settler,
              do: u

        render_hook(other_play_live, "found_city", %{"unit_id" => to_string(other_settler.id)})
        [other_city] = Fixtures.player_cities(context.world, context.other_user)

        render_hook(other_play_live, "queue_production", %{
          "city_id" => to_string(other_city.id),
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

        [other_lord] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :lord,
              do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        occupied = [city.tile_id, lord.tile_id, other_city.tile_id, other_lord.tile_id]

        [target_a, target_b | _] =
          context.world
          |> Fixtures.adjacent_tiles(camp.tile_id)
          |> Enum.uniq()
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in occupied))

        clear_tile(context.world, target_a)
        :ok = Fixtures.relocate_unit(context.world, warrior.id, target_a)
        clear_tile(context.world, target_b)
        :ok = Fixtures.relocate_unit(context.world, other_warrior.id, target_b)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == warrior.id, do: u

        [other_warrior] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == other_warrior.id,
              do: u

        drain_events(play_live, "game:camps")
        drain_events(other_play_live, "game:camps")

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:other_play_live, other_play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:other_warrior, other_warrior)
         |> Map.put(:camp, camp)}
      end

      given_ "player one wears the camp down across four strikes this turn, without felling it",
             context do
        camp_after =
          Enum.reduce(1..4, nil, fn i, _acc ->
            render_hook(context.play_live, "attack", %{
              "unit_id" => to_string(context.warrior.id),
              "target_camp_id" => to_string(context.camp.id)
            })

            assert_push_event(context.play_live, "game:combat", %{damage_dealt: _}, 500)
            camps = settle_camps(context.play_live)
            if i < 4, do: Fixtures.recharge_unit(context.world, context.warrior.id)
            Enum.find(camps, &(&1.id == context.camp.id))
          end)

        {:ok, Map.put(context, :camp_after_turn_one, camp_after)}
      end

      when_ "a turn boundary passes, and then player two's warrior finishes the same camp off",
            context do
        Fixtures.advance_turn(context.world)
        Fixtures.recharge_unit(context.world, context.other_warrior.id)

        # The one real turn boundary this criterion's own subject
        # requires (see this module's doc) is a live tick like any
        # other: `resolve_barbarian_ai` runs same as every other turn,
        # and player two's warrior is standing right next to the very
        # camp under assault, well within aggro range. Criterion
        # 7559's own `wounded_multiplier/1` scales EVERY later hit's
        # damage down from any incidental HP this warrior took on that
        # boundary — irrelevant to what THIS criterion means to prove
        # (damage persisting across a turn and a change of attacker),
        # so heal back to full before the six-swing sequence needs
        # every hit to land at the flat, unrolled 10 criterion 7559
        # pins for a full-HP warrior. Same narrow, documented-bridge
        # status as `Fixtures.recharge_unit/2` just above.
        [other_warrior] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.other_warrior.id,
              do: u

        if other_warrior.hp < other_warrior.max_hp do
          Fixtures.set_unit_hp(context.world, other_warrior.id, other_warrior.max_hp)
        end

        camp_after =
          Enum.reduce(1..6, {:standing, nil}, fn i, _acc ->
            render_hook(context.other_play_live, "attack", %{
              "unit_id" => to_string(context.other_warrior.id),
              "target_camp_id" => to_string(context.camp.id)
            })

            assert_push_event(context.other_play_live, "game:combat", %{damage_dealt: dealt}, 500)
            assert dealt == 10
            camps = settle_camps(context.other_play_live)
            if i < 6, do: Fixtures.recharge_unit(context.world, context.other_warrior.id)

            case Enum.find(camps, &(&1.id == context.camp.id)) do
              nil -> {:destroyed, nil}
              camp -> {:standing, camp}
            end
          end)

        {:ok, Map.put(context, :camp_after_turn_two, camp_after)}
      end

      then_ "player one's turn-one damage was real — the camp took damage but survived",
            context do
        assert context.camp_after_turn_one != nil,
               "the camp was already gone after only four hits, well short of its full HP"

        assert context.camp_after_turn_one.hp == context.camp.hp - 40
        {:ok, context}
      end

      then_ "player two's turn-two damage, added on top of turn one's, is what finally fells the camp",
            context do
        assert context.camp_after_turn_two == {:destroyed, nil},
               "the camp outlasted the combined ten hits across both allies and both turns"

        {:ok, context}
      end
    end
  end

  # Deliberate, narrow exception, same status as story 893/894's
  # restructured criteria: a real, active camp may have already spawned
  # a warrior of its own onto a tile this criterion needs to place
  # something ELSE on exactly — relocate it out of the way first. A
  # no-op if `tile_id` is already clear.
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
