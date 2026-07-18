defmodule BrokenOaths.Worlds.Resources do
  @moduledoc """
  Deterministic bonus-resource placement (story 905):
  `.code_my_spec/knowledge/civ6_resources.md` §2/§3/§5.

  Four bonus resources, each gated to its own eligible terrain:

    * `:cattle` — flat, featureless grassland
    * `:wheat`  — flat, featureless plains
    * `:sheep`  — hills (any base, any feature except woods)
    * `:stone`  — hills (any base, any feature except woods)

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

  A hills tile is eligible for both Sheep and Stone; ties break by a
  fixed priority (Cattle > Wheat > Sheep > Stone, per the design doc)
  — Sheep gets first claim at a hills tile, Stone only claims it if
  Sheep's own roll missed. Grassland/plains tiles never compete (each
  is eligible for exactly one resource), so the priority only ever
  matters on hills.

  Results are cached in `:persistent_term`, the same pattern (and same
  cache-invalidation discipline — bump `@cache_version` if the shape
  ever changes) `Regions` already uses for its own seed-derived state.
  """

  alias BrokenOaths.Worlds.Globe
  alias BrokenOaths.Worlds.Regions
  alias BrokenOaths.Worlds.Terrain
  alias BrokenOaths.Worlds.World

  @type kind :: :cattle | :sheep | :wheat | :stone
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
  @cache_version 2

  # Per-eligible-tile placement chance. `:standard` echoes Civ VI's own
  # `iStandardPercentage` (~28%, `civ6_resources.md` §3); `:sparse` and
  # `:dense` bracket it widely enough that the ordering `dense > sparse`
  # (story 905, criterion 7651) holds reliably at any realistic map
  # size, not just in expectation.
  @rate %{sparse: 0.15, standard: 0.28, dense: 0.55}

  @doc """
  The bonus resource at `tile_id`, or `nil` for a bare tile. The
  sanctioned read every caller (including
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

  # Fixed priority order: Cattle > Wheat > Sheep > Stone. Grassland and
  # plains are each eligible for exactly one resource; hills lists both
  # animal candidates, checked in that order.
  defp candidates(%Terrain{base: :grassland, relief: :flat, feature: nil}), do: [:cattle]
  defp candidates(%Terrain{base: :plains, relief: :flat, feature: nil}), do: [:wheat]

  defp candidates(%Terrain{relief: :hills, feature: feature}) when feature != :woods,
    do: [:sheep, :stone]

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
