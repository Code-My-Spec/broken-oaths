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

  # Read-by-id counterpart to `world_fixture/1` above, same sanctioned
  # status as `tile_terrain/2` below (read-only, no player mutation).
  # `world_fixture/1` is the "don't care how the row got there"
  # shortcut most scenarios want; a scenario whose SUBJECT is world
  # *creation itself* — driving `WorldLive.New`'s create form (story
  # 905's resource-density slider) — instead only ever learns the new
  # world's id, from the redirect the create form lands on. This reads
  # the real row back by that id so later sanctioned reads
  # (`resource_at/2`, `tile_class/2`, etc.) have a real
  # `world.seed`/`world.frequency` struct to work from.
  defdelegate get_world!(id), to: BrokenOaths.Worlds

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

  # The player's current gold treasury — same sanctioned, read-only
  # status as `player_units/2` (`Game.gold/2` is a normal, non-test
  # read); also rendered as `data-test="player-gold"` on `GameLive.Play`,
  # so this is a shortcut for the SAME fact, not a new one.
  defdelegate gold(world, user), to: BrokenOaths.Game, as: :gold

  # `user`'s own Gold Bank status (`%{gold:, cap:}` — story 909), same
  # sanctioned, read-only status as `gold/2` above (`Game.bank/2` is a
  # normal, non-test read). Works for an OFFLINE owner exactly like
  # `gold/2` does — both are direct `WorldServer` state reads, not tied
  # to any live connection — so a reconciled story 908/909/910 spec can
  # read the REAL banked figure a steward/collect action is about to
  # move without first re-mounting the (offline) owner's own LiveView.
  defdelegate bank_status(world, user), to: BrokenOaths.Game, as: :bank
  defdelegate adjacent_tiles(world, tile_id), to: BrokenOaths.Worlds.Regions, as: :adjacent_tiles

  # The fog-filtered "everything user can currently see" read (own units
  # always, another's — including a barbarian's — only while visible).
  # Same sanctioned status as `player_units/2`, needed once a barbarian
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

  # A tile's bonus resource (story 905), or `nil` for a bare tile —
  # `nil | :cattle | :sheep | :wheat | :stone`. Assumed contract for
  # the not-yet-built `BrokenOaths.Worlds.Resources` module: an `at/2`
  # read taking the same `(world, tile_id)` shape as `tile_terrain/2`
  # above — resource placement is worldgen state, a pure function of
  # `(world.seed, tile_id)` (and, per story 905's per-world density
  # criterion, `world.resource_density`), never a player action. Same
  # sanctioned, read-only status as `tile_terrain/2`; specs never call
  # the generator directly, only this narrow read.
  defdelegate resource_at(world, tile_id), to: BrokenOaths.Worlds.Resources, as: :at

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
  # `set_unit_hp/3`: story 908 (tribute) needs a vassal with a
  # controlled gold treasury to skim from, but no per-turn city gold
  # YIELD mechanic exists anywhere in this codebase yet (`Game.Yields`
  # has no gold field at all; a player's gold only ever moves via
  # barbarian bounty/camp-destroy rewards, both one-off, never a
  # recurring income) — see `BrokenOaths.Game.WorldServer`'s
  # `:set_player_gold_for_test` handler for the full rationale.
  defdelegate set_player_gold(world, user, gold),
    to: BrokenOaths.Game,
    as: :set_player_gold_for_test

  # Deliberate, narrow exception to "read-only" above, same status as
  # `set_player_gold/3`: a SEPARATE per-turn gold INCOME declaration,
  # distinct from the treasury balance `set_player_gold/3` sets — see
  # `BrokenOaths.Game.WorldServer`'s `:set_player_gold_income_for_test`
  # handler for why story 908's "debt on an empty treasury" criterion
  # needs the two kept apart. Nothing reads this yet (`BrokenOaths.
  # Game.Tribute` doesn't exist) — a documented contract for that
  # future implementation, not a wired-up mechanic today.
  defdelegate set_player_gold_income(world, user, income),
    to: BrokenOaths.Game,
    as: :set_player_gold_income_for_test

  # Deliberate, narrow exception to "read-only" above, same status as
  # `set_player_gold/3`: story 919's own "holding the FREED cities wins
  # independence" happy-path criteria need a lord whose Honor is a
  # specific, deterministic figure (a maximal tyrant, Honor 0) so the
  # rebel's own city rises for SURE regardless of seed
  # (`Rebellion.Resolution.city_rises?/4`'s own `tyranny_score(0, 1.0)
  # == 100` clears every possible `city_resistance/2` in `0..100`) —
  # the same "no real source exists yet to reach this figure quickly"
  # gap `set_player_gold/3` already papers over, not a stand-in for the
  # RISING itself (`Rebellion.Resolution` still computes that for real
  # off whatever Honor this sets). See `BrokenOaths.Game.WorldServer`'s
  # `:set_player_honor_for_test` handler for the full rationale.
  defdelegate set_player_honor(world, user, honor),
    to: BrokenOaths.Game,
    as: :set_player_honor_for_test

  # Deliberate, narrow exception to "read-only" above, same status as
  # `set_unit_hp/3`: instantly restores a unit's movement to its own
  # max, bypassing the turn boundary that would normally do it. A
  # scenario needing the SAME unit to attack repeatedly (story 894
  # criterion 7559) has to recharge its spent movement between swings,
  # but a real turn boundary exposes it to a full tick's worth of
  # unrelated barbarian AI activity — including outright death, which
  # no post-hoc HP fixture can undo.
  defdelegate recharge_unit(world, unit_id), to: BrokenOaths.Game, as: :recharge_unit_for_test

  # Deliberate, narrow exception to "read-only" above, same status as
  # `set_unit_hp/3`: story 892 (`Game.Camps`) spawns real barbarians on
  # its own 3-turn cadence at camp-chosen tiles, which no combat spec
  # can steer to an exact adjacency/range for a scenario. This inserts
  # a real, ownerless `Game.Unit` (`type: :barbarian_warrior`,
  # `player_id: nil` — the same seam `Game.Combat.hostile?/2` already
  # recognizes for a camp-spawned one) directly on `tile_id`, with no
  # camp, cadence, or march involved. Returns the spawned unit's map.
  defdelegate spawn_barbarian(world, tile_id), to: BrokenOaths.Game, as: :spawn_barbarian_for_test

  # Same bridge, extended for story 893 (barbarian AI): pass a REAL
  # camp's id (from `list_camps/1`/the "game:camps" push) and the
  # placed warrior is indistinguishable from one that camp spawned
  # naturally — `Turn`'s barbarian AI loop drives it for real (moves,
  # attacks, pillages, roams) from the very next `advance_turn`, at
  # whatever exact tile the spec chose, with no long march through a
  # live hostile world needed to get either side into position.
  defdelegate spawn_barbarian(world, tile_id, camp_id),
    to: BrokenOaths.Game,
    as: :spawn_barbarian_for_test

  # Deliberate, narrow exception to "read-only" above, same status as
  # `spawn_barbarian/2`: instantly relocates ANY of the player's own
  # units to `tile_id`, bypassing movement points, pathing, and turn
  # boundaries. A scenario needing a unit at a specific (possibly
  # distant) spot — e.g. adjacent to a real, naturally-placed camp —
  # no longer marches it there over dozens of turns exposed to a live
  # hostile world just to get it into position; `:ok` or
  # `{:error, :occupied}`.
  defdelegate relocate_unit(world, unit_id, tile_id),
    to: BrokenOaths.Game,
    as: :relocate_unit_for_test

  # Deliberate, narrow exception to "read-only" above, same status as
  # `relocate_unit/3`: instantly places a COMPLETE improvement of
  # `kind` on `tile_id`, bypassing the real build (a worker standing
  # still for `Improvement.duration/1` real turns). A scenario whose
  # SUBJECT is what happens to an ALREADY-FINISHED improvement (e.g.
  # pillage, story 893 criterion 7556) no longer needs a worker exposed
  # to a live, spawning camp for the several turns a real build would
  # otherwise take just to get one to exist. Returns the improvement's
  # map (`tile_id`, `kind`, `progress`, `status`, `builder_unit_id`).
  defdelegate complete_improvement(world, tile_id, kind),
    to: BrokenOaths.Game,
    as: :complete_improvement_for_test

  # Deliberate, narrow exception to "read-only" above, same status as
  # `complete_improvement/3`: story 911's Copper access gate needs a
  # deterministic way to grant a city Copper access without depending
  # on where the world's own Copper tiles happen to fall relative to
  # wherever a settler started — appends a REAL Copper tile's id onto
  # `city_id`'s own territory. `:ok`, or `{:error, :no_copper_on_map}`
  # if this world's own placement rolled no Copper anywhere.
  defdelegate grant_copper_access(world, city_id),
    to: BrokenOaths.Game,
    as: :grant_copper_access_for_test

  # Deliberate, narrow exception to "read-only" above, same status as
  # `complete_improvement/3`: moves a barbarian directly onto `tile_id`,
  # applying pillage-on-entry as a single isolated write rather than a
  # full tick boundary. A scenario whose SUBJECT is what happens WHEN a
  # barbarian enters a tile with a completed improvement (story 893
  # criterion 7556) doesn't need the AI's own path-finding to get it
  # there (already covered elsewhere, criteria 7551/7554) — routing
  # arrival through a real multi-camp tick made the scenario hostage to
  # every OTHER camp's own same-tick spawn/movement cadence landing on
  # the exact tile needed clear. `:ok` or `{:error, :occupied}`.
  defdelegate move_barbarian(world, barbarian_id, tile_id),
    to: BrokenOaths.Game,
    as: :move_barbarian_for_test

  # Deliberate, narrow exception to "read-only" above, same status as
  # `move_barbarian/3`: destroys EVERY camp except `keep_camp_id` and
  # hard-deletes every unit already tied to one of those other camps —
  # not merely relocated, since a relocated warrior is still a live,
  # roaming actor that could wander back into range. A scenario testing
  # ONE camp's own decision (target selection, pillage-on-entry) in a
  # world that always ships with several OTHER independently-roaming
  # camps (criterion 7543) needs to eliminate those other actors
  # outright, not tolerate their incidental interference.
  defdelegate isolate_camp(world, keep_camp_id),
    to: BrokenOaths.Game,
    as: :isolate_camp_for_test

  # Deliberate, narrow exception to "read-only" above, same status as
  # `isolate_camp/2`: hard-deletes every warrior tied to `camp_id`,
  # without touching the camp itself (still alive, still spawning
  # normally afterward). `isolate_camp/2` deliberately leaves the KEPT
  # camp's own warriors alone; a scenario whose own long setup wait (no
  # shortcut exists for city growth/production) lets that SAME camp's
  # natural cadence accumulate sibling warriors before the scenario
  # deliberately places its OWN tracked one calls this immediately
  # before `spawn_barbarian/3` to guarantee that placed warrior is the
  # ONLY one anywhere in the world at that decision boundary.
  defdelegate clear_camp_warriors(world, camp_id),
    to: BrokenOaths.Game,
    as: :clear_camp_warriors_for_test

  # Story 893 (barbarian roaming/AI) doesn't exist yet, so a barbarian
  # has no owning player/session to drive an "attack" event through
  # `GameLive.Play` — this resolves an attack FROM `attacker_id`
  # directly, the same narrow-exception status as `spawn_barbarian/2`.
  defdelegate resolve_barbarian_attack(world, attacker_id, target_id),
    to: BrokenOaths.Game,
    as: :resolve_barbarian_attack_for_test

  # Deliberate, narrow exception to "read-only" above, same status as
  # `spawn_barbarian/2`: places a REAL, additional player-owned unit at
  # `tile_id` with that type's starting stats — needed to exercise a
  # SAME-CLASS stacking/collision scenario (e.g. two settlers, two
  # warriors) once the field-stacking allowance (v0.2.1 playtest issue
  # 5df5de88) means the only two units a fresh spawn actually provides
  # (a Lord and a Settler) are of DIFFERENT combat classes and so no
  # longer collide with each other. `player_id` — not `user` — since
  # `Game.player_units/2`'s own returned unit maps never expose a
  # player id to spex-land (own-vs-foreign is already resolved by the
  # time a unit map exists); callers get it back from `join_world/2`'s
  # own `{:ok, player}`, idempotent for an already-joined user.
  defdelegate spawn_unit(world, player_id, type, tile_id),
    to: BrokenOaths.Game,
    as: :spawn_unit_for_test

  # Deliberate, narrow exception to "read-only" above, same status as
  # `spawn_unit/4`: hard-deletes ANY unit outright (player-owned or a
  # barbarian) — story 895's criterion 7568 needs to retire an
  # already-served-its-purpose tracked barbarian so it can never
  # muddy a LATER observation window with a second, untracked attack
  # (relocating it is not enough: the barbarian's own camp sits within
  # its own roam radius of the very city under test, so it would
  # simply wander back within striking range on its own).
  defdelegate remove_unit(world, unit_id), to: BrokenOaths.Game, as: :remove_unit_for_test

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
