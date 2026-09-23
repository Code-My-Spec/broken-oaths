defmodule BrokenOathsSpex.Story39.Criterion3636Spex do
  @moduledoc """
  Story 39 — Fortify a unit for a defensive bonus
  Criterion 3636 — Fortify applies immediately, same turn: no dig-in
  delay, and a defensive exchange resolved later in that SAME turn
  already carries the bonus.

  My Warrior (base strength 10, `BrokenOaths.Combat.Resolver.
  base_strength/1`) fortifies with `render_hook("fortify", ...)`, then
  — with no `advance_turn` in between — a real barbarian strikes it via
  `Fixtures.resolve_barbarian_attack/3`. `fortified_turns` is 1 right
  after `fortify/3` fires (the PARTIAL ramp level, `Combat.Resolver`'s
  own "Fortify" doc), never 0 first: `effective_strength/4`'s
  `fortify_bonus/2` already reads `round(10 * 0.25) = 3` the instant
  it's called, with no separate "turn boundary" gate anywhere in that
  path. Lord relocated well clear of both units first (same hardening
  as criteria 7565/7571) so the aura bonus doesn't pollute the
  strength this criterion isolates.

  Expected damage band, defender strength 10 + 3 (partial fortify) = 13
  at full HP, attacker (barbarian) strength 15, no bonuses either side:
  `30 × e^(0.04 × (15-13)) × [0.75, 1.25]` ≈ `[24.37, 40.62]`, the same
  Civ-VI-style damage curve criteria 7565/7571 already establish.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "fortify applies immediately, same turn" do
    scenario "a warrior fortifies and is struck by a barbarian in the same turn" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my unfortified warrior stands beside a barbarian, no lord aura nearby", context do
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

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        [warrior_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(city.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 == lord.tile_id))

        :ok = Fixtures.relocate_unit(context.world, warrior.id, warrior_target)
        [warrior] = for u <- Fixtures.player_units(context.world, context.user), u.id == warrior.id, do: u

        far_tile =
          context.world
          |> ring_tiles(city.tile_id, 3)
          |> Enum.filter(&(Fixtures.tile_class(context.world, &1) == :land))
          |> List.first()

        :ok = Fixtures.relocate_unit(context.world, lord.id, far_tile)

        [barbarian_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(warrior.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in [city.tile_id, warrior.tile_id]))

        barbarian = Fixtures.spawn_barbarian(context.world, barbarian_target)

        render_hook(play_live, "select_unit", %{"unit_id" => to_string(warrior.id)})

        refute has_element?(play_live, "[data-test='unit-fortified']")

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:barbarian, barbarian)
         |> Map.put(:barbarian_hp0, barbarian.hp)}
      end

      when_ "the player fortifies, and the barbarian strikes back in that same turn", context do
        render_hook(context.play_live, "fortify", %{"unit_id" => to_string(context.warrior.id)})

        {:ok, _} =
          Fixtures.resolve_barbarian_attack(context.world, context.barbarian.id, context.warrior.id)

        {:ok, context}
      end

      then_ "the unit's stance is fortified immediately, shown by the real panel", context do
        assert has_element?(context.play_live, "[data-test='unit-fortified']")
        {:ok, context}
      end

      then_ "the same-turn defensive exchange already reflects the partial bonus", context do
        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        dealt = 100 - warrior.hp

        # 30 * e^(0.04 * (15-13)) * [0.75, 1.25] ≈ [24.37, 40.62]
        assert dealt >= 24 and dealt <= 41
        {:ok, context}
      end
    end
  end

  # Every land tile whose raw mesh-adjacency distance from `start` is
  # exactly `depth` — same BFS-ring idiom criteria 7565/7571 already use.
  defp ring_tiles(world, start, depth) do
    Enum.reduce(1..depth, {[start], MapSet.new([start])}, fn _, {frontier, seen} ->
      next =
        frontier
        |> Enum.flat_map(&Fixtures.adjacent_tiles(world, &1))
        |> Enum.uniq()
        |> Enum.reject(&MapSet.member?(seen, &1))

      {next, MapSet.union(seen, MapSet.new(next))}
    end)
    |> elem(0)
  end
end
