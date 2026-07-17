defmodule BrokenOathsSpex.Story893.Criterion7551Spex do
  @moduledoc """
  Story 893 — Barbarian Behavior
  Criterion 7551 — at each turn boundary, a barbarian warrior moves
  exactly 1 hex toward the nearest player unit or city within 5 hexes.

  Barbarian-fixture note: unlike story 891's stand-in barbarians, this
  story is exactly the one that gives barbarians their own targeting
  and movement, so this spec uses a REAL, AI-controlled warrior. It's
  placed via `Fixtures.spawn_barbarian/3` (the same test-only bridge
  story 891's criterion 7533 uses, extended with a REAL camp's id so
  `Turn`'s barbarian AI loop drives it for real — see that function's
  doc) rather than waiting on a camp's natural 3-turn spawn cadence and
  then marching the lord to find it. That march used to take dozens of
  turns through a live, hostile world (multiple real camps exist the
  moment the first city is founded) for something this criterion has
  no opinion on — where the lord starts, or how long the walk takes —
  only that a real, camp-owned warrior steps exactly one hex closer
  once it's within range.

  Setup-hardening (not in the original contract): the lord's own
  natural spawn tile has no guaranteed relationship to a near camp's
  tile — criterion 7552 explicitly anchors the OPPOSITE ("everything
  the player owns sits beyond the camp's 5-hex aggro range") as the
  default, unremarkable case. `barbarian_ai.ex`'s leash (kept, by
  design) only ever lets a warrior move toward a target that itself
  sits within leash range of ITS OWN camp, so a target this criterion
  needs "within hunting range" of would silently never be hunted if
  the lord stayed at its natural, usually-too-distant spawn tile.
  `Fixtures.relocate_unit/3` (the same instant, no-march status
  `spawn_barbarian/3` has) places the lord a short, controlled distance
  from a REAL camp instead — the warrior is then placed at a further
  controlled distance from the (now stationary) lord, and the whole
  scenario resolves in a single `advance_turn`.

  Camp identity still comes from a REAL camp (`Fixtures.list_camps`/the
  "game:camps" push — see the Fixtures moduledoc) — one of the 1-2
  camps that spawn already inside the player's own (already-visible)
  territory (criterion 7543) — so `context.camp_id` and the "game:camps"
  push this criterion observes through are exactly what a natural spawn
  would have produced; only the lord's and warrior's OWN placement is
  test-driven.

  "Within 5 hexes" / "toward" is operationalized as land-path hex
  distance (the same BFS-over-passable-land technique criterion 7534
  established for attack range), not raw mesh distance (which is only
  ever used for camp-placement bias checks, per criterion 7543).

  House doctrine: the "moved 1 hex closer" claim is anchored to a
  before/after snapshot taken across exactly one `advance_turn` call
  (never a fixed absolute distance assumed ahead of time).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the hunt closes in" do
    scenario "a barbarian steps exactly one hex closer to a player unit within range" do
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

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})

        assert_push_event(play_live, "game:camps", %{camps: camps0})
        [city] = Fixtures.player_cities(context.world, context.user)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:camps0, camps0)
         |> Map.put(:lord, lord)}
      end

      given_ "the lord stands within a real camp's leash range, a barbarian a few hexes further out",
             context do
        [camp | _] = context.camps0

        # The lord first: exactly 3 hexes from the REAL camp (well
        # inside `@leash_range`, so the leash never excludes it as a
        # target), placed instantly — see this module's doc.
        lord_ring3 = ring(context.world, camp.tile_id, 3)
        [lord_target | _] = Enum.reject(lord_ring3, &(&1 == context.city.tile_id))
        :ok = Fixtures.relocate_unit(context.world, context.lord.id, lord_target)

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == context.lord.id,
            do: u

        # Then the warrior: 2-5 hexes (hunting range, not adjacent —
        # adjacency is criterion 7553's territory) from the lord's NEW
        # position, tied to the same real camp.
        occupied = [context.city.tile_id, lord.tile_id]

        [target | _] =
          context.world
          |> distances_from(lord.tile_id, 5)
          |> Enum.filter(fn {_tile, d} -> d in 2..5 end)
          |> Enum.map(fn {tile, _d} -> tile end)
          |> Enum.reject(&(&1 in occupied))

        barbarian = Fixtures.spawn_barbarian(context.world, target, camp.id)

        {:ok,
         context
         |> Map.put(:camp_id, camp.id)
         |> Map.put(:barbarian_latest, barbarian)
         |> Map.put(:lord_final, lord)}
      end

      when_ "one more turn boundary passes", context do
        distance_before =
          land_distance(context.world, context.barbarian_latest.tile_id, context.lord_final.tile_id)

        Fixtures.advance_turn(context.world)
        assert_push_event(context.play_live, "game:camps", %{camps: camps}, 500)
        camp = Enum.find(camps, &(&1.id == context.camp_id))
        barbarian_after = Enum.find(camp.warriors, &(&1.id == context.barbarian_latest.id))

        {:ok,
         context
         |> Map.put(:distance_before, distance_before)
         |> Map.put(:barbarian_after, barbarian_after)}
      end

      then_ "the barbarian has stepped exactly one hex closer to my lord", context do
        # Anchor: the precondition this criterion is about — a target
        # within 5 hexes but not already adjacent (adjacency is
        # criterion 7553's "attack, don't move" territory instead).
        assert context.distance_before in 2..5

        assert context.barbarian_after != nil

        assert context.barbarian_after.tile_id in Fixtures.adjacent_tiles(
                 context.world,
                 context.barbarian_latest.tile_id
               )

        new_distance =
          land_distance(context.world, context.barbarian_after.tile_id, context.lord_final.tile_id)

        assert new_distance == context.distance_before - 1
        {:ok, context}
      end
    end
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
      _ -> nil
    end
  end

  # Land tiles whose distance from `start` is EXACTLY `depth` — the
  # outer frontier of `distances_from/3`, for placing something a
  # controlled number of hexes out.
  defp ring(world, start, depth) do
    world
    |> distances_from(start, depth)
    |> Enum.filter(fn {_tile, d} -> d == depth end)
    |> Enum.map(fn {tile, _d} -> tile end)
  end

  # Every land tile's hex distance from `start`, up to `max_depth` — a
  # map instead of `land_distance/4`'s single lookup, for cheaply
  # testing "is this tile within range of `start`" across many
  # candidates at once (`start` itself included, at depth 0).
  defp distances_from(world, start, max_depth) do
    land? = fn t -> Fixtures.tile_class(world, t) == :land end
    grow_distances(world, land?, %{start => 0}, [start], 1, max_depth)
  end

  defp grow_distances(_world, _land?, distances, _frontier, depth, max_depth) when depth > max_depth,
    do: distances

  defp grow_distances(_world, _land?, distances, [], _depth, _max_depth), do: distances

  defp grow_distances(world, land?, distances, frontier, depth, max_depth) do
    next =
      frontier
      |> Enum.flat_map(&Fixtures.adjacent_tiles(world, &1))
      |> Enum.uniq()
      |> Enum.filter(&(land?.(&1) and not Map.has_key?(distances, &1)))

    grow_distances(
      world,
      land?,
      Enum.reduce(next, distances, &Map.put(&2, &1, depth)),
      next,
      depth + 1,
      max_depth
    )
  end
end
