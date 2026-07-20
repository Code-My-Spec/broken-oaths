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

  Setup-hardening (not in the original contract): the new settler and
  the lord used to WALK to their respective targets via `queue_move` +
  turn-boundary wait loops (up to 30 turns each), and the barbarian
  used to wait up to 12 MORE turns for the camp's natural spawn cadence
  — exposing an undefended settler and an escort-less lord right next
  to a live camp for potentially dozens of turns, which is exactly the
  kind of encounter this criterion wants to observe DETERMINISTICALLY
  (a controlled tie between two candidate targets), not risk losing to
  an unrelated ambush before its own setup even finishes.
  `Fixtures.relocate_unit/3` places both instantly; `Fixtures.
  spawn_barbarian/3` (tied to the same REAL, revealed camp, so `Turn`'s
  barbarian AI loop drives it for real — see criterion 7551's
  moduledoc) places the warrior directly on the camp's own tile — the
  same spawn-location a natural cadence would most commonly produce.
  Growing the first city to size 2 and banking a settler's production
  still take real turns (no shortcut exists for city-loop mechanics),
  but neither city1 nor its citizens are exposed anywhere near the
  target camp during that wait.

  Re-anchored (this world's OTHER camps eliminated, not tolerated):
  measured independently at a 60% failure rate — this world always
  ships with several OTHER, independently-roaming real camps besides
  the one this criterion tracks (criterion 7543), and `BarbarianAI.
  step_toward/4` correctly refuses to route THROUGH a tile another
  unit currently holds. On a routine (not rare) fraction of runs, one
  of those unrelated warriors sat on the tracked barbarian's single
  shortest-path hex toward city2, or wandered onto `city_target`/
  `lord_target` themselves, throwing off this criterion's exact
  "one hex closer, this boundary" and "unoccupied by construction"
  assertions — a real result of a genuinely live, multi-camp world,
  but irrelevant to what this criterion actually tests (ONE camp's own
  target-selection decision). `Fixtures.isolate_camp/2` (new,
  narrow, documented-bridge status — see `BrokenOaths.Simulation.WorldServer`'s
  `:isolate_camp_for_test` handler) destroys every OTHER camp and
  hard-deletes their warriors the moment the tracked camp is known —
  before city1 even starts growing — so no other actor exists to
  interfere for the rest of this scenario. The tracked camp itself is
  untouched and still spawns/decides for real.

  "game:camps" is content-diffed against its last-pushed value (QA
  issue dbcbd478): a tick/production event only re-pushes when the
  camp SET itself actually changed, so the long growth/production/
  march waits below no longer assume exactly one push per action —
  `drain_events/2` flushes whatever DID accumulate (zero, one, or
  several) without asserting a count, and the one meaningful read at
  the end (`when_`) trusts the mailbox is clean going in.
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

        # Eliminate every OTHER camp right away, before any wait even
        # starts — see this module's doc: this criterion's SUBJECT is
        # ONE camp's own target-selection decision (city vs. unit), not
        # whether it survives incidental interference from the several
        # OTHER camps this world always ships with (criterion 7543).
        :ok = Fixtures.isolate_camp(context.world, camp.id)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city1, city1)
         |> Map.put(:camp_id, camp.id)
         |> Map.put(:camp_tile, camp.tile_id)}
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

        # The lord first, and BEFORE any turn passes: once it's standing
        # on `lord_target`, nothing else can ever land there (one unit
        # per hex), so there's no later occupancy race to retry against
        # — unlike the settler below, which doesn't exist until city1
        # finishes producing it, dozens of turns from now.
        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        :ok = Fixtures.relocate_unit(context.world, lord.id, lord_target)
        [lord] = for u <- Fixtures.player_units(context.world, context.user), u.id == lord.id, do: u

        # Grow the first city to size 2 (settlers need size >= 2),
        # produce a settler, place it directly on `city_target`, found
        # there. Content-diffed "game:camps" (QA issue dbcbd478) only
        # re-pushes when the camp SET actually changes, so not every
        # tick here is guaranteed to produce one — `drain_events/2`
        # flushes whatever DOES accumulate (rather than asserting an
        # exact count) so it never piles up stale messages ahead of the
        # scenario's own later, meaningful read.
        Enum.reduce_while(1..60, :ok, fn _, :ok ->
          [c] =
            for cc <- Fixtures.player_cities(context.world, context.user),
                cc.id == context.city1.id,
                do: cc

          if c.size >= 2 do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            drain_events(context.play_live, "game:camps")
            {:cont, :ok}
          end
        end)

        # `queue_production`/`found_city` each broadcast `:cities_changed`
        # too (not just a tick's own `:turn_advanced`), which MAY also
        # trigger a "game:camps" push if the camp set changed since the
        # last one — drain whatever's there, same reasoning as the tick
        # loop above.
        render_hook(context.play_live, "queue_production", %{
          "city_id" => to_string(context.city1.id),
          "item" => "settler"
        })

        drain_events(context.play_live, "game:camps")

        for _ <- 1..20 do
          Fixtures.advance_turn(context.world)
          drain_events(context.play_live, "game:camps")
        end

        [new_settler] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        # `city_target` has had ~80 turns of real, roaming barbarian
        # traffic to wander through by now (unlike the lord's own spot,
        # claimed before any of that started) — retry the relocate a
        # few boundaries if something is momentarily standing on it,
        # rather than assuming it's still free.
        :ok = relocate_when_free(context.world, context.play_live, new_settler.id, city_target)
        render_hook(context.play_live, "found_city", %{"unit_id" => to_string(new_settler.id)})
        drain_events(context.play_live, "game:camps")

        [city2] =
          for c <- Fixtures.player_cities(context.world, context.user), c.id != context.city1.id,
            do: c

        # Anchor: the city really is undefended (no unit garrisoned on
        # its own tile) and both candidates really did land at the
        # controlled, equal, non-adjacent distance from the camp.
        assert Enum.all?(Fixtures.player_units(context.world, context.user), &(&1.tile_id != city2.tile_id))
        assert city2.tile_id == city_target
        assert lord.tile_id == lord_target

        {:ok, context |> Map.put(:city2, city2) |> Map.put(:lord, lord)}
      end

      given_ "a barbarian warrior stands at the camp", context do
        # `Fixtures.clear_camp_warriors/2` guarantees zero pre-existing
        # warriors anywhere in the world at this point — including this
        # SAME (tracked, never-isolated) camp's own natural spawn
        # cadence, which otherwise has ~80 real turns to accumulate a
        # sibling warrior before this deliberate placement even happens.
        # With every other camp already eliminated (previous given_) and
        # this camp's own board cleared, spawning directly on
        # `camp_tile` itself needs no occupancy search or "too close"
        # fallback anymore — it's exactly 2 hexes from both
        # `city_target` and `lord_target` by construction, and nothing
        # else exists to land there instead.
        Fixtures.clear_camp_warriors(context.world, context.camp_id)
        warrior = Fixtures.spawn_barbarian(context.world, context.camp_tile, context.camp_id)
        {:ok, Map.put(context, :barbarian, warrior)}
      end

      when_ "one more turn boundary passes", context do
        # The long setup above leaves `play_live`'s "game:camps" mailbox
        # clean (every accumulated push was drained as it came) — this
        # turn boundary is the first one since, and the barbarian's own
        # step changes its `tile_id` inside the pushed payload, so a
        # fresh push is guaranteed here.
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

  # `Fixtures.relocate_unit/3`, retried across a few turn boundaries if
  # the target is momentarily held by a roaming barbarian — much
  # smaller exposure than the multi-turn march this replaces, since the
  # unit being placed doesn't exist (or doesn't need to be anywhere in
  # particular) until right before this call. Drains each retry's own
  # "game:camps" push, if any (same reasoning as the wait loops above)
  # so it never piles up stale messages ahead of a later assertion
  # either.
  defp relocate_when_free(world, play_live, unit_id, tile_id, retries \\ 10)
  defp relocate_when_free(_world, _play_live, _unit_id, _tile_id, 0), do: {:error, :occupied}

  defp relocate_when_free(world, play_live, unit_id, tile_id, retries) do
    case Fixtures.relocate_unit(world, unit_id, tile_id) do
      :ok ->
        :ok

      {:error, :occupied} ->
        Fixtures.advance_turn(world)
        drain_events(play_live, "game:camps")
        relocate_when_free(world, play_live, unit_id, tile_id, retries - 1)
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
