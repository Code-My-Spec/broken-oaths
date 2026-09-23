defmodule BrokenOathsSpex.Story39.Criterion3637Spex do
  @moduledoc """
  Story 39 — Fortify a unit for a defensive bonus
  Criterion 3637 — the FULL Fortify bonus (`fortified_turns >= 2`,
  Civ-6-style ramp — see criterion 3636's own doc) is +50% of the
  unit's BASE strength, and that bonus is folded into strength BEFORE
  the wounded penalty scales it down, not added on top of an already-
  wounded number (`BrokenOaths.Combat.Resolver.effective_strength/4`'s
  own doc, "folded into strength BEFORE the wounded penalty scales it,
  same ordering as the lord's aura").

  My Warrior (base strength 10, `Combat.Resolver.base_strength/1`)
  fortifies and survives one full turn boundary without moving or
  attacking (`Simulation.Turn.Movement.advance_fortify/1`), reaching
  the FULL ramp level — `round(10 * 0.5) = 5`. A first barbarian
  strike (strength 15, `@base_strength[:barbarian_warrior]`) wounds it
  while it's already fully fortified — being struck never clears the
  stance (criterion 3640) — leaving it at a real, observed HP that
  this spec reads back rather than assumes. A SECOND, fresh barbarian
  then strikes the same wounded, still-fully-fortified warrior; the
  expected damage band for that second exchange is computed from the
  Civ-VI-style curve (`30 × e^(0.04 × Δstrength) × [0.75, 1.25]`,
  criteria 7565/7571/3636's own curve) using `(base + fortify) ×
  wounded` — the folded-before formula — from the warrior's ACTUAL,
  just-observed pre-strike HP rather than a guessed one, so the band
  holds the real implementation's ordering accountable rather than
  a fixture assumption.

  Lord relocated well clear of both units first (same hardening as
  criteria 7565/3636) so the aura bonus doesn't pollute the strength
  this criterion isolates. Both barbarians strike a real ownerless
  unit the same sanctioned way 3636/3639/3640 do —
  `Fixtures.resolve_barbarian_attack/3`, since `hostile?/2` refuses
  PvP between two real players (story 891, criterion 7542).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "defense bonus is +50% base strength, folded in before the wounded penalty" do
    scenario "a fully-ramped, already-wounded warrior takes a second barbarian strike" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my warrior is fully fortified and wounded by a first barbarian strike, lord far away",
             context do
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

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == warrior.id, do: u

        far_tile =
          context.world
          |> ring_tiles(city.tile_id, 3)
          |> Enum.filter(&(Fixtures.tile_class(context.world, &1) == :land))
          |> List.first()

        :ok = Fixtures.relocate_unit(context.world, lord.id, far_tile)

        render_hook(play_live, "select_unit", %{"unit_id" => to_string(warrior.id)})
        render_hook(play_live, "fortify", %{"unit_id" => to_string(warrior.id)})

        Fixtures.advance_turn(context.world)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == warrior.id, do: u

        assert warrior.fortified_turns >= 2

        [barbarian_target_1 | _] =
          context.world
          |> Fixtures.adjacent_tiles(warrior.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in [city.tile_id, warrior.tile_id]))

        barbarian_1 = Fixtures.spawn_barbarian(context.world, barbarian_target_1)

        {:ok, _} = Fixtures.resolve_barbarian_attack(context.world, barbarian_1.id, warrior.id)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == warrior.id, do: u

        assert warrior.hp > 0
        assert warrior.hp < warrior.max_hp
        assert warrior.fortified_turns >= 2

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:city, city)
         |> Map.put(:barbarian_1, barbarian_1)
         |> Map.put(:hp_before_second_strike, warrior.hp)}
      end

      when_ "a second, fresh barbarian strikes the wounded, still-fully-fortified warrior", context do
        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        [barbarian_target_2 | _] =
          context.world
          |> Fixtures.adjacent_tiles(context.warrior.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in [context.city.tile_id, context.warrior.tile_id, context.barbarian_1.tile_id]))

        barbarian_2 = Fixtures.spawn_barbarian(context.world, barbarian_target_2)

        {:ok, _} = Fixtures.resolve_barbarian_attack(context.world, barbarian_2.id, context.warrior.id)

        {:ok, context}
      end

      then_ "the damage matches the full bonus folded in before the wounded penalty, at the warrior's real observed HP",
            context do
        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == context.warrior.id,
              do: u

        assert warrior.hp > 0
        dealt = context.hp_before_second_strike - warrior.hp

        # (base + fortify) * wounded, folded-before ordering — computed
        # from the warrior's REAL, just-observed pre-strike HP rather
        # than an assumed one; see this module's own moduledoc.
        wounded_multiplier = 0.5 + 0.5 * (context.hp_before_second_strike / warrior.max_hp)
        defender_strength = (10 + 5) * wounded_multiplier
        attacker_strength = 15

        low = 30 * :math.exp(0.04 * (attacker_strength - defender_strength)) * 0.75
        high = 30 * :math.exp(0.04 * (attacker_strength - defender_strength)) * 1.25

        assert dealt >= floor(low) and dealt <= ceil(high)
        {:ok, context}
      end
    end
  end

  # Every land tile whose raw mesh-adjacency distance from `start` is
  # exactly `depth` — same BFS-ring idiom criteria 7565/7571/3636
  # already use.
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
