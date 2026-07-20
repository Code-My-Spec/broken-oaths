defmodule BrokenOathsSpex.Story892.Criterion7543Spex do
  @moduledoc """
  Story 892 — Barbarian Camps Spawn
  Criterion 7543 — founding a player's first city spawns 5-7 barbarian
  camps total: 1-2 already inside the player's own (already-visible)
  region, and 4-5 more 8-15 hexes out, unexplored, and outside the
  player's claimed region (the region-boundary bias — see Three Amigos
  notes on story 892). Total/far ranges narrowed from 5-8/4-6 in the
  v0.2.1 playtest balance pass (issue 04931763, "barbarians spawn too
  quickly, or are too strong") — see `BrokenOaths.Combat.Camps`'s own
  moduledoc for the full before/after numbers and the same pass's
  minimum-spacing rule (covered by `CampsTest`, unit-level; no UI
  surface exists to assert inter-camp distance through here).

  Camp existence/placement has no UI surface until a camp is actually
  scouted (fog of war, criterion 7546 — a hard constraint), so this
  spec uses `Fixtures.list_camps/1`, a narrow sanctioned ground-truth
  read added for this story with the same status as
  `region_partition`/`claimed_region` (see the Fixtures moduledoc).
  The immediately-visible in-region camps ARE asserted through the
  real surface: the "game:camps" push (mirroring "game:cities") that
  `GameLive.Play` pushes on every board refresh — inferred surface,
  not yet implemented (component under test: `BrokenOaths.Combat.Camps`).

  "Biased toward region boundaries" is operationalized here as "not a
  tile inside the founding player's own claimed region" — the region
  partition (story 877) is the only boundary concept this codebase
  already has.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the wilderness answers the first city" do
    scenario "founding the first city spawns 5-7 camps split near/far" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player joined the world and is on the board", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")
        {:ok, Map.put(context, :play_live, play_live)}
      end

      when_ "the player founds their first city", context do
        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(context.play_live, "found_city", %{"unit_id" => to_string(settler.id)})

        assert_push_event(context.play_live, "game:camps", %{camps: pushed_camps})

        [city] = Fixtures.player_cities(context.world, context.user)

        {:ok, context |> Map.put(:city, city) |> Map.put(:pushed_camps, pushed_camps)}
      end

      then_ "one or two camps are already visible inside the player's own territory", context do
        assert length(context.pushed_camps) in 1..2

        region_id = Fixtures.claimed_region(context.world, context.user)
        %{regions: regions} = Fixtures.region_partition(context.world)
        home = MapSet.new(Map.fetch!(regions, region_id))

        for camp <- context.pushed_camps do
          assert camp.hp == 100
          assert MapSet.member?(home, camp.tile_id)
        end

        {:ok, context}
      end

      then_ "four to five more camps sit 8-15 hexes out, unexplored, outside the region",
            context do
        all_camps = Fixtures.list_camps(context.world)
        visible_ids = MapSet.new(context.pushed_camps, & &1.id)
        far_camps = Enum.reject(all_camps, &(&1.id in visible_ids))

        assert length(far_camps) in 4..5
        assert length(all_camps) in 5..7

        region_id = Fixtures.claimed_region(context.world, context.user)
        %{regions: regions} = Fixtures.region_partition(context.world)
        home = MapSet.new(Map.fetch!(regions, region_id))

        # BFS rings from the city tile over raw mesh adjacency (same
        # technique as criteria 7464/7489): tiles within 7 hops, and
        # tiles within 15 hops. "8-15 hexes away" = present in the
        # 15-ring but absent from the 7-ring.
        grow_ring = fn depth ->
          Enum.reduce(1..depth, {[context.city.tile_id], MapSet.new([context.city.tile_id])}, fn
            _, {frontier, seen} ->
              next =
                frontier
                |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
                |> Enum.uniq()
                |> Enum.reject(&MapSet.member?(seen, &1))

              {next, MapSet.union(seen, MapSet.new(next))}
          end)
          |> elem(1)
        end

        within_7 = grow_ring.(7)
        within_15 = grow_ring.(15)

        for camp <- far_camps do
          assert camp.hp == 100
          refute MapSet.member?(home, camp.tile_id)
          refute MapSet.member?(within_7, camp.tile_id)
          assert MapSet.member?(within_15, camp.tile_id)
        end

        {:ok, context}
      end
    end
  end
end
