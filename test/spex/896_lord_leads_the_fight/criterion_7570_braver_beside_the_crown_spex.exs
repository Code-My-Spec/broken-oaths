defmodule BrokenOathsSpex.Story896.Criterion7570Spex do
  @moduledoc """
  Story 896 — Lord Leads the Fight
  Criterion 7570 — the lord's +2 strength aura applies on defense, not
  just attack: my warrior (strength 10, +2 lord aura = effective 12)
  defending against a barbarian warrior's attack (strength 15) should
  fight back from the strength-12 band, not the plain strength-10
  band.

  This is the DEFENSE half of the aura rule. Story 891's criterion
  7541 already covers the ATTACK half (an aura'd unit attacking); this
  spec swaps attacker/defender roles — the barbarian is the attacker
  here, my warrior the defender — and observes the same underlying
  formula through the defender's counter-damage (criterion 7538,
  story 891, already establishes counter-damage is real and computed
  from pre-combat stats, so "fights back" is exactly that).

  Barbarian-fixture note: see `BrokenOathsSpex.Story891.Criterion7533Spex`'s
  moduledoc — the barbarian is a real, ownerless unit placed via
  `Fixtures.spawn_barbarian/2`. Story 893 (barbarian roaming/AI)
  doesn't exist yet, so there's no player session to drive an attack
  FROM it through the ordinary "attack" event — the barbarian is the
  attacker here, so this resolves the exchange directly via
  `Fixtures.resolve_barbarian_attack/3` instead.

  KNOWN LIMITATION (statistical): same caveat as criterion 7541 — the
  strength-10 band (~18 to 31, criterion 7537) and the strength-12
  band computed here (~20 to 33) overlap, so a single random roll
  can't conclusively rule out "got lucky within the strength-10 band."
  This spec asserts membership in the strength-12 band, the same
  literal encoding criterion 7541 uses for the attack side.

  My lord is walked next to my warrior's landed position — spawn
  adjacency gives no guarantee either unit lands next to the other, so
  this is engineered with a real move (`queue_move`), the same
  approach criterion 7541 uses.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "braver beside the crown" do
    scenario "the warrior's counter-damage comes from the strength-12 band when the lord stands beside it" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my warrior stands adjacent to my lord when a barbarian attacks it", context do
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

        for _ <- 1..8, do: Fixtures.advance_turn(context.world)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        my_occupied = [city.tile_id, lord.tile_id, warrior.tile_id]

        [barbarian_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(warrior.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in my_occupied))

        barbarian = Fixtures.spawn_barbarian(context.world, barbarian_target)

        # Bring the lord to a free tile adjacent to my warrior — not
        # already the barbarian's tile or the warrior's own tile.
        [lord_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(warrior.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in [city.tile_id, warrior.tile_id, barbarian.tile_id, lord.tile_id]))

        walk_to(context.world, play_live, context.user, lord.id, lord_target)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:barbarian, barbarian)
         |> Map.put(:barbarian_hp0, barbarian.hp)}
      end

      when_ "the combat resolves", context do
        {:ok, _result} =
          Fixtures.resolve_barbarian_attack(context.world, context.barbarian.id, context.warrior.id)

        {:ok, context}
      end

      then_ "the warrior fights back from the strength-12 band, not the strength-10 band",
            context do
        [barbarian] =
          for u <- Fixtures.visible_units(context.world, context.user),
              u.id == context.barbarian.id,
              do: u

        dealt = context.barbarian_hp0 - barbarian.hp

        # 30 * e^(0.04 * (12 - 15)) ± 25% ≈ [19.96, 33.26]
        assert dealt >= 20 and dealt <= 33
        {:ok, context}
      end
    end
  end

  # Walks `unit_id` (owned by `owner`, driven through `live_view`) to
  # `to_tile`, advancing turn boundaries until it arrives — the same
  # immediate-then-recharge movement pattern every spec in story 891
  # relies on (see `BrokenOathsSpex.Story891.Criterion7575Spex`'s
  # identical helper).
  defp walk_to(world, live_view, owner, unit_id, to_tile, max_turns \\ 40) do
    render_hook(live_view, "queue_move", %{"unit_id" => unit_id, "to_tile" => to_tile})

    Enum.reduce_while(1..max_turns, :ok, fn _, :ok ->
      [u] = for uu <- Fixtures.player_units(world, owner), uu.id == unit_id, do: uu

      if u.tile_id == to_tile do
        {:halt, :ok}
      else
        Fixtures.advance_turn(world)
        {:cont, :ok}
      end
    end)
  end
end
