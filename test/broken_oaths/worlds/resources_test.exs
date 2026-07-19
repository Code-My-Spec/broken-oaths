defmodule BrokenOaths.Worlds.ResourcesTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Game.Spawner
  alias BrokenOaths.Worlds.Globe
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.Resources
  alias BrokenOaths.Worlds.World

  # A bespoke seed/frequency pair known to roll a healthy mix of
  # hills AND deep ocean (hills are naturally rare terrain — many
  # seeds roll none at all at small frequencies, the same reason
  # `criterion_7485`/`criterion_7484` reach for their own bespoke
  # seed 33 rather than the default `:a_world` fixture), so both the
  # Sheep/Stone (hills) and "ocean never carries a resource" cases
  # below have real coverage.
  @hilly_seed 7
  @frequency 30
  @total_tiles Globe.tile_count(@frequency)

  defp world(attrs \\ %{}) do
    Map.merge(
      %World{seed: @hilly_seed, frequency: @frequency, resource_density: :standard},
      attrs
    )
  end

  describe "at/2" do
    test "is deterministic for a given seed, frequency, and density" do
      w = world()
      first = for t <- 0..(@total_tiles - 1), into: %{}, do: {t, Resources.at(w, t)}
      second = for t <- 0..(@total_tiles - 1), into: %{}, do: {t, Resources.at(w, t)}

      assert first == second
      assert first |> Map.values() |> Enum.any?(&(&1 != nil))
    end

    test "never places a resource on non-land terrain" do
      w = world()

      for tile_id <- 0..(@total_tiles - 1), Resources.at(w, tile_id) != nil do
        assert Regions.tile_class(w, tile_id) == :land
      end
    end

    test "every placed resource sits on terrain its own kind allows" do
      w = world()

      placements =
        for tile_id <- 0..(@total_tiles - 1),
            resource = Resources.at(w, tile_id),
            resource != nil,
            do: {resource, Regions.terrain(w, tile_id)}

      assert placements != []
      assert Enum.all?(placements, fn {resource, terrain} -> eligible?(resource, terrain) end)
    end

    test "a hilly world actually rolls Sheep and/or Stone (both share the hills gate)" do
      w = world()

      hill_resources =
        for tile_id <- 0..(@total_tiles - 1),
            Regions.terrain(w, tile_id).relief == :hills,
            resource = Resources.at(w, tile_id),
            resource != nil,
            do: resource

      assert Enum.any?(hill_resources, &(&1 in [:sheep, :stone]))
    end

    test "dense places strictly more resources than sparse, for the same seed" do
      sparse = world(%{resource_density: :sparse})
      dense = world(%{resource_density: :dense})

      count = fn w -> Enum.count(0..(@total_tiles - 1), &(Resources.at(w, &1) != nil)) end

      assert count.(dense) > count.(sparse)
    end

    test "an ineligible tile (e.g. ocean) never carries a resource" do
      w = world()

      ocean_tile =
        Enum.find(0..(@total_tiles - 1), &(Regions.tile_class(w, &1) == :deep_ocean))

      refute is_nil(ocean_tile)
      assert Resources.at(w, ocean_tile) == nil
    end

    # Regression for the v0.2.1 playtest "resources missing" report
    # (issue 335f265c): the field symptom was "I've only seen wheat
    # resources... no Cattle, no Sheep, no Stone" on live, already-
    # running worlds. The placement math here was never actually wrong
    # (this whole describe block already covers it); the real failure
    # mode was a long-lived, hot-reloaded server serving an EARLIER,
    # incomplete `candidates/1` build out of the `:persistent_term`
    # cache forever, because nothing about a placement bugfix changes
    # a world's `{seed, frequency, density}` cache key (see
    # `Resources.@cache_version`'s own comment and the
    # `game-state-persistence` ADR). This locks in the actual
    # observable contract at real gameplay scale (`World.frequency`'s
    # own schema default, 54) across more than one seed, so a future
    # regression to "everything rolls the same kind" fails loudly.
    test "a real-scale world rolls more than one resource kind, not just wheat" do
      frequency = 54
      total = Globe.tile_count(frequency)

      for seed <- [7, 99, 20_260_718] do
        w = %World{seed: seed, frequency: frequency, resource_density: :standard}

        kinds =
          for tile_id <- 0..(total - 1),
              resource = Resources.at(w, tile_id),
              resource != nil,
              do: resource

        distinct_kinds = Enum.uniq(kinds)

        assert length(distinct_kinds) > 1,
               "seed #{seed}: only rolled #{inspect(distinct_kinds)} across the whole map"
      end
    end

    # Playtest fix regression (issue 3e1159d1 — "resources everywhere",
    # story 905 criteria 7701/7702): STANDARD density should place a
    # resource on roughly 7% of LAND tiles (one per 12-15), a Civ 6-like
    # sparse scatter — not the ~14-20% the pre-fix `@rate.standard`
    # (0.28, tuned per ELIGIBLE tile without accounting for hills'
    # double Sheep/Stone roll or the eligible/land ratio) actually
    # produced. Measured at real gameplay scale (`World.frequency`'s own
    # schema default, 54 — same scale `criterion 335f265c`'s regression
    # above already uses) across several seeds: 7.0%-8.8% (band widened
    # slightly at the top from the original 5-9% measurement to absorb
    # story 911's Copper-reachability fix — see `Resources`'s own
    # `@copper_rate` comment for why that fix nudges density up a little
    # on purpose), comfortably inside a generous 5%-9% band. A regression
    # back toward the old, too-dense default would blow well past 9%; a
    # broken/near-empty placement would fall under 5% — either fails
    # this loudly.
    test "a standard-density world places roughly 7% of land tiles with a resource" do
      frequency = 54
      total = Globe.tile_count(frequency)

      for seed <- [7, 99, 20_260_718, 424_242, 33] do
        w = %World{seed: seed, frequency: frequency, resource_density: :standard}

        land = for tile_id <- 0..(total - 1), Regions.tile_class(w, tile_id) == :land, do: tile_id
        resource_count = Enum.count(land, &(Resources.at(w, &1) != nil))
        pct = resource_count / length(land) * 100

        assert pct >= 5.0 and pct <= 9.0,
               "seed #{seed}: standard density covered #{Float.round(pct, 2)}% of land tiles, expected ~7% (5-9% band)"
      end
    end

    # Ordering regression alongside the coverage target above: sparse
    # and dense stay meaningfully below/above the new, lower standard
    # midpoint (not just "strictly more than sparse," which
    # `"dense places strictly more resources than sparse"` above already
    # covers) — the per-world density slider (criterion 7703) still
    # reaches a noticeably sparser or richer world from the new default.
    test "sparse and dense both land in their own bands around the new standard midpoint" do
      frequency = 54
      total = Globe.tile_count(frequency)

      base = %World{seed: @hilly_seed, frequency: frequency, resource_density: :standard}

      land =
        for tile_id <- 0..(total - 1), Regions.tile_class(base, tile_id) == :land, do: tile_id

      pct = fn density ->
        w = %{base | resource_density: density}
        Enum.count(land, &(Resources.at(w, &1) != nil)) / length(land) * 100
      end

      sparse_pct = pct.(:sparse)
      standard_pct = pct.(:standard)
      dense_pct = pct.(:dense)

      assert sparse_pct < standard_pct
      assert standard_pct < dense_pct
      assert sparse_pct <= 5.0
      assert dense_pct >= 10.0
    end
  end

  # QA issue 78e938bb (story 911 follow-up): re-QA across three separate
  # worlds — including a DENSE one with a real founded city grown to
  # size 6 / 12 territory tiles — found ZERO reachable Copper, making
  # the Bronze Spearman unbuildable for a real player. These regressions
  # lock in the fix's actual promise: every region a player could
  # possibly spawn in (`Regions.spawnable/1`) has a Copper tile within
  # `Resources`'s own reachability radius of that region's spawn point.
  describe "Copper reachability guarantee (QA issue 78e938bb, story 911 follow-up)" do
    # Mirrors `Resources.@copper_guarantee_radius` (private to that
    # module by design — this describe block re-asserts the CONTRACT
    # from outside, not the implementation, so a future radius change
    # there is a deliberate, visible edit here too, not a silent drift).
    @guarantee_radius 6

    test "every spawnable region has Copper reachable within a few tiles of its own spawn point" do
      for frequency <- [8, 54],
          seed <- [7, 99, 33],
          density <- [:sparse, :standard, :dense] do
        w = %World{seed: seed, frequency: frequency, resource_density: density}

        for region_id <- Regions.spawnable(w) do
          [anchor | _] = Regions.central_land_tiles(w, region_id)
          reachable = land_tiles_within(w, anchor, region_id, @guarantee_radius)

          assert Enum.any?(reachable, &(Resources.at(w, &1) == :copper)),
                 "freq #{frequency} seed #{seed} #{density}: region #{region_id}'s spawn " <>
                   "anchor (tile #{anchor}) has no reachable Copper within " <>
                   "#{@guarantee_radius} tiles"
        end
      end
    end

    # The most faithful reproduction of the QA symptom: not a synthetic
    # "central tile" but the ACTUAL `lord_tile` a real player would get
    # from `Game.Spawner.spawn_player/2` on their very first join.
    test "a real Spawner-placed player can reach Copper within a reasonable distance of their lord_tile" do
      for frequency <- [8, 54], seed <- [7, 424_242, 20_260_718] do
        w = %World{seed: seed, frequency: frequency, resource_density: :standard}

        {:ok, %{region_id: region_id, lord_tile: lord_tile}} = Spawner.spawn_player(w, [])

        reachable = land_tiles_within(w, lord_tile, region_id, @guarantee_radius)

        assert Enum.any?(reachable, &(Resources.at(w, &1) == :copper)),
               "freq #{frequency} seed #{seed}: the actual Spawner lord_tile #{lord_tile} " <>
                 "has no reachable Copper within #{@guarantee_radius} tiles"
      end
    end

    # Land-only, same-region BFS from `anchor`, bounded at `radius` hex
    # steps — an independent (test-side) reimplementation of the
    # "nearby" notion `Resources`'s own guarantee uses internally, so
    # this test verifies the OBSERVABLE contract rather than re-running
    # the module's own private code path.
    defp land_tiles_within(world, anchor, region_id, radius) do
      region_set =
        world
        |> Regions.partition()
        |> Map.fetch!(:regions)
        |> Map.fetch!(region_id)
        |> MapSet.new()

      grow_within(world, region_set, %{anchor => 0}, [anchor], 0, radius)
    end

    defp grow_within(_world, _region_set, depths, _frontier, depth, radius) when depth >= radius,
      do: Map.keys(depths)

    defp grow_within(world, region_set, depths, frontier, depth, radius) do
      next =
        frontier
        |> Enum.flat_map(&Regions.adjacent_tiles(world, &1))
        |> Enum.uniq()
        |> Enum.filter(fn t ->
          MapSet.member?(region_set, t) and not Map.has_key?(depths, t) and
            Regions.tile_class(world, t) == :land
        end)

      case next do
        [] ->
          Map.keys(depths)

        _ ->
          grow_within(
            world,
            region_set,
            put_depths(depths, next, depth + 1),
            next,
            depth + 1,
            radius
          )
      end
    end

    defp put_depths(depths, tiles, depth), do: Enum.reduce(tiles, depths, &Map.put(&2, &1, depth))
  end

  defp eligible?(:cattle, %{base: :grassland, relief: :flat, feature: nil}), do: true
  defp eligible?(:cattle, _terrain), do: false

  defp eligible?(:wheat, %{base: :plains, relief: :flat, feature: nil}), do: true
  defp eligible?(:wheat, _terrain), do: false

  defp eligible?(:sheep, %{relief: :hills, feature: feature}), do: feature != :woods
  defp eligible?(:sheep, _terrain), do: false

  defp eligible?(:stone, %{relief: :hills, feature: feature}), do: feature != :woods
  defp eligible?(:stone, _terrain), do: false

  # Story 911 — Copper (a STRATEGIC resource) shares Sheep/Stone's own
  # hills-no-woods terrain gate (see `Resources`'s own moduledoc for
  # why it reuses that terrain rather than inventing a new one).
  defp eligible?(:copper, %{relief: :hills, feature: feature}), do: feature != :woods

  # Story 911 follow-up (QA issue 78e938bb): the per-region
  # reachability guarantee (`Resources.guarantee_copper_near_spawns/2`)
  # broadens onto ANY flat, featureless tile — not just Grassland/
  # Plains — as a LAST RESORT, only when nothing Hills-eligible sits
  # near enough (a real case QA also observed: an all-Snow/Tundra polar
  # region with no Hills and no Grassland/Plains within the guarantee
  # radius at all). See `Resources.flat_eligible?/2`'s own comment for
  # why Desert/Tundra/Snow are in-bounds for this specific, yield-free
  # access-gate resource.
  defp eligible?(:copper, %{relief: :flat, feature: nil}), do: true

  defp eligible?(:copper, _terrain), do: false
end
