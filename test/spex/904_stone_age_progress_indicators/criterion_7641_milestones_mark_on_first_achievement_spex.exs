defmodule BrokenOathsSpex.Story904.Criterion7641Spex do
  @moduledoc """
  Story 904 — Stone Age Progress Indicators
  Criterion 7641 — milestones mark on first achievement: the progress
  panel flags the first time each of four events happens — founding a
  city, killing a barbarian, destroying a camp, and discovering
  another player. Source: stone_age.md §12.1 — "Milestones shown:
  First city founded, First barbarian killed, First camp destroyed,
  First player discovered."

  RED-first: see `BrokenOathsSpex.Story904.Criterion7639Spex`'s
  moduledoc for the general "the panel doesn't exist yet" framing this
  spec shares (same source file, same assumed mount point on
  `GameLive.Play`).

  ## Assumed data-test contract

  Each milestone is its own always-rendered row (so a player can see
  what's still ahead of them, the same "durable roster" spirit
  `GameLive.KnownPlayersPanel` already uses for discovered players),
  whose text reads "Achieved" once — and only once — that milestone's
  triggering event has happened for the first time:

    * `[data-test='milestone-first-city']` — first city founded
    * `[data-test='milestone-first-kill']` — first barbarian unit
      killed (distinct from a camp — see criterion 7640's own moduledoc
      for why the story tracks these as two separate figures)
    * `[data-test='milestone-first-camp']` — first barbarian camp
      destroyed
    * `[data-test='milestone-first-discovery']` — first other player
      discovered

  This spec drives all four, in the same order the story lists them,
  each as its own `when_`/`then_` pair against a single, continuously
  running `GameLive.Play` connection — proving each milestone flips
  independently rather than all four together as a side effect of any
  single action.

  ## Setup shortcuts (documented, same status as criterion 7640)

  The Lord — never a produced Warrior — does all the fighting here
  (kills the barbarian AND clears the camp), the same shortcut
  `Criterion7640Spex`'s own moduledoc documents in full: no production
  wait, `Fixtures.recharge_unit/2` (not a real `advance_turn`) between
  camp swings, `Fixtures.set_unit_hp/3` pinning the killed barbarian to
  1 HP so the Lord's own attack is lethal regardless of the random
  damage roll.

  Discovery is the one step that DOES call `Fixtures.advance_turn/1` —
  first contact is detected at a turn boundary (`GameLive.Play`'s own
  moduledoc: "the turn-boundary first-contact detection"), so there is
  no shortcut around it. It happens last, after the Lord already has a
  city, a kill, and a camp to its name, and only spends one real turn —
  low exposure to any OTHER camp's own spawn cadence, the same
  tolerance the rest of this story's specs already accept.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "milestones mark on first achievement" do
    scenario "founding a city, killing a barbarian, destroying a camp, and discovering a player each mark their own milestone" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "two players have joined the world; neither has founded a city yet", context do
        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        {:ok, other_join_live, _html} = live(context.other_conn, "/play")

        other_join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, _other_play_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        {:ok, Map.put(context, :play_live, play_live)}
      end

      when_ "I found my first city", context do
        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(context.play_live, "found_city", %{"unit_id" => to_string(settler.id)})

        [city] = Fixtures.player_cities(context.world, context.user)

        {:ok, Map.put(context, :city, city)}
      end

      then_ "the first-city milestone is marked achieved", context do
        assert has_element?(context.play_live, "[data-test='milestone-first-city']", "Achieved")
        {:ok, context}
      end

      when_ "I kill a barbarian with my lord", context do
        [lord | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        kill_target = free_adjacent_land_tile(context.world, lord.tile_id, [context.city.tile_id])

        barbarian = Fixtures.spawn_barbarian(context.world, kill_target)
        Fixtures.set_unit_hp(context.world, barbarian.id, 1)

        render_hook(context.play_live, "attack", %{
          "unit_id" => to_string(lord.id),
          "target_unit_id" => to_string(barbarian.id)
        })

        {:ok, Map.put(context, :lord, lord)}
      end

      then_ "the first-barbarian-killed milestone is marked achieved", context do
        assert has_element?(context.play_live, "[data-test='milestone-first-kill']", "Achieved")
        {:ok, context}
      end

      when_ "I destroy a barbarian camp with my lord", context do
        :ok = Fixtures.recharge_unit(context.world, context.lord.id)

        [camp | _] = Fixtures.list_camps(context.world)

        camp_target =
          free_adjacent_land_tile(context.world, camp.tile_id, [context.city.tile_id])

        clear_camp_squatter(context.world, camp_target)
        :ok = Fixtures.relocate_unit(context.world, context.lord.id, camp_target)

        destroy_camp(context.play_live, context.world, context.lord.id, camp.id)

        {:ok, context}
      end

      then_ "the first-camp-destroyed milestone is marked achieved", context do
        assert has_element?(context.play_live, "[data-test='milestone-first-camp']", "Achieved")
        {:ok, context}
      end

      when_ "another player's unit comes within sight of mine and the turn advances", context do
        [my_lord] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.lord.id,
              do: u

        [other_unit | _] = Fixtures.player_units(context.world, context.other_user)

        target =
          free_adjacent_land_tile(context.world, my_lord.tile_id, [context.city.tile_id])

        :ok = Fixtures.relocate_unit(context.world, other_unit.id, target)
        Fixtures.advance_turn(context.world)

        {:ok, context}
      end

      then_ "the first-player-discovered milestone is marked achieved", context do
        assert has_element?(
                 context.play_live,
                 "[data-test='milestone-first-discovery']",
                 "Achieved"
               )

        {:ok, context}
      end
    end
  end

  # An adjacent, workable land tile to `tile_id`, excluding whatever's
  # already known-occupied. Same idiom every combat criterion in
  # stories 891/893/894/895 already uses.
  defp free_adjacent_land_tile(world, tile_id, exclude) do
    land? = fn t -> Fixtures.tile_class(world, t) == :land end

    [target | _] =
      world
      |> Fixtures.adjacent_tiles(tile_id)
      |> Enum.filter(land?)
      |> Enum.reject(&(&1 in exclude))

    target
  end

  # Deliberate, narrow exception, same status as story 893's restructured
  # criteria (see `Story894.Criterion7560Spex`'s own `clear_tile/2`): a
  # real, active camp may already have spawned a warrior of its own onto
  # a tile this spec needs to place something ELSE on exactly — relocate
  # it out of the way first. A no-op if `tile_id` is already clear.
  defp clear_camp_squatter(world, tile_id) do
    occupant =
      world
      |> Fixtures.list_camps()
      |> Enum.flat_map(& &1.warriors)
      |> Enum.find(&(&1.tile_id == tile_id))

    if occupant do
      parking =
        world
        |> Fixtures.adjacent_tiles(tile_id)
        |> Enum.filter(&(Fixtures.tile_class(world, &1) == :land and &1 != tile_id))

      Enum.find_value(parking, fn t -> Fixtures.relocate_unit(world, occupant.id, t) == :ok end)
    end

    :ok
  end

  # Attacks `camp_id` with `attacker_id` until it's destroyed,
  # recharging the attacker's movement between hits with
  # `Fixtures.recharge_unit/2` rather than a real `advance_turn`. See
  # this module's own moduledoc. Bounded at 10 attempts (a full-HP
  # camp needed 9 real hits when this spec was written, at roughly 11
  # flat damage/hit, no random roll — see `WorldServer.
  # resolve_camp_attack/3`/`Combat.camp_damage/2`).
  #
  # `Fixtures.list_camps/1` is documented "ground truth, UNFILTERED" —
  # a destroyed camp is soft-deleted (`destroyed_at` set) but stays in
  # this list forever with `hp` clamped at 0, rather than disappearing
  # from it, so "alive" is checked via `hp > 0`, never via presence in
  # the list.
  defp destroy_camp(play_live, world, attacker_id, camp_id) do
    Enum.reduce_while(1..10, :ok, fn _, :ok ->
      camp = Enum.find(Fixtures.list_camps(world), &(&1.id == camp_id))

      if camp && camp.hp > 0 do
        render_hook(play_live, "attack", %{
          "unit_id" => to_string(attacker_id),
          "target_camp_id" => to_string(camp_id)
        })

        Fixtures.recharge_unit(world, attacker_id)
        {:cont, :ok}
      else
        {:halt, :ok}
      end
    end)
  end
end
