defmodule BrokenOathsSpex.Story896.Criterion7571Spex do
  @moduledoc """
  Story 896 — Lord Leads the Fight
  Criterion 7571 — the lord's +2 strength aura has a range limit: at 2
  hexes (not adjacent), it grants nothing. My warrior (strength 10)
  attacking a barbarian warrior (strength 15) while 2 hexes from my
  lord should deal damage from the plain strength-10 band — the same
  band criterion 7537 (story 891) establishes as the no-aura baseline
  — not the strength-12 band criteria 7541 (story 891) and 7570 (this
  story) establish for an adjacent lord.

  Barbarian-fixture note: see `BrokenOathsSpex.Story891.Criterion7533Spex`'s
  moduledoc — the barbarian is a real, ownerless unit placed via
  `Fixtures.spawn_barbarian/2`.

  KNOWN LIMITATION (statistical): same overlapping-band caveat as
  criterion 7541/7570 — the strength-10 band (~18-31) and strength-12
  band (~20-33) overlap, so a single roll can't conclusively separate
  them. This spec asserts membership in the strength-10 band, the
  most literal single-scenario encoding of "no bonus applies"
  available without a deterministic-roll test hook.

  My lord is walked to a tile exactly two hex-steps from my warrior —
  a real move (`queue_move`), not a fixture trick, the same
  engineering criterion 7541/7570 use for the adjacent case. The
  distance-2 ring is built by taking my warrior's immediate neighbors
  (ring 1) and growing outward one more step, then excluding ring 1
  and the warrior's own tile — so nothing chosen is accidentally still
  adjacent.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the aura has an edge" do
    scenario "the warrior's damage comes from the strength-10 band when the lord is two hexes away" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my warrior stands 2 hexes from my lord and fights a barbarian", context do
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

        # Distance-2 ring: grow one hop past my warrior's own neighbors
        # (ring 1), then drop ring 1 itself and the warrior's own tile
        # so nothing chosen is accidentally still adjacent.
        ring1 =
          context.world
          |> Fixtures.adjacent_tiles(warrior.tile_id)
          |> MapSet.new()

        far_occupied = [city.tile_id, warrior.tile_id, barbarian.tile_id, lord.tile_id]

        [lord_target | _] =
          ring1
          |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
          |> Enum.uniq()
          |> Enum.reject(&(MapSet.member?(ring1, &1) or &1 == warrior.tile_id))
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in far_occupied))

        walk_to(context.world, play_live, context.user, lord.id, lord_target)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:barbarian, barbarian)
         |> Map.put(:barbarian_hp0, barbarian.hp)}
      end

      when_ "it fights a barbarian", context do
        render_hook(context.play_live, "attack", %{
          "unit_id" => to_string(context.warrior.id),
          "target_unit_id" => to_string(context.barbarian.id)
        })

        {:ok, context}
      end

      then_ "no +2 bonus applies", context do
        [barbarian] =
          for u <- Fixtures.visible_units(context.world, context.user),
              u.id == context.barbarian.id,
              do: u

        dealt = context.barbarian_hp0 - barbarian.hp

        # 30 * e^(0.04 * (10 - 15)) ± 25% ≈ [18.44, 30.73]
        assert dealt >= 18 and dealt <= 31
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
