defmodule BrokenOathsSpex.Story893.Criterion7554Spex do
  @moduledoc """
  Story 893 — Barbarian Behavior
  Criterion 7554 — when both an undefended city and a player unit are
  candidate targets (both within 5 hexes), a barbarian's movement
  targets the city, not the unit. Per the Three Amigos notes on this
  story: "an undefended city is preferred as a target over player
  units — when both a city and a unit are candidates, the city wins."

  This story owns only target SELECTION (the barbarian's movement
  heads toward the city). Actually resolving a city attack — HP,
  garrison math, pillage-vs-destroy — belongs to story 895 (City
  Defense and Garrison), so "undefended" here just means "no unit is
  garrisoned on the city's own tile," and the observable proof is
  purely about which way the barbarian steps.

  Barbarian-fixture note: see criterion 7551's moduledoc — this uses a
  REAL camp-spawned warrior, one of the 1-2 camps that spawn already
  inside the player's own territory (criterion 7543).

  Second city, not the first: the first city's location relative to
  the camp is uncontrolled (wherever the settler happened to found),
  so it can't be guaranteed to sit within the 5-hex candidate range.
  A second city is grown deliberately at a controlled distance from
  the camp — the same "grow to size 2, produce a settler, march it
  out, found" sequence criterion 7544 (story 892) already established
  for a legitimate second founding.

  Equal-distance construction: both the city and the lord are placed
  at the SAME land-path distance (2 hexes) from the camp, in the two
  most mutually divergent directions available in that ring. This
  isolates the "city vs. unit" variable from "nearer wins" — if the
  barbarian simply always preferred whichever target was closer, this
  setup (a tie) would not produce a false pass.

  KNOWN LIMITATION (geometric): "most mutually divergent" is a
  best-effort search over the ring's candidates (maximizing pairwise
  land-path distance between the two chosen tiles), not a proof of
  true angular opposition — on a very narrow coastline the two targets
  could still share a first hop. See criterion 7541 (story 891) for
  the project's precedent of flagging this kind of statistical/
  geometric caveat rather than silently assuming it away.

  Inferred, not-yet-implemented shape: as in criterion 7551, this
  assumes each pushed warrior gains a `tile_id` field.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "they smell the undefended city" do
    scenario "a barbarian with both a city and a unit in range heads for the city" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player founded their first city, revealing a nearby barbarian camp",
             context do
        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})

        assert_push_event(play_live, "game:camps", %{camps: camps0})
        [camp | _] = camps0
        [city1] = Fixtures.player_cities(context.world, context.user)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city1, city1)
         |> Map.put(:camp_id, camp.id)
         |> Map.put(:camp_tile, camp.tile_id)
         |> Map.put(:camp_warrior_baseline_ids, MapSet.new(camp.warriors, & &1.id))}
      end

      given_ "a second, undefended city and the player's lord sit two hexes from the camp, in different directions",
             context do
        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        ring2 =
          Enum.reduce(1..2, {[context.camp_tile], MapSet.new([context.camp_tile])}, fn
            _, {frontier, seen} ->
              next =
                frontier
                |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
                |> Enum.uniq()
                |> Enum.filter(land?)
                |> Enum.reject(&MapSet.member?(seen, &1))

              {next, MapSet.union(seen, MapSet.new(next))}
          end)
          |> elem(0)

        {city_target, lord_target} = most_divergent_pair(context.world, ring2)

        # Grow the first city to size 2 (settlers need size >= 2),
        # produce a settler, march it out to `city_target`, found there.
        Enum.reduce_while(1..60, :ok, fn _, :ok ->
          [c] =
            for cc <- Fixtures.player_cities(context.world, context.user),
                cc.id == context.city1.id,
                do: cc

          if c.size >= 2 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        render_hook(context.play_live, "queue_production", %{
          "city_id" => to_string(context.city1.id),
          "item" => "settler"
        })

        for _ <- 1..20, do: Fixtures.advance_turn(context.world)

        [new_settler] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(new_settler.id),
          "to_tile" => city_target
        })

        Enum.reduce_while(1..30, :ok, fn _, :ok ->
          [s] =
            for u <- Fixtures.player_units(context.world, context.user),
                u.id == new_settler.id,
                do: u

          if s.tile_id == city_target do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        render_hook(context.play_live, "found_city", %{"unit_id" => to_string(new_settler.id)})

        [city2] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id != context.city1.id,
            do: c

        # Walk the lord to the divergent target — never onto the
        # city's own tile, or it would garrison it and break the
        # "undefended" precondition.
        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(lord.id),
          "to_tile" => lord_target
        })

        Enum.reduce_while(1..30, :ok, fn _, :ok ->
          [l] = for u <- Fixtures.player_units(context.world, context.user), u.id == lord.id, do: u

          if l.tile_id == lord_target do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [lord] = for u <- Fixtures.player_units(context.world, context.user), u.id == lord.id, do: u

        # Anchor: the city really is undefended (no unit garrisoned on
        # its own tile) and both candidates really did land at the
        # controlled, equal, non-adjacent distance from the camp.
        assert Enum.all?(Fixtures.player_units(context.world, context.user), &(&1.tile_id != city2.tile_id))
        assert city2.tile_id == city_target
        assert lord.tile_id == lord_target

        {:ok, context |> Map.put(:city2, city2) |> Map.put(:lord, lord)}
      end

      given_ "a barbarian warrior has spawned at the camp", context do
        warrior =
          Enum.reduce_while(1..12, nil, fn _turn, _acc ->
            Fixtures.advance_turn(context.world)
            assert_push_event(context.play_live, "game:camps", %{camps: camps}, 500)
            camp = Enum.find(camps, &(&1.id == context.camp_id))

            new_warrior =
              Enum.find(camp.warriors, &(&1.id not in context.camp_warrior_baseline_ids))

            if new_warrior, do: {:halt, new_warrior}, else: {:cont, nil}
          end)

        {:ok, Map.put(context, :barbarian, warrior)}
      end

      when_ "one more turn boundary passes", context do
        Fixtures.advance_turn(context.world)
        assert_push_event(context.play_live, "game:camps", %{camps: camps}, 500)
        camp = Enum.find(camps, &(&1.id == context.camp_id))
        barbarian_after = Enum.find(camp.warriors, &(&1.id == context.barbarian.id))

        {:ok, Map.put(context, :barbarian_after, barbarian_after)}
      end

      then_ "the barbarian's step brings it closer to the undefended city, not the lord", context do
        assert context.barbarian_after != nil

        assert context.barbarian_after.tile_id in Fixtures.adjacent_tiles(
                 context.world,
                 context.barbarian.tile_id
               )

        distance_to_city_before =
          land_distance(context.world, context.barbarian.tile_id, context.city2.tile_id)

        distance_to_city_after =
          land_distance(context.world, context.barbarian_after.tile_id, context.city2.tile_id)

        distance_to_lord_before =
          land_distance(context.world, context.barbarian.tile_id, context.lord.tile_id)

        distance_to_lord_after =
          land_distance(context.world, context.barbarian_after.tile_id, context.lord.tile_id)

        assert distance_to_city_after == distance_to_city_before - 1
        refute distance_to_lord_after < distance_to_lord_before

        {:ok, context}
      end
    end
  end

  # The two tiles in `ring` whose land-path distance from each other
  # is largest — a best-effort proxy for "most divergent directions
  # from the shared origin the ring was grown from."
  defp most_divergent_pair(world, ring) do
    {_distance, a, b} =
      for a <- ring, b <- ring, a != b do
        {land_distance(world, a, b, 12), a, b}
      end
      |> Enum.max_by(fn {d, _, _} -> d end)

    {a, b}
  end

  # Land-path hex distance via BFS over passable-land adjacency — the
  # same "how many hexes away" notion criterion 7534 (story 891) uses
  # for attack range, not the raw-mesh ring distance criterion 7543
  # uses for camp-placement bias.
  defp land_distance(world, from, to, max_depth \\ 10) do
    land? = fn t -> Fixtures.tile_class(world, t) == :land end

    0..max_depth
    |> Enum.reduce_while({[from], MapSet.new([from])}, fn depth, {frontier, seen} ->
      if to in frontier do
        {:halt, {:found, depth}}
      else
        next =
          frontier
          |> Enum.flat_map(&Fixtures.adjacent_tiles(world, &1))
          |> Enum.uniq()
          |> Enum.filter(land?)
          |> Enum.reject(&MapSet.member?(seen, &1))

        {:cont, {next, MapSet.union(seen, MapSet.new(next))}}
      end
    end)
    |> case do
      {:found, depth} -> depth
      _ -> 99
    end
  end
end
