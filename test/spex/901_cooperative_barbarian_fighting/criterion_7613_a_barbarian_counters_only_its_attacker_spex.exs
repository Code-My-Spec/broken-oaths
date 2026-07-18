defmodule BrokenOathsSpex.Story901.Criterion7613Spex do
  @moduledoc """
  Story 901 — Cooperative Barbarian Fighting
  Criterion 7613 — when two different players' units are both
  attacking the same barbarian warrior, its counter-attack lands only
  on whichever of them is striking it in that exchange — never on the
  other, uninvolved ally (stone_age.md §8.2, "barbarian counter-attacks
  distributed among attackers" — refined here to "distributed" meaning
  "routed to whichever attacker it faces," not "split across every
  cooperating attacker").

  `Game.Combat.resolve/3` already computes a single exchange between
  exactly one attacker and one defender at a time (see that module's
  moduledoc: "both computed from the same pre-combat strengths"); this
  criterion is the acceptance-level proof that nothing about a SECOND
  ally standing nearby ever pulls damage onto them.

  This uses a stand-alone, camp-less barbarian warrior
  (`Fixtures.spawn_barbarian/2`, 15/15/120 per story 893's own
  moduledoc) rather than a camp — camps never counter-attack at all
  (story 894 criterion 7558), so a camp can't demonstrate "who the
  counter lands on." At 120 HP, a single Stone Age Warrior's hit
  (bounded well under 31 damage even at the ±25% roll's ceiling, per
  `Combat.damage/3`'s curve for a 10-strength attacker against a
  15-strength defender) can never come close to felling it in one
  blow, so the barbarian is guaranteed to still be standing — and
  still able to counter — for both allies' strikes.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a barbarian counters only its attacker" do
    scenario "the counter-blow lands on whichever ally is striking, never on the other" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "both players have founded cities, and each has a warrior standing beside a single wild barbarian",
             context do
        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
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

        occupied = [
          city.tile_id,
          lord.tile_id,
          other_city.tile_id,
          other_lord.tile_id,
          warrior.tile_id
        ]

        [barb_tile | _] =
          context.world
          |> Fixtures.adjacent_tiles(warrior.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in occupied))

        clear_tile(context.world, barb_tile)
        barbarian = Fixtures.spawn_barbarian(context.world, barb_tile)

        [target_b | _] =
          context.world
          |> Fixtures.adjacent_tiles(barb_tile)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in [barb_tile | occupied]))

        clear_tile(context.world, target_b)
        :ok = Fixtures.relocate_unit(context.world, other_warrior.id, target_b)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == warrior.id, do: u

        [other_warrior] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == other_warrior.id,
              do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:other_play_live, other_play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:other_warrior, other_warrior)
         |> Map.put(:barbarian_id, barbarian.id)
         |> Map.put(:warrior_hp0, warrior.hp)
         |> Map.put(:other_warrior_hp0, other_warrior.hp)}
      end

      when_ "player one's warrior strikes the barbarian first", context do
        render_hook(context.play_live, "attack", %{
          "unit_id" => to_string(context.warrior.id),
          "target_unit_id" => to_string(context.barbarian_id)
        })

        assert_push_event(
          context.play_live,
          "game:combat",
          %{damage_dealt: dealt_a, damage_taken: taken_a},
          500
        )

        {:ok, context |> Map.put(:dealt_a, dealt_a) |> Map.put(:taken_a, taken_a)}
      end

      then_ "only player one's warrior takes the counter-blow — player two's is untouched",
            context do
        assert is_integer(context.taken_a) and context.taken_a > 0

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        [other_warrior] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.other_warrior.id,
              do: u

        assert warrior.hp == context.warrior_hp0 - context.taken_a
        assert other_warrior.hp == context.other_warrior_hp0

        {:ok,
         context
         |> Map.put(:warrior_hp_after_a, warrior.hp)
         |> Map.put(:other_warrior_hp_after_a, other_warrior.hp)}
      end

      when_ "player two's warrior then strikes the same, still-living barbarian", context do
        render_hook(context.other_play_live, "attack", %{
          "unit_id" => to_string(context.other_warrior.id),
          "target_unit_id" => to_string(context.barbarian_id)
        })

        assert_push_event(
          context.other_play_live,
          "game:combat",
          %{damage_dealt: dealt_b, damage_taken: taken_b},
          500
        )

        {:ok, context |> Map.put(:dealt_b, dealt_b) |> Map.put(:taken_b, taken_b)}
      end

      then_ "this time the counter lands only on player two — player one is unaffected by it",
            context do
        assert is_integer(context.taken_b) and context.taken_b > 0

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        [other_warrior] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.other_warrior.id,
              do: u

        assert warrior.hp == context.warrior_hp_after_a
        assert other_warrior.hp == context.other_warrior_hp_after_a - context.taken_b

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
