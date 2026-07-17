defmodule BrokenOathsSpex.Story895.Criterion7565Spex do
  @moduledoc """
  Story 895 — City Defense and Garrison
  Criterion 7565 — a unit garrisoned on a city's own tile (a) fights
  with a +50% boost to its combat strength and (b) can strike an
  adjacent barbarian without leaving the tile.

  Reuses story 891's `Game.Combat` surface verbatim (the `"attack"`
  hook, the Civ VI damage curve, adjacency-only attacks with no
  movement) — the only new ingredient is that the attacker starts the
  fight already garrisoned.

  Setup-hardening (not in the original contract): earlier drafts of
  this criterion stood a second real player's warrior in for "the
  barbarian" (the convention `BrokenOathsSpex.Story891.Criterion7533Spex`'s
  moduledoc describes for a DIFFERENT purpose — sparing a wait on
  `Game.Camps`' own spawn cadence). That doesn't work HERE:
  `Game.Combat.hostile?/2` refuses combat between two units that both
  carry a real `player_id` ("no Stone Age PvP" — story 891, criterion
  7542, a HARD, already-passing rule this criterion must not weaken),
  so an ordinary `"attack"`/`target_unit_id` order between two real
  players' units is refused outright — `damage_dealt` stays 0
  regardless of any garrison bonus, for a reason that has nothing to
  do with what this criterion means to test. This version uses a REAL,
  ownerless barbarian instead (`Fixtures.spawn_barbarian/2`,
  `player_id: nil` — the same fixture criterion 7533 itself uses),
  placed directly on a land tile adjacent to the city — no march, no
  exposure to any OTHER independently-roaming camp warrior along the
  way. A real barbarian warrior's base strength is 15
  (`Game.Combat.base_strength/1`), not the 10 an earlier draft's
  stand-in Warrior carried, so the expected damage band below is
  computed against 15, not 10: attacker strength
  `Combat.garrisoned_strength/2` = 10 × 1.5 = 15 (garrison bonus,
  full HP, no aura — see the lord-relocation hardening below) against
  defender strength 15 (equal strength) — `30 × e^0 × [0.75, 1.25]`
  ≈ `[22.5, 37.5]`, rounding (round-half-away-from-zero, same as
  `combat_test.exs`'s own `expected_band/2` helper) to `[23, 38]`.

  A second hardening, unrelated to the barbarian swap: `Spawner`
  places a fresh civilization's lord and settler close together by
  design, so the lord routinely lands adjacent to the settler's
  (hence the city's) own tile. Left there, `Combat`'s pre-existing +2
  lord-aura bonus (story 891) would fold into the garrison-boosted
  strength this criterion means to isolate, pushing damage outside
  the band above on whichever runs happen to spawn the lord next
  door. The lord is relocated well clear of the city first — a real
  in-game action, `Fixtures.relocate_unit/3`, the same sanctioned
  bridge story 893's own specs already use.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "fighting from the walls" do
    scenario "a garrisoned warrior strikes an adjacent barbarian without leaving the city" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my warrior stands garrisoned on my city's own tile, adjacent to a barbarian", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
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

        # See moduledoc's lord-relocation hardening note.
        far_tile =
          context.world
          |> ring_tiles(city.tile_id, 3)
          |> Enum.filter(&(Fixtures.tile_class(context.world, &1) == :land))
          |> List.first()

        :ok = Fixtures.relocate_unit(context.world, lord.id, far_tile)
        [lord] = for u <- Fixtures.player_units(context.world, context.user), u.id == lord.id, do: u

        unless warrior.tile_id == city.tile_id do
          render_hook(play_live, "queue_move", %{
            "unit_id" => to_string(warrior.id),
            "to_tile" => city.tile_id
          })

          Enum.reduce_while(1..10, :ok, fn _, :ok ->
            [w] =
              for u <- Fixtures.player_units(context.world, context.user),
                  u.id == warrior.id,
                  do: u

            if w.tile_id == city.tile_id do
              {:halt, :ok}
            else
              Fixtures.advance_turn(context.world)
              {:cont, :ok}
            end
          end)
        end

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == warrior.id, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        my_occupied = [city.tile_id, lord.tile_id]

        [barbarian_tile | _] =
          context.world
          |> Fixtures.adjacent_tiles(city.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in my_occupied))

        barbarian = Fixtures.spawn_barbarian(context.world, barbarian_tile)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:warrior, warrior)
         |> Map.put(:barbarian, barbarian)
         |> Map.put(:barbarian_hp0, barbarian.hp)}
      end

      when_ "I order my garrisoned warrior to attack the barbarian", context do
        render_hook(context.play_live, "attack", %{
          "unit_id" => to_string(context.warrior.id),
          "target_unit_id" => to_string(context.barbarian.id)
        })

        {:ok, context}
      end

      then_ "the damage dealt reflects the garrison's boosted combat strength (roughly 23 to 38)",
            context do
        [barbarian] =
          for u <- Fixtures.visible_units(context.world, context.user), u.id == context.barbarian.id, do: u

        dealt = context.barbarian_hp0 - barbarian.hp
        assert dealt >= 23 and dealt <= 38
        {:ok, context}
      end

      then_ "my warrior remains garrisoned on the city tile after striking", context do
        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        assert warrior.tile_id == context.city.tile_id
        {:ok, context}
      end
    end
  end

  # Every land tile whose raw mesh-adjacency distance from `start` is
  # exactly `depth` — the same BFS-ring idiom criteria 7543/7544/7569
  # already use for "how many hexes away."
  defp ring_tiles(world, start, depth) do
    Enum.reduce(1..depth, {[start], MapSet.new([start])}, fn _, {frontier, seen} ->
      next =
        frontier
        |> Enum.flat_map(&BrokenOathsSpex.Fixtures.adjacent_tiles(world, &1))
        |> Enum.uniq()
        |> Enum.reject(&MapSet.member?(seen, &1))

      {next, MapSet.union(seen, MapSet.new(next))}
    end)
    |> elem(0)
  end
end
