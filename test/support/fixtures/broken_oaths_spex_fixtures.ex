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
end
