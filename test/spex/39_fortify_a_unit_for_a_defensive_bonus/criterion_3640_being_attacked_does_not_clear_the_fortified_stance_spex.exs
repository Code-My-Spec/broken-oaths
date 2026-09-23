defmodule BrokenOathsSpex.Story39.Criterion3640Spex do
  @moduledoc """
  Story 39 — Fortify a unit for a defensive bonus
  Criterion 3640 — being attacked does NOT clear a unit's Fortify
  stance (only the fortified unit's own move or attack does — see
  criteria 3638/3639).

  A full-HP Warrior fortifies, then a real barbarian (`Fixtures.
  spawn_barbarian/2`, an ownerless unit — `Combat.Resolver.hostile?/2`'s
  own seam) strikes it via `Fixtures.resolve_barbarian_attack/3`, the
  sanctioned direct-resolution bridge for an attack with no player
  session on the attacking side. "Regardless of outcome" is read as
  "whether the defender loses HP or not" — a full-HP Warrior (100 hp)
  cannot be killed by one barbarian strike (max single-hit damage is
  well under 100 even unfortified), so both a hit and, in the rare case
  the random band rolls a near-miss, a light graze are covered by the
  same single real exchange; outright death is a different exchange
  (many hits) outside what one attack can produce here.
  `Simulation.Turn.Movement.apply_positions/3` and `Combat.Resolver.
  resolve_attack/4`'s own reset only ever fire for the unit's own move
  or attack — nothing on the incoming-damage path touches
  `fortified_turns` at all, which is exactly the absence this criterion
  checks for.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "being attacked does not clear the fortified stance" do
    scenario "a fortified warrior is struck by an adjacent barbarian" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my fortified warrior stands adjacent to a barbarian", context do
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

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        occupied_tiles =
          for u <- Fixtures.player_units(context.world, context.user), u.id != warrior.id, do: u.tile_id

        [warrior_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(city.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in occupied_tiles))

        :ok = Fixtures.relocate_unit(context.world, warrior.id, warrior_target)
        [warrior] = for u <- Fixtures.player_units(context.world, context.user), u.id == warrior.id, do: u

        [barbarian_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(warrior.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in [city.tile_id, warrior.tile_id]))

        barbarian = Fixtures.spawn_barbarian(context.world, barbarian_target)

        render_hook(play_live, "select_unit", %{"unit_id" => to_string(warrior.id)})
        render_hook(play_live, "fortify", %{"unit_id" => to_string(warrior.id)})

        assert has_element?(play_live, "[data-test='unit-fortified']")

        {:ok,
         context
         |> Map.put(:world_after_join, context.world)
         |> Map.put(:warrior, warrior)
         |> Map.put(:barbarian, barbarian)}
      end

      when_ "the barbarian strikes the fortified warrior", context do
        {:ok, _} = Fixtures.resolve_barbarian_attack(context.world, context.barbarian.id, context.warrior.id)
        {:ok, context}
      end

      then_ "the warrior's fortified stance remains, whatever the exchange did to its HP", context do
        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        assert warrior.fortified_turns > 0
        assert warrior.hp > 0
        {:ok, context}
      end
    end
  end
end
