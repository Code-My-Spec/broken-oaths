defmodule BrokenOathsSpex.Story893.Criterion7552Spex do
  @moduledoc """
  Story 893 — Barbarian Behavior
  Criterion 7552 — when no player unit or city is within 5 hexes, a
  barbarian warrior roams near its home camp instead of standing
  still or wandering off.

  Barbarian-fixture note: see criterion 7551's moduledoc — this uses a
  REAL camp-spawned warrior via the "game:camps" push, one of the 1-2
  camps that spawn already inside the player's own territory
  (criterion 7543), so it is observable with no exploring detour.

  Inferred, not-yet-implemented shape: as in criterion 7551, this
  assumes each pushed warrior gains a `tile_id` field (the documented
  shape in the Fixtures moduledoc predates roaming/AI).

  "Nothing in range" here means the player deliberately leaves every
  unit/city where it naturally lands after founding — no marching
  toward the camp — with an explicit anchor assertion (not an
  assumption) that everything the player owns really is beyond the
  5-hex aggro range before any roaming is judged.

  "Roams near its home camp" is operationalized as a bounded-radius
  judgment call: across several turn boundaries with nothing in range,
  the warrior's land-path distance from its camp's tile never exceeds
  2 hexes — the same kind of documented judgment call criterion 7540
  (story 891) made for "game:combat"'s shape, since no story or spec
  doc gives roaming an exact radius.

  Truth surface "game:camps" is content-diffed against its last-pushed
  value (QA issue dbcbd478), so not every turn is guaranteed to
  produce a push — `latest_camps/2` (not `assert_push_event`) tracks
  the running snapshot, carrying the last-known state forward on a
  quiet turn (which, by construction, means nothing about the camp/
  warrior changed that turn).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "out of sight, out of mind" do
    scenario "a barbarian with nothing in range stays close to its camp" do
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
        [city] = Fixtures.player_cities(context.world, context.user)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:camp_id, camp.id)
         |> Map.put(:camp_tile, camp.tile_id)
         |> Map.put(:camp_warrior_baseline_ids, MapSet.new(camp.warriors, & &1.id))
         |> Map.put(:camps, camps0)}
      end

      given_ "every player unit and city sits beyond the camp's 5-hex aggro range", context do
        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        # Anchor: this criterion's whole precondition — verified, not
        # assumed. "In-region" only guarantees the camp is inside the
        # player's claimed territory, not that it's close to any
        # particular unit/city, but the scenario is meaningless if the
        # anchor doesn't hold.
        assert land_distance(context.world, context.camp_tile, context.city.tile_id, 12) > 5
        assert land_distance(context.world, context.camp_tile, lord.tile_id, 12) > 5

        {:ok, context}
      end

      given_ "a barbarian warrior has spawned at the camp", context do
        {warrior, camps} =
          Enum.reduce_while(1..12, {nil, context.camps}, fn _turn, {_acc, camps} ->
            Fixtures.advance_turn(context.world)
            camps = latest_camps(context.play_live, camps)
            camp = Enum.find(camps, &(&1.id == context.camp_id))

            new_warrior =
              Enum.find(camp.warriors, &(&1.id not in context.camp_warrior_baseline_ids))

            if new_warrior, do: {:halt, {new_warrior, camps}}, else: {:cont, {nil, camps}}
          end)

        {:ok, context |> Map.put(:barbarian, warrior) |> Map.put(:camps, camps)}
      end

      when_ "several more turn boundaries pass with nothing ever coming into range", context do
        {snapshots, _camps} =
          Enum.reduce(1..5, {[], context.camps}, fn _turn, {acc, camps} ->
            Fixtures.advance_turn(context.world)
            camps = latest_camps(context.play_live, camps)
            camp = Enum.find(camps, &(&1.id == context.camp_id))
            warrior = Enum.find(camp.warriors, &(&1.id == context.barbarian.id))
            {[warrior | acc], camps}
          end)

        {:ok, Map.put(context, :warrior_snapshots, Enum.reverse(snapshots))}
      end

      then_ "the barbarian never strays more than a couple of hexes from its camp", context do
        # Anchor: the barbarian is still alive/tracked every turn — a
        # vacuous "roams near camp" would also pass on an empty list.
        assert Enum.all?(context.warrior_snapshots, &(&1 != nil))

        for warrior <- context.warrior_snapshots do
          assert land_distance(context.world, context.camp_tile, warrior.tile_id, 8) <= 2
        end

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
      _ -> 99
    end
  end
end
