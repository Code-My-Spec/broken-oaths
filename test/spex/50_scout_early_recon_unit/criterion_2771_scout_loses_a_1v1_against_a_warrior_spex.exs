defmodule BrokenOathsSpex.Story952.Criterion2771Spex do
  @moduledoc """
  Story 952 — Scout — early recon unit
  Criterion 2771 — a Scout (strength 5) loses a 1v1 against a Warrior
  (`Combat.Resolver.base_strength(:barbarian_warrior)` = 15, the same
  barbarian "Warrior" opponent `BrokenOathsSpex.Story891.Criterion7537Spex`
  already established for this identical scenario shape).

  Attacking a rival PLAYER's own Warrior directly is not a legal setup
  for this criterion: `Combat.Resolver.hostile?/2` is `false` for any
  two real players by default ("no PvP in the Stone Age", LOCKED —
  `BrokenOathsSpex.Story899.Criterion7603Spex`), so `validate_pvp_attack/4`
  would reject the exchange as `{:error, :not_hostile}` — silently, no
  crash, both units' HP untouched. A barbarian has `player_id: nil`,
  which `hostile?/2` always allows, and it's still literally a "Warrior"
  unit type, satisfying the criterion's own wording without requiring a
  war/vassalage relationship that's out of scope for a unit-strength
  comparison.

  Setup-hardening (same class of problem `Criterion7537Spex`'s own
  `ensure_lord_away/5` exists to prevent, extended to garrison too):
  `resolve_attack/3` derives `attacker_aura?`/`attacker_garrisoned?`
  LIVE from real game state — a living, same-player lord adjacent to
  the Scout adds `Resolver.@lord_aura_bonus` (2), and the Scout
  standing on its own city's tile (a completed unit's default landing
  tile when free) multiplies by `Resolver.@garrison_bonus` (1.5). Both
  would silently corrupt the plain, no-modifier strength-5 band this
  criterion asserts — combined, they alone can push the Scout's
  effective attacking strength past 10, well outside the plain-5 curve.
  The Scout is relocated off the city tile (avoiding garrison) and the
  Lord is walked out of adjacency range of the Scout's final position
  (avoiding aura) before the barbarian ever spawns.

  Unit-vs-unit combat rolls a ±25% Civ VI curve around a
  strength-derived band (unlike the flat, no-roll camp damage), with
  the final damage `round/1`-ed (`Resolver.damage/3`'s own last pipe
  step) to an integer. "Loses" is encoded as each side's own absolute
  damage band, NOT a relative comparison
  (`scout_damage_taken > barbarian_damage_taken`) — the two damage
  rolls are independent (`Resolver.damage/3`'s `roll_seed` differs per
  direction), so a relative comparison could in principle flip on
  unlucky rolls even when the combat math is correct. Bands computed
  precisely from the exact formula (`@base_damage` 30, `@damage_scale`
  0.04, roll uniform in [0.75, 1.25)) for the plain Scout(5) vs
  barbarian Warrior(15) gap, then rounded the same way `damage/3`
  itself rounds:

      striking->resisting  base * exp(scale * Δ)   * roll range      = damage range
      Scout(5)->barb(15):  30 * exp(0.04*-10) ≈ 20.11 * [0.75,1.25) ≈ [15.08, 25.14) -> 15..25
      barb(15)->Scout(5):  30 * exp(0.04*10)  ≈ 44.75 * [0.75,1.25) ≈ [33.57, 55.94) -> 34..56

  These are two SEPARATE quantities (different exponent sign, not two
  slices of one continuous range) — a gap between 25 and 34 is
  expected and correct, not a hole in coverage.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Scout loses a 1v1 against a Warrior", fail_on_error_logs: false do
    scenario "the Scout takes the heavier hit back" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city)

      given_ "my Scout stands adjacent to a barbarian Warrior, clear of any garrison or lord-aura bonus",
             context do
        render_hook(context.play_live, "queue_production", %{
          "city_id" => context.city.id,
          "item" => "scout"
        })

        Enum.reduce_while(1..15, :ok, fn _, :ok ->
          if Enum.any?(Fixtures.player_units(context.world, context.user), &(&1.type == :scout)) do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [scout] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :scout, do: u

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        # Avoid the garrison bonus (story 895): move the Scout off the
        # city's own tile first, same sanctioned bridge story 893's
        # specs already use.
        [scout_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(context.city.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in [lord.tile_id]))

        :ok = Fixtures.relocate_unit(context.world, scout.id, scout_target)

        [scout] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == scout.id, do: u

        # Avoid the lord's aura bonus: walk the lord clear if it landed
        # adjacent to the Scout's new position (see moduledoc).
        lord =
          ensure_lord_away(
            context.world,
            context.play_live,
            context.user,
            lord,
            scout.tile_id,
            context.city.tile_id
          )

        my_occupied = [context.city.tile_id, lord.tile_id, scout.tile_id]

        [target | _] =
          context.world
          |> Fixtures.adjacent_tiles(scout.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in my_occupied))

        barbarian = Fixtures.spawn_barbarian(context.world, target)

        {:ok,
         context
         |> Map.put(:scout, scout)
         |> Map.put(:barbarian, barbarian)
         |> Map.put(:scout_hp0, scout.hp)
         |> Map.put(:barbarian_hp0, barbarian.hp)}
      end

      when_ "my Scout attacks the Warrior", context do
        render_hook(context.play_live, "attack", %{
          "unit_id" => to_string(context.scout.id),
          "target_unit_id" => to_string(context.barbarian.id)
        })

        {:ok, context}
      end

      then_ "the strength-gap curve puts the Warrior's damage in the weaker band (15 to 25) and the Scout's own damage in the stronger band (34 to 56)",
            context do
        [scout] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == context.scout.id,
            do: u

        [barbarian] =
          for u <- Fixtures.visible_units(context.world, context.user),
              u.id == context.barbarian.id,
              do: u

        scout_damage_taken = context.scout_hp0 - scout.hp
        barbarian_damage_taken = context.barbarian_hp0 - barbarian.hp

        assert barbarian_damage_taken >= 15 and barbarian_damage_taken <= 25,
               "expected the Warrior's own damage taken (#{barbarian_damage_taken}) in the weaker band (15-25)"

        assert scout_damage_taken >= 34 and scout_damage_taken <= 56,
               "expected the Scout's own damage taken (#{scout_damage_taken}) in the stronger band (34-56)"

        {:ok, context}
      end
    end
  end

  # If `lord` already stands adjacent to `avoid_tile`, walks it to a
  # free land tile two hexes out and returns the lord's up-to-date unit
  # map; otherwise returns `lord` unchanged. Same helper
  # `BrokenOathsSpex.Story891.Criterion7537Spex` already established.
  defp ensure_lord_away(world, live_view, user, lord, avoid_tile, city_tile) do
    ring1 = world |> Fixtures.adjacent_tiles(avoid_tile) |> MapSet.new()

    if MapSet.member?(ring1, lord.tile_id) do
      land? = fn t -> Fixtures.tile_class(world, t) == :land end

      [safe_tile | _] =
        ring1
        |> Enum.flat_map(&Fixtures.adjacent_tiles(world, &1))
        |> Enum.uniq()
        |> Enum.reject(&(MapSet.member?(ring1, &1) or &1 in [avoid_tile, city_tile, lord.tile_id]))
        |> Enum.filter(land?)

      render_hook(live_view, "queue_move", %{"unit_id" => lord.id, "to_tile" => safe_tile})
      wait_until_arrived(world, user, lord.id, safe_tile)
    else
      lord
    end
  end

  # Advances turns until `unit_id` reports `target_tile`, then returns
  # its up-to-date unit map. Extracted out of `ensure_lord_away/6` to
  # keep that function's own nesting within the project's max-depth-2
  # convention.
  defp wait_until_arrived(world, user, unit_id, target_tile) do
    _result =
      Enum.reduce_while(1..10, :ok, fn _, :ok ->
        [u] = for unit <- Fixtures.player_units(world, user), unit.id == unit_id, do: unit

        if u.tile_id == target_tile do
          {:halt, :ok}
        else
          Fixtures.advance_turn(world)
          {:cont, :ok}
        end
      end)

    [u] = for unit <- Fixtures.player_units(world, user), unit.id == unit_id, do: unit
    u
  end
end
