defmodule BrokenOathsSpex.Story904.Criterion7640Spex do
  @moduledoc """
  Story 904 — Stone Age Progress Indicators
  Criterion 7640 — career totals so far: the progress panel shows
  running totals of cities founded, barbarian camps destroyed, and
  barbarians killed. Source: stone_age.md §12.1 — "Shows: Total
  cities founded, Total barbarian camps destroyed, Total barbarians
  killed."

  RED-first: see `BrokenOathsSpex.Story904.Criterion7639Spex`'s
  moduledoc for the general "the panel doesn't exist yet" framing this
  spec shares (same source file, same assumed mount point on
  `GameLive.Play`).

  ## Assumed data-test contract

    * `[data-test='progress-cities']` — plain integer, total cities
      ever founded by this player
    * `[data-test='progress-camps']` — plain integer, total barbarian
      camps ever destroyed by this player
    * `[data-test='progress-barbarians']` — plain integer, total
      barbarian UNITS ever killed by this player — distinct from
      camps destroyed: the story lists "Total barbarian camps
      destroyed" and "Total barbarians killed" as two separate
      figures, so a camp kill and a roaming-warrior kill must each
      only move their own counter.

  ## Setup shortcuts (documented, same status as existing combat specs)

  The Lord attacks the camp directly instead of waiting ~8 turns for a
  produced Warrior — the same shortcut `Story894.Criterion7560Spex`
  established for the warrior case, just with the Lord's own combat
  stats instead (story 896/894, stone_age.md §10.2 names "Lord (12
  damage)"; the actual flat, no-random-roll figure measured against a
  live camp while writing this spec was 11/hit — either way, well
  under 10 hits clears a 100 HP camp), with `Fixtures.recharge_unit/2`
  (not a real `advance_turn`) restoring its movement between them —
  see `Criterion7560Spex`'s own moduledoc for why a live tick between
  swings is unsafe (exposure to a nearby camp's own spawn cadence).
  This scenario never calls `advance_turn` at all, so no OTHER camp
  ever gets a chance to spawn a warrior into the Lord's path in the
  first place.

  The killed barbarian is a second, independent
  `Fixtures.spawn_barbarian/2` (a real, ownerless unit) placed
  adjacent to the Lord's post-fight position, with
  `Fixtures.set_unit_hp/3` dropping it to 1 HP first — the same
  narrow, documented exception `Story891.Criterion7539Spex` already
  established, guaranteeing the Lord's own attack is lethal regardless
  of the random damage roll.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "career totals so far" do
    scenario "founding a city, destroying a camp, and killing a barbarian each raise their own running total" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my civilization has founded one city, with my lord free to fight", context do
        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})

        [city] = Fixtures.player_cities(context.world, context.user)

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:lord, lord)}
      end

      when_ "I destroy a barbarian camp and kill a barbarian unit with my lord", context do
        [camp | _] = Fixtures.list_camps(context.world)

        camp_target =
          free_adjacent_land_tile(context.world, camp.tile_id, [context.city.tile_id])

        clear_camp_squatter(context.world, camp_target)
        :ok = Fixtures.relocate_unit(context.world, context.lord.id, camp_target)

        destroy_camp(context.play_live, context.world, context.lord.id, camp.id)

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.lord.id,
              do: u

        kill_target = free_adjacent_land_tile(context.world, lord.tile_id, [context.city.tile_id])

        barbarian = Fixtures.spawn_barbarian(context.world, kill_target)
        Fixtures.set_unit_hp(context.world, barbarian.id, 1)
        :ok = Fixtures.recharge_unit(context.world, lord.id)

        render_hook(context.play_live, "attack", %{
          "unit_id" => to_string(lord.id),
          "target_unit_id" => to_string(barbarian.id)
        })

        {:ok, context}
      end

      then_ "the panel's career totals show one city founded, one camp destroyed, and one barbarian killed",
            context do
        assert has_element?(context.play_live, "[data-test='progress-cities']", "1")
        assert has_element?(context.play_live, "[data-test='progress-camps']", "1")
        assert has_element?(context.play_live, "[data-test='progress-barbarians']", "1")
        {:ok, context}
      end
    end
  end

  # An adjacent, workable land tile to `tile_id`, excluding whatever's
  # already known-occupied (a city center, the acting unit's own start
  # tile once it's moved elsewhere). Same idiom every combat criterion
  # in stories 891/893/894/895 already uses.
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
  # `Fixtures.recharge_unit/2` rather than a real `advance_turn` — see
  # this module's own moduledoc for why. Bounded
  # at 10 attempts (a full-HP camp needed 9 real hits when this spec
  # was written, at roughly 11 flat damage/hit, no random roll — see
  # `WorldServer.resolve_camp_attack/3`/`Combat.camp_damage/2`).
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
