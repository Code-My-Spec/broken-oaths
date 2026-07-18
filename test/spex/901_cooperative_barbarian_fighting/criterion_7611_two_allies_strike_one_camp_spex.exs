defmodule BrokenOathsSpex.Story901.Criterion7611Spex do
  @moduledoc """
  Story 901 — Cooperative Barbarian Fighting
  Criterion 7611 — two different players' units can both attack the
  very same barbarian camp: neither player is refused for "someone
  else is already fighting that," and both attacks land on the same
  shared HP pool (stone_age.md §8.2, "multiple players' units can
  attack same barbarian target").

  Surface note: attacking a camp reuses the existing `"attack"` hook
  (`target_camp_id`, story 894 criterion 7558) — nothing about that
  event is player-scoped beyond ownership of the ATTACKING unit
  (`Combat.validate_camp_attack/3` checks only movement + adjacency,
  no ownership check on the camp itself, since a camp has no
  `player_id` to compare). This criterion exercises that same event
  from TWO separate, independently-authenticated LiveView connections
  against one shared camp id, rather than inventing a new
  `AlliancePanel`-specific event — "cooperation" here is a fact about
  the shared target, not a special coordination action a player takes.

  Each player founds their own city (each founding guarantees 1-2
  in-region camps per story 892 criterion 7543); this scenario always
  uses PLAYER ONE's own camp as the shared target — which of the two
  players' camps is used doesn't matter to what this criterion tests.
  `Fixtures.relocate_unit/3` places both warriors on the camp's
  doorstep instantly, the same narrow, documented-bridge status
  story 893/894's restructured criteria already established, avoiding
  a long march through a live, roaming-barbarian world.

  Fog note: `visible_camps/2`'s own rule (`WorldServer`) is "home
  region OR explored" — a camp merely ADJACENT to a unit, with no real
  turn boundary since that unit arrived, is NOT yet "explored" for
  that unit's owner (`explored` only grows via `Turn.tick/1`'s own
  `refresh_explored/1` step). Player one already sees the shared camp
  unconditionally (it's in player one's own home region, from their
  own founding); player two's warrior standing next to it right after
  `Fixtures.relocate_unit/3` is not enough on its own — one real
  `Fixtures.advance_turn/1` after both warriors are in place lets that
  tick's own `refresh_explored/1` add the camp's tile to player two's
  `explored` set, exactly as it would for a player who actually walked
  there, so player two's OWN "game:camps" push includes it for the
  rest of the scenario (attacking itself never required this —
  `Combat.validate_camp_attack/3` only checks movement + adjacency —
  but reading the shared camp's HP back through player two's own push,
  this criterion's own proof technique, does).

  "game:camps" is content-diffed against its last-pushed value (QA
  issue dbcbd478), so the setup waits below may leave zero, one, or
  several stale pushes sitting in EITHER connection's mailbox (every
  `:turn_advanced`/`:cities_changed` broadcast reaches BOTH players'
  views) — `drain_events/2` flushes them with no assertion. The
  `when_` block's own reads use `settle_camps/1` rather than a bare
  `assert_push_event`: `Phoenix.LiveViewTest.assert_push_event/3,4`
  always matches the OLDEST queued message, so player two's own read
  must walk past the INTERMEDIATE push their own view receives from
  player one's attack (cross-broadcast) to reach the one reflecting
  BOTH players' damage — and, under load, a single attack has
  occasionally been observed to produce a stale, pre-mutation
  "game:camps" push immediately followed by the fresh one.
  `settle_camps/1` coalesces forward through any of that to the LAST
  "game:camps" push actually pushed to that view.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "two allies strike one camp" do
    scenario "a second player's attack on an already-damaged camp is accepted, not refused" do
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

        # One real tick so `Turn.tick/1`'s own `refresh_explored/1` adds
        # the shared camp's tile to player two's `explored` set (see
        # this module's Fog note) — without it, player two's OWN
        # "game:camps" push never includes a camp outside their home
        # region no matter how close their unit stands. A tick's own
        # `reset_movement/1` step fully recharges both warriors too, so
        # no separate `Fixtures.recharge_unit/2` call is needed after.
        Fixtures.advance_turn(context.world)

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

      when_ "player one strikes the camp, and then player two strikes that very same camp",
            context do
        render_hook(context.play_live, "attack", %{
          "unit_id" => to_string(context.warrior.id),
          "target_camp_id" => to_string(context.camp.id)
        })

        assert_push_event(context.play_live, "game:combat", %{damage_dealt: dealt_a}, 500)
        camps_after_a = settle_camps(context.play_live)
        camp_after_a = Enum.find(camps_after_a, &(&1.id == context.camp.id))

        render_hook(context.other_play_live, "attack", %{
          "unit_id" => to_string(context.other_warrior.id),
          "target_camp_id" => to_string(context.camp.id)
        })

        assert_push_event(context.other_play_live, "game:combat", %{damage_dealt: dealt_b}, 500)
        camps_after_b = settle_camps(context.other_play_live)
        camp_after_b = Enum.find(camps_after_b, &(&1.id == context.camp.id))

        {:ok,
         context
         |> Map.put(:dealt_a, dealt_a)
         |> Map.put(:camp_after_a, camp_after_a)
         |> Map.put(:dealt_b, dealt_b)
         |> Map.put(:camp_after_b, camp_after_b)}
      end

      then_ "both attacks are accepted against the same camp, and its shared HP falls each time",
            context do
        assert is_integer(context.dealt_a) and context.dealt_a > 0
        assert is_integer(context.dealt_b) and context.dealt_b > 0

        assert context.camp_after_a != nil,
               "player two's target camp was gone before player two ever swung"

        assert context.camp_after_a.hp == context.camp.hp - context.dealt_a

        assert context.camp_after_b != nil,
               "the camp vanished from player two's own view instead of taking a second hit"

        assert context.camp_after_b.hp == context.camp_after_a.hp - context.dealt_b
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
