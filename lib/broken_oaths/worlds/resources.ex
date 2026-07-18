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
      (`BrokenOaths.Game.Yields.resource_bonus/1`'s `:copper` clause
      is `0F 0P`) — it is a pure ACCESS GATE for the Bronze Spearman
      (`BrokenOaths.Game.Production.can_queue?/3`'s `copper_access?`
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
  percentage bands — putting Copper last means it only ever claims a
  hills tile the other two would otherwise have left BARE, so
  Sheep/Stone's own placement is bit-for-bit unaffected by Copper's
  addition (verified: `ResourcesTest`'s eligible-terrain and hilly-
  world regressions still pass unchanged) and the land-tile percentage
  only grows by the small remainder Copper picks up on top, still
  comfortably inside the tuned 5-9% band. Grassland/plains tiles never
  compete (each is eligible for exactly one resource), so the priority
  only ever matters on hills.

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

  # Bump whenever the cached shape changes: persistent_term survives
  # code reloads, so a stale-shaped entry would otherwise leak into new
  # code (mirrors `Regions.@cache_version`). Bumped 1 -> 2 for the
  # v0.2.1 playtest "resources missing" bug (issue 335f265c): this
  # module's own placement math (verified: cattle/wheat/sheep/stone all
  # roll at the expected rate on a fresh BEAM, see ResourcesTest) was
  # never wrong, but a long-lived, hot-reloaded server can have cached
  # an EARLIER, incomplete build of `candidates/1` under version 1 (see
  # the `game-state-persistence` ADR: "hot reloads and generator changes
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
  @cache_version 4

  # Per-eligible-tile placement chance. Retuned for the "resources
  # everywhere" playtest fix (issue 3e1159d1): the OLD values echoed
  # Civ VI's own `iStandardPercentage` (~28%, `civ6_resources.md` §3)
  # literally, but that rate is per ELIGIBLE tile (grassland/plains/
  # hills only, per-terrain-gated `candidates/1` below), not per LAND
  # tile — and it measurably put a resource on ~14-20% of every LAND
  # tile once hills' own double-roll (Sheep then Stone, see `place/3`)
  # is folded in, nowhere near Civ 6's actual early-game density. Story
  # 905's shaped target (criteria 7701/7702) is ~7% of LAND tiles at
  # STANDARD — roughly one resource per 12-15 land tiles. `:standard`
  # 0.12 lands the mesh-wide average right at that target (measured
  # ~7.1% across a ten-seed sample at the default frequency —
  # `ResourcesTest`'s own "a standard-density world places roughly 7%"
  # regression pins this down precisely); `:sparse`/`:dense` are exact
  # halvings/doublings of the new standard (0.06 / 0.24, averaging
  # ~3.9% / ~13.8% on the same sample) — the same relative spread the
  # old sparse/standard/dense trio had (~0.5x / ~2x), just anchored to
  # the new, lower midpoint, so the per-world density slider (criterion
  # 7651/7703) still spans meaningfully sparser-to-richer worlds.
  #
  # Story 911 — Copper reuses this SAME `@rate` (no separate, bespoke
  # strategic-resource rate): since Copper is checked last, after Sheep
  # and Stone have already claimed their own share of hills tiles at
  # this same rate, its actual land-tile contribution is naturally
  # smaller than a fresh top-priority resource's would be (measured:
  # +0.5 to +1.5 percentage points across a multi-seed sample at real
  # gameplay scale — still comfortably inside `ResourcesTest`'s tuned
  # 5-9% standard-density band). Reusing the tuned rate, rather than
  # inventing a new number, is the literal reading of "keep it within
  # the retuned density — don't blow up the rates."
  @rate %{sparse: 0.06, standard: 0.12, dense: 0.24}

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
    mesh = Globe.get(world.frequency)

    for {tile_id, _tile} <- mesh.tiles,
        Regions.tile_class(world, tile_id) == :land,
        resource = place(world, tile_id, rate),
        resource != nil,
        into: %{} do
      {tile_id, resource}
    end
  end

  # -------------------------------------------------------------------
  # Per-tile placement
  # -------------------------------------------------------------------

  defp place(world, tile_id, rate) do
    world
    |> Regions.terrain(tile_id)
    |> candidates()
    |> Enum.find(&(roll(world.seed, tile_id, &1) < rate))
  end

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
end
