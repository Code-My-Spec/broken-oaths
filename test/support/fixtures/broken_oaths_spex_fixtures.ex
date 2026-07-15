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
end
