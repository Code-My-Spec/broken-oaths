defmodule BrokenOathsSpex.Story901.Criterion7615Spex do
  @moduledoc """
  Story 901 — Cooperative Barbarian Fighting
  Criterion 7615 — when only ONE player's units ever struck a camp,
  destroying it pays that player the FULL bounty — proportional
  splitting (criterion 7614) must never shortchange a solo kill just
  because the game now supports sharing it with allies.

  This is the guard-rail corollary to 7614's proportional-split rule:
  a 100%-contribution share is still 100% of the bounty, not some
  default fraction. Structurally this mirrors story 894 criterion
  7560's own "the camp falls and the land opens" scenario (same ten
  flat, unrolled hits — story 894 criterion 7559 — felling the same
  100-HP camp for the same 30-gold `Camps.destroy_reward/0`), but is
  restated here as story 901's own acceptance criterion because it's
  the specific behavior this story's cooperative-bounty change must
  not regress.

  "game:camps" is content-diffed against its last-pushed value (QA
  issue dbcbd478), so the 8-turn setup wait below may leave zero, one,
  or several stale pushes sitting in the mailbox — `drain_events/2`
  flushes them with no assertion. The ten-attack `when_` loop below
  deliberately does NOT drain "game:camps" between swings: each swing
  changes the camp's hp, so by the tenth (killing) blow the mailbox
  holds a backlog of up to ten pushes, oldest first. `then_`'s own
  read uses `settle_camps/1` rather than a bare `assert_push_event`
  (which would match the OLDEST, first-swing snapshot) — it walks
  forward through that whole backlog, coalescing to the LAST
  "game:camps" push actually produced, i.e. the post-destruction one.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "sole attacker keeps the whole bounty" do
    scenario "a camp felled entirely by one player's own warrior pays that player the full bounty" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my warrior stands adjacent to an already-visible barbarian camp, with no ally in sight",
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

        gold0 = player_gold(play_live)
        drain_events(play_live, "game:camps")

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:camp, camp)
         |> Map.put(:gold0, gold0)}
      end

      when_ "my warrior alone strikes the camp ten times, recharging between each hit, felling it",
            context do
        for i <- 1..10 do
          render_hook(context.play_live, "attack", %{
            "unit_id" => to_string(context.warrior.id),
            "target_camp_id" => to_string(context.camp.id)
          })

          assert_push_event(context.play_live, "game:combat", %{damage_dealt: dealt}, 500)
          assert dealt == 10
          if i < 10, do: Fixtures.recharge_unit(context.world, context.warrior.id)
        end

        {:ok, context}
      end

      then_ "the camp is destroyed", context do
        camps_after = settle_camps(context.play_live)
        refute Enum.any?(camps_after, &(&1.id == context.camp.id))
        {:ok, context}
      end

      then_ "my gold increases by the full 30-gold bounty — no share was withheld for a non-existent ally",
            context do
        assert player_gold(context.play_live) == context.gold0 + 30
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

  # The gold badge renders the icon component (no digits) followed by
  # the plain integer — the last digit run in the fragment is always
  # the gold total, regardless of the icon's own markup (story 894
  # criterion 7560's own helper).
  defp player_gold(play_live) do
    html = play_live |> element("[data-test='player-gold']") |> render()

    ~r/\d+/
    |> Regex.scan(html)
    |> List.last()
    |> List.first()
    |> String.to_integer()
  end
end
