defmodule BrokenOathsSpex.Fixtures do
  @moduledoc """
  Curated bridge from BDD specs into in-app state.

  The only module that may dep on `BrokenOaths` from inside the spex
  test tree. Declared as its own top-level Boundary so the spec
  boundary (`BrokenOathsSpex`) can dep on it without inheriting
  `BrokenOaths`'s deps.

  Rule of thumb: this bridge exposes state a player brings TO the game
  (their account, a world's existence) — never state a player creates
  BY playing (units, orders, exploration). Play-state comes from
  driving GameLive.
  """

  use Boundary, top_level?: true, deps: [BrokenOaths]

  # --- Users / session ---
  defdelegate user_fixture(attrs \\ %{}), to: BrokenOaths.UsersFixtures
  defdelegate user_scope_fixture(), to: BrokenOaths.UsersFixtures
  defdelegate user_scope_fixture(user), to: BrokenOaths.UsersFixtures
  defdelegate generate_user_session_token(user), to: BrokenOaths.Users

  # --- Worlds ---
  # A world existing is server-side state (worlds are provisioned, not
  # player-created in the gameplay loop), so seeding one is sanctioned.
  defdelegate world_fixture(attrs \\ %{}), to: BrokenOaths.WorldsFixtures

  # --- Regions (sanctioned domain reads) ---
  # Region identity is deliberately invisible to players ("invisible
  # plumbing" — PM decision on story 877), so region-math criteria have
  # no UI surface to observe. These narrow reads are the sanctioned
  # shortcut for those specs; they expose seed-derived server state,
  # never let a spec mutate anything.
  defdelegate region_partition(world), to: BrokenOaths.Worlds.Regions, as: :partition
  defdelegate spawnable_regions(world), to: BrokenOaths.Worlds.Regions, as: :spawnable
  defdelegate tile_class(world, tile_id), to: BrokenOaths.Worlds.Regions, as: :tile_class

  # --- Game membership (sanctioned domain read) ---
  # Which region a player claimed is likewise invisible plumbing.
  defdelegate claimed_region(world, user), to: BrokenOaths.Game, as: :claimed_region

  # --- Game infra (sanctioned test-tick surface) ---
  # Turn boundaries are wall-clock (60s) in production; specs must never
  # sleep, so the WorldServer exposes a deterministic tick. Triggering a
  # tick is server-originated state (the timer would have done it), not
  # a player action — sanctioned.
  defdelegate advance_turn(world), to: BrokenOaths.Game, as: :advance_turn

  # Known-debt shortcut (see bdd/spex/boundaries.md): a true simultaneous
  # UI race is unconstructible in LiveViewTest (helpers are test-process
  # only). The join flow is covered end-to-end by criteria 7406/7412;
  # criterion 7407 races the same serialization point the UI path hits.
  defdelegate join_world(world, user), to: BrokenOaths.Game
  defdelegate restart_world(world), to: BrokenOaths.Game, as: :restart_world_server

  # --- Game reads for board-state assertions (sanctioned) ---
  defdelegate player_units(world, user), to: BrokenOaths.Game, as: :player_units
  defdelegate adjacent_tiles(world, tile_id), to: BrokenOaths.Worlds.Regions, as: :adjacent_tiles

  # The fog-filtered "everything user can currently see" read (own units
  # always, another's — including a barbarian's — only while visible).
  # Same sanctioned status as `player_units/2`; needed once a barbarian
  # is a real, ownerless unit rather than a second player's, so a spec
  # can re-read its post-combat HP without a player of its own to ask.
  defdelegate visible_units(world, user), to: BrokenOaths.Game, as: :units_visible_to

  # A tile's unit-sphere center — what the client sends when the player
  # right-clicks the globe (fog targets have no id client-side, so
  # orders travel as points). Seed-derived geometry, read-only.
  def tile_center(world, tile_id) do
    mesh = BrokenOaths.Worlds.Globe.get(world.frequency)
    BrokenOaths.Worlds.Globe.tile(mesh, tile_id).center
  end

  # Total tile count for a world's mesh frequency — lets specs iterate
  # "every tile" (e.g. searching for a narrow spot) without hardcoding
  # a size. Seed/frequency-derived geometry, same status as tile_class.
  def tile_count(world), do: BrokenOaths.Worlds.Globe.tile_count(world.frequency)

  # --- City loop (stories 878-883): sanctioned domain reads ---
  # A city is state the SUT produces by founding/growing/producing —
  # never seeded directly. Specs create and mutate cities exclusively
  # by driving GameLive.Play (`found_city`, `select_city`,
  # `queue_production`, `assign_worked_tile`, `rename_city`,
  # `start_improvement`); this is read-only, same status as
  # `player_units`. Expected city shape: `id`, `name`, `tile_id`,
  # `size`, `food`, `food_threshold`, `production`, `queue`
  # (`[%{id:, type:, banked:, cost:}]`, head = current), `territory`
  # (`[tile_id]`), `worked_tiles` (`[tile_id]`, excludes the free
  # center).
  defdelegate player_cities(world, user), to: BrokenOaths.Game, as: :player_cities

  # A tile's terrain descriptor (`%{base:, relief:, feature:}`, see
  # `BrokenOaths.Worlds.Terrain`) — seed-derived geometry exactly like
  # `tile_class`/`tile_center`, just the finer-grained view yield and
  # founding criteria need (grassland founding spots, farm/mine
  # eligibility, yield-stacking terrain combos).
  def tile_terrain(world, tile_id) do
    mesh = BrokenOaths.Worlds.Globe.get(world.frequency)
    %{terrain: terrain} = BrokenOaths.Worlds.Generator.generate_maps(world.seed, mesh)
    Map.fetch!(terrain, tile_id)
  end

  # A tile's completed improvement (`nil | :farm | :mine | :road`) —
  # gameplay state a worker creates BY playing, so read-only here too;
  # specs build improvements exclusively via `start_improvement`.
  defdelegate tile_improvement(world, tile_id), to: BrokenOaths.Game, as: :tile_improvement

  # Deliberate, narrow exception to "read-only" above: healing
  # (criterion 7480, story 881) can only be observed starting from a
  # damaged unit, and this epic's only damage source — combat — is
  # explicitly out of scope (future barbarian/combat stories). There
  # is no UI action that damages a unit yet. Rather than leave healing
  # untestable, this is a stand-in for "a unit that took a hit," the
  # same way `advance_turn` stands in for the wall-clock timer — it
  # sets HP directly and nothing else. Revisit/remove once a combat
  # story lands and can supply real damage.
  defdelegate set_unit_hp(world, unit_id, hp), to: BrokenOaths.Game, as: :set_unit_hp_for_test

  # Deliberate, narrow exception to "read-only" above, same status as
  # `set_unit_hp/3`: story 892 (`Game.Camps`) spawns real barbarians on
  # its own 3-turn cadence at camp-chosen tiles, which no combat spec
  # can steer to an exact adjacency/range for a scenario. This inserts
  # a real, ownerless `Game.Unit` (`type: :barbarian_warrior`,
  # `player_id: nil` — the same seam `Game.Combat.hostile?/2` already
  # recognizes for a camp-spawned one) directly on `tile_id`, with no
  # camp, cadence, or march involved. Returns the spawned unit's map.
  defdelegate spawn_barbarian(world, tile_id), to: BrokenOaths.Game, as: :spawn_barbarian_for_test

  # Story 893 (barbarian roaming/AI) doesn't exist yet, so a barbarian
  # has no owning player/session to drive an "attack" event through
  # `GameLive.Play` — this resolves an attack FROM `attacker_id`
  # directly, the same narrow-exception status as `spawn_barbarian/2`.
  defdelegate resolve_barbarian_attack(world, attacker_id, target_id),
    to: BrokenOaths.Game,
    as: :resolve_barbarian_attack_for_test

  # --- Barbarian camps (story 892): sanctioned narrow read ---
  # A camp's existence, tile, hp, and warrior roster are spawn-time
  # server decisions — exactly the same status as region identity
  # above ("region math criteria have no UI surface to observe"). Fog
  # of war is a HARD constraint here (criterion 7546): an undiscovered
  # camp must never appear in a pushed payload or rendered HTML, so
  # there is no way to observe placement/count criteria (7543, 7544,
  # 7546) through the UI for camps a player hasn't scouted. This read
  # exposes only the same kind of ground-truth server fact
  # `region_partition`/`claimed_region` already expose.
  #
  # NEVER read this to assert what the player *sees* on screen — that
  # comes exclusively from the "game:camps" push event (mirroring
  # "game:cities"/"game:units") once a camp's tile is actually
  # visible/explored through GameLive.Play. Only use it to (a) plan a
  # `given_`/`when_` (e.g. "walk a unit next to this camp's tile so it
  # becomes visible") or (b) assert spawn-time facts that have no UI
  # surface by construction (counts, placement, "no new camps on a
  # second founding").
  #
  # Expected shape: `%{id:, tile_id:, hp:, warriors: [%{id:, tile_id:,
  # hp:, attack:, defense:}]}` — camp fields mirror the city marker
  # (`id`/`tile_id`/`hp`); warriors nest inside their camp because
  # story 892 only spawns them (roaming/AI is story 893). A warrior's
  # own `tile_id` is exposed so a spec can route a unit's path around
  # one without waiting on fog-filtered visibility.
  defdelegate list_camps(world), to: BrokenOaths.Game, as: :list_camps
end
