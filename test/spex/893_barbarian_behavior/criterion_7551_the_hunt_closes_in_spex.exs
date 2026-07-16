defmodule BrokenOathsSpex.Story893.Criterion7551Spex do
  @moduledoc """
  Story 893 — Barbarian Behavior
  Criterion 7551 — at each turn boundary, a barbarian warrior moves
  exactly 1 hex toward the nearest player unit or city within 5 hexes.

  Barbarian-fixture note: unlike story 891's stand-in barbarians, this
  story is exactly the one that gives barbarians their own targeting
  and movement, so this spec uses a REAL camp-spawned warrior (via
  `Fixtures.list_camps`/the "game:camps" push — see the Fixtures
  moduledoc), not a second-player stand-in.

  Camp/warrior visibility uses one of the 1-2 camps that spawn already
  inside the player's own (already-visible) territory (criterion
  7543), so the whole scenario can be observed through the real
  "game:camps" push with no exploring detour.

  Inferred, not-yet-implemented shape: `Fixtures.list_camps/1`'s
  documented warrior shape (`%{id:, hp:, attack:, defense:}`) predates
  roaming/AI (explicitly "roaming/AI is story 893" per its own
  moduledoc) and carries no position. Movement is unobservable without
  one, so this spec assumes each pushed warrior gains a `tile_id`
  field once this story lands — the same kind of judgment call
  criterion 7540 (story 891) documented for "game:combat"'s shape.

  "Within 5 hexes" / "toward" is operationalized as land-path hex
  distance (the same BFS-over-passable-land technique criterion 7534
  established for attack range), not raw mesh distance (which is only
  ever used for camp-placement bias checks, per criterion 7543).

  House doctrine: the "moved 1 hex closer" claim is anchored to a
  before/after snapshot taken across exactly one `advance_turn` call
  (never a fixed absolute distance assumed ahead of time), since the
  warrior may have already been roaming near its camp while my lord
  was still marching into range.
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

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})

        assert_push_event(play_live, "game:camps", %{camps: camps0})
        [camp | _] = camps0
        [city] = Fixtures.player_cities(context.world, context.user)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:camp_id, camp.id)
         |> Map.put(:camp_warrior_baseline_ids, MapSet.new(camp.warriors, & &1.id))}
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

      given_ "the player's lord marches within hunting range, but stays a few hexes clear",
             context do
        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        occupied = [context.city.tile_id, context.barbarian.tile_id]

        ring3 =
          Enum.reduce(
            1..3,
            {[context.barbarian.tile_id], MapSet.new([context.barbarian.tile_id])},
            fn _, {frontier, seen} ->
              next =
                frontier
                |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
                |> Enum.uniq()
                |> Enum.filter(land?)
                |> Enum.reject(&MapSet.member?(seen, &1))

              {next, MapSet.union(seen, MapSet.new(next))}
            end
          )
          |> elem(0)

        [target | _] = Enum.reject(ring3, &(&1 in occupied))

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        render_hook(context.play_live, "queue_move", %{
          "unit_id" => to_string(lord.id),
          "to_tile" => target
        })

        lord_now = fn ->
          [u] =
            for u <- Fixtures.player_units(context.world, context.user), u.id == lord.id, do: u

          u
        end

        {lord_final, barbarian_latest} =
          Enum.reduce_while(1..40, {lord_now.(), context.barbarian}, fn _turn, {unit, barb} ->
            if unit.tile_id == target do
              {:halt, {unit, barb}}
            else
              Fixtures.advance_turn(context.world)
              assert_push_event(context.play_live, "game:camps", %{camps: camps}, 500)
              camp = Enum.find(camps, &(&1.id == context.camp_id))
              new_barb = Enum.find(camp.warriors, &(&1.id == context.barbarian.id)) || barb
              {:cont, {lord_now.(), new_barb}}
            end
          end)

        {:ok,
         context
         |> Map.put(:lord_final, lord_final)
         |> Map.put(:barbarian_latest, barbarian_latest)}
      end

      when_ "one more turn boundary passes", context do
        distance_before =
          land_distance(context.world, context.barbarian_latest.tile_id, context.lord_final.tile_id)

        Fixtures.advance_turn(context.world)
        assert_push_event(context.play_live, "game:camps", %{camps: camps}, 500)
        camp = Enum.find(camps, &(&1.id == context.camp_id))
        barbarian_after = Enum.find(camp.warriors, &(&1.id == context.barbarian.id))

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
end
