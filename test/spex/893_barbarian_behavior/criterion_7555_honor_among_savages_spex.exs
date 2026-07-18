defmodule BrokenOathsSpex.Story893.Criterion7555Spex do
  @moduledoc """
  Story 893 — Barbarian Behavior
  Criterion 7555 — barbarians never attack each other, even when
  standing right next to one another.

  Barbarian-fixture note: see criterion 7551's moduledoc — this uses
  REAL camp-spawned warriors via the "game:camps" push, one of the 1-2
  camps that spawn already inside the player's own territory
  (criterion 7543).

  Two barbarians guaranteed close together: rather than trying to walk
  two independently-roaming barbarians next to each other (an AI
  behavior this story doesn't give the player any lever over), this
  spec waits for the SAME camp to reach its 2-alive warrior cap
  (`camps.spec.md`: "capped at 2 alive per camp"). A freshly spawned
  warrior appears on its camp's own tile (the same spawn-location
  assumption criterion 7551 documents), so a camp holding both of its
  warriors puts them at minimum distance from each other without the
  player needing to steer anything.

  The observable proof of "never attack each other" is persistence:
  across several turn boundaries with the two barbarians right next to
  their shared camp (and nothing belonging to the player anywhere
  close enough to be a distraction — see criterion 7552's "beyond
  5-hex range" anchor technique), both warrior ids and their HP stay
  exactly as spawned. If they fought, at least one would take damage
  or disappear.

  Inferred, not-yet-implemented shape: as in criterion 7551, this
  assumes each pushed warrior gains a `tile_id` field.

  Setup-hardening (not in the original contract, unrelated to story
  895): the `given_` step's own anchor check originally asserted
  BOTH warriors within 1 hex of the camp — but the FIRST warrior to
  spawn (well before the second reaches the 3-turn cadence needed to
  join it, up to 24 boundaries later per this same step's own wait
  loop) is already a live, `BarbarianAI`-driven actor for every one of
  those intervening turns, free to roam up to `@roam_radius` (2, not
  1) hexes from its own camp per that module's documented "Roaming"
  behavior — a pre-existing mechanic this criterion's own SUBJECT
  (barbarians never attack each other) has no interest in. The anchor
  now matches that actual, documented radius; the criterion's own
  `then_` assertion (neither barbarian ever loses HP or disappears)
  is untouched.

  Truth surface "game:camps" is content-diffed against its last-pushed
  value (QA issue dbcbd478), so not every turn is guaranteed to
  produce a push — `latest_camps/2` (not `assert_push_event`) tracks
  the running snapshot, carrying the last-known roster forward on a
  quiet turn (which, by construction, means nothing about the camp
  changed that turn).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "honor among savages" do
    scenario "two barbarians from the same camp never fight each other" do
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
         |> Map.put(:camps, camps0)}
      end

      given_ "everything the player owns sits beyond the camp's 5-hex aggro range", context do
        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        assert land_distance(context.world, context.camp_tile, context.city.tile_id, 12) > 5
        assert land_distance(context.world, context.camp_tile, lord.tile_id, 12) > 5

        {:ok, context}
      end

      given_ "the camp has spawned both of its barbarian warriors", context do
        {camp, camps} =
          Enum.reduce_while(1..24, {nil, context.camps}, fn _turn, {_acc, camps} ->
            Fixtures.advance_turn(context.world)
            camps = latest_camps(context.play_live, camps)
            camp = Enum.find(camps, &(&1.id == context.camp_id))

            if length(camp.warriors) >= 2, do: {:halt, {camp, camps}}, else: {:cont, {nil, camps}}
          end)

        # Anchor: the 2-warrior cap really was reached, and both really
        # are still sitting right next to their shared camp — the
        # deterministic "close together" setup this spec depends on.
        assert length(camp.warriors) == 2

        for warrior <- camp.warriors do
          assert land_distance(context.world, context.camp_tile, warrior.tile_id, 4) <= 2
        end

        {:ok, context |> Map.put(:warriors0, camp.warriors) |> Map.put(:camps, camps)}
      end

      when_ "several more turn boundaries pass with both barbarians still shoulder to shoulder",
            context do
        {snapshots, _camps} =
          Enum.reduce(1..5, {[], context.camps}, fn _turn, {acc, camps} ->
            Fixtures.advance_turn(context.world)
            camps = latest_camps(context.play_live, camps)
            camp = Enum.find(camps, &(&1.id == context.camp_id))
            {[camp.warriors | acc], camps}
          end)

        {:ok, Map.put(context, :warrior_snapshots, Enum.reverse(snapshots))}
      end

      then_ "neither barbarian ever loses HP or disappears", context do
        ids0 = MapSet.new(context.warriors0, & &1.id)
        hp_by_id0 = Map.new(context.warriors0, &{&1.id, &1.hp})

        for warriors <- context.warrior_snapshots do
          ids_now = MapSet.new(warriors, & &1.id)

          # Both original barbarians are still present — neither was
          # destroyed.
          assert MapSet.subset?(ids0, ids_now)

          for warrior <- warriors, MapSet.member?(ids0, warrior.id) do
            assert warrior.hp == Map.fetch!(hp_by_id0, warrior.id)
          end
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
