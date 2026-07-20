defmodule BrokenOaths.Worlds.Resources do
  @moduledoc """
  Deterministic bonus/strategic-resource placement (stories 905/911):
  `.code_my_spec/knowledge/civ6_resources.md` §2/§3/§5.

  Four BONUS resources, each gated to its own eligible terrain:

    * `:cattle` — flat, featureless grassland
    * `:wheat`  — flat, featureless plains
    * `:sheep`  — hills (any base, any feature except woods)
    * `:stone`  — hills (any base, any feature except woods)

  Plus one STRATEGIC resource (story 911 — Copper for the Bronze
  Spearman):

    * `:copper` — hills (any base, any feature except woods), the
      same eligible terrain as Sheep/Stone. `civ6_resources.md`'s own
      table already lists Copper on Hills (§2: "Copper | Hills"), so
      this reuses the SAME terrain gate rather than inventing a new
      one — Civ 6 itself also places Copper on Desert/Tundra in later
      expansions, but Hills alone is the simplest MVP slice and keeps
      this module's terrain surface unchanged. Unlike the four bonus
      resources, Copper carries no yield of its own
      (`BrokenOaths.Cities.Yields.resource_bonus/1`'s `:copper` clause
      is `0F 0P`) — it is a pure ACCESS GATE for the Bronze Spearman
      (`BrokenOaths.Cities.Production.can_queue?/3`'s `copper_access?`
      option), never a stockpile a city consumes. Copper is placed
      here UNCONDITIONALLY, exactly like every other resource — this
      module has no concept of a viewing player. The reveal rule
      ("Copper stays invisible until a player completes Bronze
      Working") is a client-visibility concern, not a placement one,
      and lives entirely in `BrokenOathsWeb.GameLive.Play`'s own
      `known_resources/3` (gating what a fog-filtered push actually
      includes) — the same split `BrokenOaths.Worlds.Regions`
      (placement) already keeps from `Game.visibility/2` (who sees
      what).

  Placement is a PURE function of `world.seed`, `world.frequency`,
  `world.resource_density`, and a tile's own id — no live RNG, no
  `Repo`. The same inputs always produce the same resource map, the
  same way `BrokenOaths.Worlds.Regions.partition/1` is a pure function
  of seed + frequency (see that module's own moduledoc). Every roll
  hashes `{seed, tile_id, kind}` through `:erlang.phash2/2` into a
  3-integer `:rand.seed_s/2` state and draws exactly one value —
  the same seeded-roll idiom `BrokenOaths.Game.Combat.roll/1` and
  `BrokenOaths.Game.Camps`'s `seeded_pick/3` already establish, so two
  calls with the same seed always agree regardless of what else is
  happening in this process.

  A hills tile is eligible for Sheep, Stone, AND Copper; ties break by
  a fixed priority (Cattle > Wheat > Sheep > Stone > Copper, per the
  design doc, Copper appended last for story 911) — Sheep gets first
  claim at a hills tile, Stone claims it only if Sheep's own roll
  missed, and Copper claims it only if BOTH Sheep's and Stone's rolls
  missed. Copper deliberately sits LAST in priority, not first: story
  905's density retune (issue 3e1159d1) is recent and already tuned
  Sheep/Stone's own rates against `ResourcesTest`'s precise land-tile
  percentage bands — putting Copper last means Sheep/Stone's own
  placement stays bit-for-bit unaffected by Copper's addition (see
  `place/3`: Sheep/Stone keep rolling against the shared `@rate`, never
  `@copper_rate`). Grassland/plains tiles never compete (each is
  eligible for exactly one resource), so the priority only ever matters
  on hills.

  ## Copper reachability (QA issue `78e938bb`, story 911 follow-up)

  Re-QA across three separate worlds (including a dense-density one)
  found ZERO reachable Copper from any founded city — Hills are
  naturally rare terrain (`Generator`'s own comment: ~8-13% of land),
  a starting island frequently has only 0-5 Hills tiles total, and
  Copper's last-priority leftover roll (only claiming a Hills tile
  BOTH Sheep's and Stone's own rolls already missed) made its actual
  per-tile odds too thin to reliably land at all against that small a
  population — turning "Bronze Spearman requires Copper" into "Bronze
  Spearman is unbuildable" for a real player. Two changes address this,
  deliberately layered rather than relying on either alone:

  1. **Copper gets its own, higher, independent rate** (`@copper_rate`,
     roughly 1.17x `@rate` at every density tier) instead of sharing
     `@rate` with the four bonus resources. Because Copper still checks
     LAST (after Sheep/Stone's own `@rate` rolls), this raises how often
     Copper actually claims a Hills tile the other two left bare without
     touching Sheep/Stone's own roll at all — `place/3` looks up the
     rate per-kind, so their code path is unchanged bit-for-bit. This
     multiplier is intentionally modest: an initial, much more aggressive
     bump (~1.7x) measurably pushed `ResourcesTest`'s tuned 5-9%
     standard-density band over its own ceiling on some seeds (seed 33 at
     real gameplay scale hit 9.26%) before item 2 below even ran — the
     reachability GUARANTEE, not this rate, is what actually has to do
     the heavy lifting, so the rate only needs to nudge the natural roll
     closer to already agreeing with the guarantee. Measured: standard
     density across the same five real-scale seeds `ResourcesTest` already
     samples now lands 7.0%-8.8%, still comfortably inside the band.

  2. **A deterministic per-spawnable-region GUARANTEE**
     (`guarantee_copper_near_spawns/2`) is layered on top of the natural
     roll, because a probabilistic rate — however generous — can still
     roll zero on any GIVEN world, exactly the failure QA hit three times
     running. For every region `Regions.spawnable/1` would offer a new
     player (>= 175 tiles), this module anchors on that region's own
     `Regions.central_land_tiles/2` (the SAME centrality `Game.Spawner`
     walks to pick a `lord_tile` — see that function's own moduledoc for
     why the two modules share it rather than risking two different
     "center of the region" answers) and checks whether a Copper tile
     already sits within `@copper_guarantee_radius` hex-steps of it
     (land-only, same-region BFS). If not, it force-places one, ranking
     "stay near" ABOVE "stay on Hills": nearest eligible Hills tile
     first (preferring a currently-BARE tile over overriding an existing
     Sheep/Stone one), then a broadened flat, featureless tile of ANY
     base — the explicit "allow another common reachable land type"
     escape hatch this story's own follow-up discussion called out, and
     needed for real: QA's own repro set includes an all-Snow/Tundra
     polar region with zero Hills and zero Grassland/Plains within
     radius, and a separate all-Woods/Rainforest/Marsh region with zero
     featureless flat tiles either. The very last tier — any `:land`
     tile within radius at all, feature or relief be damned — always has
     at least one candidate (`anchor` itself), so the guarantee is
     unconditional: it never needs to reach OUTSIDE the radius, keeping
     "near spawn" a hard promise rather than a best-effort one. This
     guarantee runs AFTER the natural roll and is a pure function of the
     same `world.seed`/`frequency`/`resource_density` inputs, so it
     stays fully deterministic and cacheable like everything else here.

  Results are cached in `:persistent_term`, the same pattern (and same
  cache-invalidation discipline — bump `@cache_version` if the shape
  ever changes) `Regions` already uses for its own seed-derived state.
  """

  alias BrokenOaths.Worlds.Globe
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.Terrain
  alias BrokenOaths.Worlds.World

  @type kind :: :cattle | :sheep | :wheat | :stone | :copper
  @type tile_id :: non_neg_integer()
  @type density :: :sparse | :standard | :dense

  # Bump whenever the cached shape changes: persistent_term survives code
  # reloads, so a stale-shaped entry would otherwise leak into new code
  # (mirrors `Regions.@cache_version`). Bumped 1 -> 2 for the v0.2.1
  # playtest "resources missing" bug (issue 335f265c): this module's own
  # placement math (verified: cattle/wheat/sheep/stone all roll at the
  # expected rate on a fresh BEAM, see ResourcesTest) was never wrong,
  # but a long-lived, hot-reloaded server can have cached an EARLIER,
  # incomplete build of `candidates/1` under version 1 (see the
  # `game-state-persistence` ADR: "hot reloads and generator changes
  # invalidate cleanly" via a version bump, precisely for this case) —
  # a world visited during that window would keep serving whatever
  # narrower resource set (in the field report: wheat only) got cached
  # for its `{seed, frequency, density}` key forever, since nothing
  # about a placement bugfix itself changes those key inputs. Bumping
  # forces every world to recompute under the current, correct logic.
  #
  # Bumped 2 -> 3 for the playtest "resources everywhere" report (issue
  # 3e1159d1, story 905 rules 7701-7703): `@rate` below dropped to a
  # sparser Civ 6-like default, an in-place value change to the same
  # `build_map/1` shape a stale `persistent_term` entry under version 2
  # would otherwise keep serving forever for a world visited during a
  # hot-reload window, exactly the same class of staleness the 1 -> 2
  # bump above already documents.
  #
  # Bumped 3 -> 4 for story 911 (Copper, the first STRATEGIC resource):
  # `candidates/1`'s hills clause now lists a third kind, changing
  # `build_map/1`'s own output shape for any world with at least one
  # eligible hills tile that both Sheep and Stone missed — the exact
  # same "placement logic changed, but the cache key's own inputs
  # (seed/frequency/density) didn't" staleness class the two bumps
  # above already document.
  #
  # Bumped 4 -> 5 for the story 911 Copper-reachability fix (QA issue
  # 78e938bb): Copper now rolls against its own `@copper_rate` instead
  # of the shared `@rate`, AND `build_map/1` layers a per-region
  # reachability guarantee on top (see the moduledoc's own "Copper
  # reachability" section) — both change `build_map/1`'s output for any
  # world that has at least one spawnable region, the same staleness
  # class every bump above already documents.
  @cache_version 5

  # Per-eligible-tile placement chance for Cattle/Wheat/Sheep/Stone.
  # Retuned for the "resources everywhere" playtest fix (issue
  # 3e1159d1): the OLD values echoed Civ VI's own `iStandardPercentage`
  # (~28%, `civ6_resources.md` §3) literally, but that rate is per
  # ELIGIBLE tile (grassland/plains/hills only, per-terrain-gated
  # `candidates/1` below), not per LAND tile — and it measurably put a
  # resource on ~14-20% of every LAND tile once hills' own double-roll
  # (Sheep then Stone, see `place/3`) is folded in, nowhere near Civ 6's
  # actual early-game density. Story 905's shaped target (criteria
  # 7701/7702) is ~7% of LAND tiles at STANDARD — roughly one resource
  # per 12-15 land tiles. `:standard` 0.12 lands the mesh-wide average
  # right at that target (measured ~7.1% across a ten-seed sample at the
  # default frequency — `ResourcesTest`'s own "a standard-density world
  # places roughly 7%" regression pins this down precisely); `:sparse`/
  # `:dense` are exact halvings/doublings of the new standard (0.06 /
  # 0.24, averaging ~3.9% / ~13.8% on the same sample) — the same
  # relative spread the old sparse/standard/dense trio had (~0.5x / ~2x),
  # just anchored to the new, lower midpoint, so the per-world density
  # slider (criterion 7651/7703) still spans meaningfully sparser-to-
  # richer worlds.
  @rate %{sparse: 0.06, standard: 0.12, dense: 0.24}

  # Copper's OWN placement chance (story 911 follow-up, QA issue
  # 78e938bb) — no longer reuses `@rate`. Copper still checks LAST in
  # `candidates/1`'s hills priority (after Sheep and Stone), so its
  # actual land-tile contribution is `(1 - @rate)^2 * @copper_rate` per
  # hills tile — strictly smaller than a fresh top-priority resource's
  # would be at the same nominal rate, and Sheep/Stone's own rolls
  # (still against `@rate`) are completely untouched by this value.
  # ~1.17x `@rate` at every tier: raises the odds Copper actually claims
  # a bare hills tile (was ~9.3% of bare hills tiles at standard density
  # under the old shared rate; ~10.9% now) — deliberately a MODEST bump,
  # not the largest one tried. An initial, much more aggressive rate
  # (~1.7x `@rate`) measurably pushed `ResourcesTest`'s tuned 5-9%
  # standard-density band past its own ceiling on some seeds (seed 33 at
  # real gameplay scale: 9.26%) before the guarantee below even ran, so
  # it was dialed back — this value keeps every sampled seed's standard-
  # density coverage (7.0%-8.8%, five-seed real-scale sample) inside the
  # band with margin. The actual reachability GUARANTEE
  # (`guarantee_copper_near_spawns/2`) does the real work; this rate
  # bump just makes the natural roll already agree with the guarantee
  # more often, so the deterministic override rarely has to fire on a
  # real seed.
  @copper_rate %{sparse: 0.07, standard: 0.14, dense: 0.28}

  # Hex-step BFS radius (land tiles only, same region) around a
  # spawnable region's own `Regions.central_land_tiles/2` anchor within
  # which `guarantee_copper_near_spawns/2` requires a reachable Copper
  # tile — "a few tiles of spawn, no boat required" per the QA issue's
  # own ask. Generous enough to comfortably contain a size-6 city's
  # eventual 12-tile territory (story 883's growth cap) plus a turn or
  # two of scouting room, without reaching so far it stops meaning
  # "near".
  @copper_guarantee_radius 6

  @doc """
  The resource at `tile_id`, or `nil` for a bare tile — bonus
  (`:cattle`/`:sheep`/`:wheat`/`:stone`) or strategic (`:copper`,
  story 911) alike; this read makes no distinction and applies no
  reveal gating (see the moduledoc's own "Copper is placed here
  UNCONDITIONALLY" note). The sanctioned read every caller (including
  `BrokenOathsSpex.Fixtures.resource_at/2`) goes through — nothing
  outside this module ever computes placement directly.
  """
  @spec at(World.t(), tile_id()) :: kind() | nil
  def at(world, tile_id) do
    world
    |> resource_map()
    |> Map.get(tile_id)
  end

  # -------------------------------------------------------------------
  # The full map, cached
  # -------------------------------------------------------------------

  defp resource_map(world) do
    cached(cache_key(world), fn -> build_map(world) end)
  end

  defp cache_key(world) do
    {__MODULE__, @cache_version, world.seed, world.frequency, density(world)}
  end

  defp density(%{resource_density: density}) when density in [:sparse, :standard, :dense],
    do: density

  defp density(_world), do: :standard

  defp cached(key, build) do
    case :persistent_term.get(key, nil) do
      nil ->
        value = build.()
        :persistent_term.put(key, value)
        value

      value ->
        value
    end
  end

  defp build_map(world) do
    rate = Map.fetch!(@rate, density(world))
    copper_rate = Map.fetch!(@copper_rate, density(world))
    mesh = Globe.get(world.frequency)

    base =
      for {tile_id, _tile} <- mesh.tiles,
          Regions.tile_class(world, tile_id) == :land,
          resource = place(world, tile_id, rate, copper_rate),
          resource != nil,
          into: %{} do
        {tile_id, resource}
      end

    guarantee_copper_near_spawns(world, base)
  end

  # -------------------------------------------------------------------
  # Per-tile placement
  # -------------------------------------------------------------------

  defp place(world, tile_id, rate, copper_rate) do
    world
    |> Regions.terrain(tile_id)
    |> candidates()
    |> Enum.find(&(roll(world.seed, tile_id, &1) < rate_for(&1, rate, copper_rate)))
  end

  defp rate_for(:copper, _rate, copper_rate), do: copper_rate
  defp rate_for(_kind, rate, _copper_rate), do: rate

  # Fixed priority order: Cattle > Wheat > Sheep > Stone > Copper.
  # Grassland and plains are each eligible for exactly one resource;
  # hills lists all three hills-eligible kinds, checked in that order
  # (story 911 appends `:copper` last — see the moduledoc for why).
  defp candidates(%Terrain{base: :grassland, relief: :flat, feature: nil}), do: [:cattle]
  defp candidates(%Terrain{base: :plains, relief: :flat, feature: nil}), do: [:wheat]

  defp candidates(%Terrain{relief: :hills, feature: feature}) when feature != :woods,
    do: [:sheep, :stone, :copper]

  defp candidates(%Terrain{}), do: []

  # A deterministic roll in [0.0, 1.0) for `{seed, tile_id, kind}`.
  defp roll(seed, tile_id, kind) do
    state = :rand.seed_s(:exsss, seed_tuple({seed, tile_id, kind}))
    {value, _state} = :rand.uniform_s(state)
    value
  end

  defp seed_tuple(term) do
    h = :erlang.phash2(term, 1_000_000_000)
    {h, h * 7 + 13, h * 31 + 97}
  end

  # -------------------------------------------------------------------
  # Copper reachability guarantee (QA issue 78e938bb, story 911
  # follow-up) — see the moduledoc's own "Copper reachability" section.
  # -------------------------------------------------------------------

  defp guarantee_copper_near_spawns(world, map) do
    world
    |> Regions.spawnable()
    |> Enum.reduce(map, &guarantee_copper_in_region(world, &1, &2))
  end

  defp guarantee_copper_in_region(world, region_id, map) do
    region_set = region_tile_set(world, region_id)

    case Regions.central_land_tiles(world, region_id) do
      [] ->
        map

      [anchor | _] ->
        nearby = nearby_land_depths(world, region_set, anchor, @copper_guarantee_radius)

        if Enum.any?(Map.keys(nearby), &(Map.get(map, &1) == :copper)) do
          map
        else
          ensure_reachable_copper(world, map, nearby)
        end
    end
  end

  defp region_tile_set(world, region_id) do
    world
    |> Regions.partition()
    |> Map.fetch!(:regions)
    |> Map.fetch!(region_id)
    |> MapSet.new()
  end

  # Land-only, same-region BFS depths from `anchor`, bounded at
  # `radius` hex-steps — every candidate this function's caller ever
  # considers is therefore, by construction, already "near spawn"; see
  # `ensure_reachable_copper/2`'s own comment for why this makes the
  # guarantee unconditional rather than needing a farther, whole-region
  # fallback tier.
  defp nearby_land_depths(world, region_set, anchor, radius) do
    grow_land_depths(world, region_set, %{anchor => 0}, [anchor], 0, radius)
  end

  defp grow_land_depths(_world, _region_set, depths, _frontier, depth, radius)
       when depth >= radius,
       do: depths

  defp grow_land_depths(world, region_set, depths, frontier, depth, radius) do
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
        depths

      _ ->
        depths = Enum.reduce(next, depths, &Map.put(&2, &1, depth + 1))
        grow_land_depths(world, region_set, depths, next, depth + 1, radius)
    end
  end

  # Priority order for the forced placement, "stay near" ranked ABOVE
  # "stay on Hills": a Hills tile first, then (only when no Hills tile
  # sits this close — QA's own polar-region repro) a broadened flat,
  # featureless tile (any base — see the moduledoc's Civ 6 Desert/
  # Tundra precedent), and finally — only when the ENTIRE nearby
  # neighborhood is Hills-less AND has no featureless flat tile either
  # (QA's own all-forest repro: Woods/Rainforest/Marsh everywhere within
  # radius) — ANY land tile at all within radius, feature or relief be
  # damned. This last tier always has at least one candidate (`anchor`
  # itself, depth 0, is guaranteed present and is `:land` by
  # `Regions.central_land_tiles/2`'s own contract), so this function
  # ALWAYS places a reachable Copper tile — no whole-region fallback
  # tier is needed (an earlier build had one; it was silently
  # unreachable dead code once this final tier existed, so it was
  # removed rather than kept as a footgun for a future edit). Each tier
  # prefers a currently-BARE tile, tie-broken by shallowest depth then
  # lowest tile id, so this only steals a Sheep/Stone placement when
  # every eligible-or-better tile already carries one.
  defp ensure_reachable_copper(world, map, depths) do
    ids = Map.keys(depths)

    with :none <- best_candidate(world, map, depths, ids, &hills_eligible?/1),
         :none <- best_candidate(world, map, depths, ids, &flat_eligible?/1) do
      {:ok, tile_id} = best_candidate(world, map, depths, ids, fn _terrain -> true end)
      Map.put(map, tile_id, :copper)
    else
      {:ok, tile_id} -> Map.put(map, tile_id, :copper)
    end
  end

  defp best_candidate(world, map, depths, ids, terrain_eligible?) do
    case Enum.filter(ids, &terrain_eligible?.(Regions.terrain(world, &1))) do
      [] -> :none
      candidates -> {:ok, pick_nearest_bare(map, depths, candidates)}
    end
  end

  defp pick_nearest_bare(map, depths, candidates) do
    candidates
    |> Enum.map(&{&1, {bare_rank(map, &1), Map.fetch!(depths, &1), &1}})
    |> Enum.min_by(fn {_id, key} -> key end)
    |> elem(0)
  end

  defp bare_rank(map, tile_id), do: if(Map.get(map, tile_id) == nil, do: 0, else: 1)

  defp hills_eligible?(%Terrain{relief: :hills, feature: feature}), do: feature != :woods
  defp hills_eligible?(%Terrain{}), do: false

  # Broadened terrain: ANY flat, featureless land tile, regardless of
  # base — not just Grassland/Plains. A region whose nearby
  # neighborhood is entirely polar (Snow/Tundra, no Hills, no
  # Grassland/Plains within radius — a real case this module's own test
  # suite caught) still needs a placement THAT STAYS NEAR SPAWN; the
  # moduledoc's own terrain intro already notes Civ 6 itself places
  # Copper on Desert/Tundra in later expansions, so leaning on those
  # bases here for this pure access-gate resource (no yield of its own
  # to balance) is a deliberate, in-bounds choice, not an arbitrary
  # hack. `feature == nil` is kept strict (no Woods/Marsh/Rainforest)
  # so the tile stays a plain, unremarkable one — exactly as
  # unremarkable as a bare Grassland/Plains tile would be.
  defp flat_eligible?(%Terrain{relief: :flat, feature: nil}), do: true
  defp flat_eligible?(%Terrain{}), do: false
end
