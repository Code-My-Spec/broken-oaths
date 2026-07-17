defmodule BrokenOathsSpex.Story892.Criterion7544Spex do
  @moduledoc """
  Story 892 — Barbarian Camps Spawn
  Criterion 7544 — founding any city after the first (second, third,
  ...) spawns zero additional barbarian camps. Only the very first
  founding triggers the wilderness (criterion 7543).

  Camp existence has no UI surface until scouted (fog of war,
  criterion 7546), so the before/after comparison here reads
  `Fixtures.list_camps/1`, the same narrow sanctioned ground-truth
  read used by 7543/7546 (see the Fixtures moduledoc). The second
  founding's own effect (a second city existing) IS asserted through
  the real surface (`Fixtures.player_cities/2`, the same sanctioned
  read every other city-loop spec already uses).

  The "grow, produce a settler, march it 4+ hexes, found" sequence
  mirrors story 883's own second-founding criterion (7489) — same
  pattern, reused here because this criterion needs the exact same
  legitimate second founding, just checking a different outcome.

  Setup-hardening (not in the original contract): the settler used to
  WALK to its founding tile over a turn-boundary wait loop (up to 15
  more turns on top of the ~80 already spent growing/producing) — the
  settler-tile candidate is still validated as reachable via a real
  `queue_move` probe (unchanged: this still refuses an unreachable
  pocket, not just a barbarian-occupied one), but once a walkable
  target is confirmed, `Fixtures.relocate_unit/3` places the settler
  there directly instead of spending another turn-boundary's worth of
  exposure walking it, since story 893's barbarian AI (real, roaming
  warriors, this criterion's own subject) can still find and kill an
  undefended settler mid-march — nothing to do with what's being
  tested here (camp count after a second founding).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "expansion is not punished twice" do
    scenario "a produced settler founds a second city and no new camps appear" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a first city already stands with its barbarian camps spawned", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [founding_settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(founding_settler.id)})
        [city1] = Fixtures.player_cities(context.world, context.user)
        camps_after_first = Fixtures.list_camps(context.world)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city1, city1)
         |> Map.put(:camps_after_first, camps_after_first)}
      end

      given_ "a produced settler marched 4+ hexes from the first city", context do
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

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        # Wilderness camps (this criterion's own subject) can have real
        # ownerless warriors standing anywhere by now — dozens of turns
        # have passed waiting for growth and settler production. A
        # target tile a warrior occupies would interrupt the settler's
        # move one hex short (Turn's dynamic collision check), never
        # reaching the founding distance; ground-truth camp/warrior
        # tiles (the same sanctioned read criterion 7543 uses) are
        # excluded so this stays a test of "no new camps," not a flake
        # on wilderness placement.
        barbarian_tiles =
          context.world
          |> Fixtures.list_camps()
          |> Enum.flat_map(fn camp -> [camp.tile_id | Enum.map(camp.warriors, & &1.tile_id)] end)
          |> MapSet.new()

        # Candidates from 4 hexes out through 10 (cumulative, not a
        # single ring) — a wider pool than the plain "exactly 4"
        # criterion 7489 could rely on before real barbarians existed,
        # since one warrior standing at the city's own doorstep can
        # block every exit at a single fixed depth.
        rings =
          Enum.reduce(1..10, {[context.city1.tile_id], MapSet.new([context.city1.tile_id]), %{}}, fn
            depth, {frontier, seen, by_depth} ->
              next =
                frontier
                |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
                |> Enum.uniq()
                |> Enum.reject(&MapSet.member?(seen, &1))
                |> Enum.filter(land?)

              by_depth = if depth >= 4, do: Map.put(by_depth, depth, next), else: by_depth
              {next, MapSet.union(seen, MapSet.new(next)), by_depth}
          end)
          |> elem(2)

        candidates =
          4..10
          |> Enum.flat_map(&Map.get(rings, &1, []))
          |> Enum.reject(&MapSet.member?(barbarian_tiles, &1))

        # A tile clear of barbarians can still be UNREACHABLE if one
        # blocks the only route to it (`WorldServer`'s BFS pathfinding
        # treats any occupied tile as impassable, not just as a
        # destination) — try candidates in order (nearest first) until
        # one actually queues a path, rather than assuming the first
        # is walkable. `queue_move`'s `unit_id` — unlike `found_city`'s
        # — is never run through `Play.parse_id/1`, so it must be the
        # raw integer (same as criterion 7489's own working pattern),
        # not a string.
        target =
          Enum.find(candidates, fn candidate ->
            render_hook(context.play_live, "queue_move", %{
              "unit_id" => new_settler.id,
              "to_tile" => candidate
            })

            not has_element?(context.play_live, "[data-test='order-error']")
          end)

        refute target == nil,
               "no land tile 4-10 hexes out had a walkable path (all blocked by barbarians?)"

        :ok = Fixtures.relocate_unit(context.world, new_settler.id, target)

        [settler] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.id == new_settler.id,
              do: u

        {:ok, Map.put(context, :settler, settler)}
      end

      when_ "it founds a second city", context do
        render_hook(context.play_live, "found_city", %{"unit_id" => to_string(context.settler.id)})
        {:ok, context}
      end

      then_ "no additional barbarian camps spawn", context do
        camps_after_second = Fixtures.list_camps(context.world)

        # Anchor: the first founding really did spawn camps (5-8, per
        # criterion 7543), so this comparison isn't vacuously "0 == 0".
        assert length(context.camps_after_first) >= 5

        # Identity (id/tile_id/hp), not full structural equality: this
        # given_ chain (borrowed from criterion 7489's "grow, produce a
        # settler, march it, found" sequence) burns 20+ turns waiting
        # for settler production — well past the 3-turn spawn cadence
        # criteria 7546/7547/7548/7549 establish as real, required
        # behavior. A below-cap camp legitimately gaining warriors in
        # that window is correct, not "punishment" for the second
        # founding; comparing warriors here would make this criterion
        # fail EVERY time the cadence fires correctly. "No additional
        # camps spawn" means the SET of camps is unchanged — same ids,
        # same tiles, same hp — which this asserts precisely.
        second_identity = Enum.map(camps_after_second, &Map.take(&1, [:id, :tile_id, :hp]))
        first_identity = Enum.map(context.camps_after_first, &Map.take(&1, [:id, :tile_id, :hp]))
        assert MapSet.new(second_identity) == MapSet.new(first_identity)
        {:ok, context}
      end

      then_ "a second city exists alongside the first", context do
        cities = Fixtures.player_cities(context.world, context.user)
        assert length(cities) == 2
        {:ok, context}
      end
    end
  end
end
