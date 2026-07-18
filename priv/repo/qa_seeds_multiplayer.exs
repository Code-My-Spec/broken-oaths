# Multiplayer QA seed — idempotent AND self-healing. Run with:
#
#     mix run priv/repo/qa_seeds_multiplayer.exs
#
# Builds on `priv/repo/qa_seeds.exs`'s patterns (confirmed user via the
# real magic-link flow, a deliberately small crash-safe world) to stage
# story 901 (Cooperative Barbarian Fighting) and future two-player
# scenarios: two confirmed QA players, joined and founded in a
# fast-turn world, each with a real warrior standing adjacent to the
# SAME barbarian camp — ready for an immediate cooperative assault
# through the browser, no manual setup required. Mutual discovery
# (`game_known_players`) is seeded too, so chat/alliance panels are
# unlocked from the first page load.
#
# ## Why "self-healing", not just "idempotent"
#
# `turn_seconds: 5` (below) makes `BrokenOaths.Game.WorldServer`'s own
# wall-clock catch-up (`catch_up/1` — "if `turn_started_at` is more
# than `turn_seconds` stale on boot, missed ticks run synchronously
# before the server accepts requests") fire on the VERY FIRST
# `BrokenOaths.Game.*` call this script makes (`join_world`), any time
# this world has sat dormant for more than a few seconds since its
# `turn_started_at` was last refreshed — which is every single time
# this script (or the dev server) next touches it, since a script run
# is the only thing keeping the `WorldServer` process alive at all.
# Those synchronous catch-up ticks are NOT idle: every camp's 3-turn
# spawn cadence (`BrokenOaths.Game.Camps.advance/2`) runs for real, and
# a camp that reaches readiness spawns a real barbarian warrior that
# the NEXT tick's barbarian-AI loop can walk into an adjacent unit and
# attack. Confirmed empirically while building this script: two runs
# of an EARLIER, naively-idempotent version of this file, a couple of
# minutes apart, were enough for a camp to spawn a warrior directly
# onto its own tile and land a real hit on the adjacent QA warrior
# (100 -> 26 HP) before either player ever logged in. A `turn_seconds`
# this fast makes that gap dangerous regardless of exactly how it's
# triggered (a second `mix run`, or simply the dev server's own next
# boot after this script exits).
#
# Rather than fight that mechanic, this script neutralizes it every
# time it runs: after joining/founding (unavoidably live `Game` calls,
# so unavoidably a catch-up trigger), it unconditionally resets every
# camp to pristine (100 HP, counter 0, not destroyed), deletes every
# barbarian warrior, resets both cities' HP, and force-repositions both
# players' warriors to full HP on their target tiles — via raw `Repo`
# writes, deliberately bypassing the (now possibly stale) in-memory
# `WorldServer` the join/found calls just booted, so nothing further
# can race these writes within this same run. It finishes by resetting
# `worlds.turn_started_at` to "now" as its LAST write, maximizing the
# safe window before the next catch-up (whenever the dev server next
# boots this world). **Operationally: run this script again,
# immediately before starting the dev server, if any meaningful time
# passed between a previous run and when QA actually begins — it fully
# repairs whatever wall-clock catch-up did in between.**
#
# Camp visibility for the player whose warrior ISN'T in their own home
# region is seeded directly into `game_explorations`, not via an
# `advance_turn` tick (deliberately — seeding it this way needs no tick
# at all, so it carries none of the catch-up risk above).
#
# ## World choice
#
# Frequency 8 is the crash-safe, easily-fillable size proven by "QA
# World (Fill Test)" (seed 111222, see `qa_seeds.exs`) — 642 tiles,
# exactly two spawnable regions (`Regions.spawnable/1`'s 175-tile
# habitability floor), perfect for exactly two players. `worlds.seed`
# carries a unique index, so this world needs its OWN seed distinct
# from 111222 — 901901 was probed offline (frequency 8, no persisted
# world required — `Regions.spawnable/1` and `Spawner.spawn_player/2`
# are both pure functions of seed/frequency) before being hardcoded
# here: exactly two spawnable regions, both place a player without
# raising. Do NOT change this seed without re-probing the same way (see
# `.code_my_spec/qa/plan.md`'s frequency-5/6 Spawner-crash warning —
# frequency 8 ITSELF is proven safe across every seed tried in that QA
# session, but a DIFFERENT seed at any frequency is not, until
# checked).

import Ecto.Query

alias BrokenOaths.{Game, Repo, Users, Worlds}
alias BrokenOaths.Game.{Camp, City, CityDefense, Exploration, KnownPlayer, Production, Unit}
alias BrokenOaths.Users.UserToken
alias BrokenOaths.Worlds.Regions

qa_password = "qa-password-123!"

ensure_qa_user = fn email ->
  case Users.get_user_by_email(email) do
    nil ->
      {:ok, user} = Users.register_user(%{email: email})

      # Confirm via the magic-link flow (same path production uses).
      {encoded_token, user_token} = UserToken.build_email_token(user, "login")
      Repo.insert!(user_token)
      {:ok, {user, _expired}} = Users.login_user_by_magic_link(encoded_token)

      {:ok, {user, _expired}} = Users.update_user_password(user, %{password: qa_password})
      IO.puts("Created QA user #{email}")
      user

    user ->
      IO.puts("QA user already exists: #{email}")
      user
  end
end

user_a = ensure_qa_user.("qa-901-a@broken-oaths.test")
user_b = ensure_qa_user.("qa-901-b@broken-oaths.test")

multiplayer_world =
  case Enum.find(Worlds.list_worlds(), &(&1.name == "QA World (Multiplayer)")) do
    nil ->
      {:ok, world} =
        Worlds.create_world(%{
          name: "QA World (Multiplayer)",
          seed: 901_901,
          frequency: 8,
          # 60s (not the QA-default fast tick): a cooperative camp
          # assault is a multi-turn, two-player browser flow — a fast
          # tick lets wall-clock catch-up field barbarians that kill the
          # staged warriors before a tester reaches the attack phase.
          turn_seconds: 60
        })

      IO.puts("Created QA World (Multiplayer) (seed 901901, frequency 8, turn_seconds 5)")
      world

    world ->
      IO.puts("QA World (Multiplayer) already exists (id #{world.id})")
      world
  end

# --- Join + found (real Game API: claims a region, spawns a Lord +
# Settler; founding consumes the Settler, creates a size-1 city, and —
# a player's FIRST founding only — seeds 5-8 wilderness camps in/around
# their own region, story 892). This is the one unavoidable place that
# lazily boots this world's `WorldServer` and, if it had gone dormant,
# triggers wall-clock catch-up — see this file's top doc. Everything
# from here on force-repairs whatever that catch-up may have produced.

ensure_joined = fn user ->
  {:ok, player} = Game.join_world(multiplayer_world, user)
  player
end

player_a = ensure_joined.(user_a)
player_b = ensure_joined.(user_b)

ensure_founded = fn user, player ->
  case Game.player_cities(multiplayer_world, user) do
    [city | _] ->
      city

    [] ->
      [settler] =
        for u <- Game.player_units(multiplayer_world, user), u.type == :settler, do: u

      :ok = Game.found_city(multiplayer_world, user, settler.id)
      [city] = Game.player_cities(multiplayer_world, user)
      IO.puts("#{user.email} founded city ##{city.id} (player ##{player.id})")
      city
  end
end

city_a = ensure_founded.(user_a, player_a)
city_b = ensure_founded.(user_b, player_b)

# --- Repair pass: force this world's wilderness back to pristine no
# matter what wall-clock catch-up just did above. Camps are ownerless
# wilderness state (`Game.Camp`'s doc) and cities regen HP naturally
# anyway — resetting either here doesn't erase real player progress,
# only combat noise this script itself is responsible for not leaving
# behind. Deliberately raw `Repo` writes, not `Game.*` calls: the
# `WorldServer` booted above may be holding stale in-memory state from
# BEFORE these writes, but nothing in the rest of this script reads
# through it again, so that staleness never surfaces.

{cleared_camps, _} =
  Repo.update_all(from(c in Camp, where: c.world_id == ^multiplayer_world.id),
    set: [hp: Camp.max_hp(), spawn_counter: 0, destroyed_at: nil]
  )

{cleared_barbarians, _} =
  Repo.delete_all(
    from(u in Unit, where: u.world_id == ^multiplayer_world.id and u.type == :barbarian_warrior)
  )

Repo.update_all(from(c in City, where: c.world_id == ^multiplayer_world.id),
  set: [hp: CityDefense.max_hp(), production_halted_until: nil]
)

if cleared_barbarians > 0 do
  IO.puts(
    "Repair: wall-clock catch-up had spawned #{cleared_barbarians} barbarian warrior(s) across #{cleared_camps} camp(s) — cleared, camps reset to full HP"
  )
end

# --- Pick the shared target camp: lowest camp id (deterministic across
# re-runs) with at least two free adjacent land tiles, read fresh from
# the DB (not `Game.list_camps`, which would read the WorldServer's
# possibly-stale in-memory copy from before the repair pass above).
# Player one founds first, and `WorldServer`'s wilderness placement
# inserts "near" camps (inside the founder's own region) before "far"
# ones, so this is very likely player one's own near camp — already
# visible to them with no exploration needed at all.

camps = Repo.all(from c in Camp, where: c.world_id == ^multiplayer_world.id, order_by: c.id)

if camps == [] do
  raise "no camps exist in #{multiplayer_world.name} — founding should have seeded wilderness camps"
end

lord_tiles =
  for u <- Game.player_units(multiplayer_world, user_a) ++ Game.player_units(multiplayer_world, user_b),
      u.type == :lord,
      do: u.tile_id

occupied_base = MapSet.new([city_a.tile_id, city_b.tile_id | lord_tiles])

{target_camp, target_tile_a, target_tile_b} =
  camps
  |> Enum.find_value(fn camp ->
    candidates =
      multiplayer_world
      |> Regions.adjacent_tiles(camp.tile_id)
      |> Enum.uniq()
      |> Enum.filter(&(Regions.tile_class(multiplayer_world, &1) == :land))
      |> Enum.reject(&MapSet.member?(occupied_base, &1))
      |> Enum.sort()

    case candidates do
      [tile_1, tile_2 | _rest] -> {camp, tile_1, tile_2}
      _ -> nil
    end
  end) || raise "no camp in #{multiplayer_world.name} has two free adjacent land tiles"

# --- Force each player's warrior onto its target tile at full HP —
# inserted fresh, or unconditionally repaired in place if one already
# exists (fixes both a stale position AND any combat damage a prior
# run's catch-up may have dealt it).

force_warrior_at = fn user, player, tile_id ->
  stats = Production.unit_stats(:warrior)

  attrs = %{
    world_id: multiplayer_world.id,
    player_id: player.id,
    type: :warrior,
    tile_id: tile_id,
    hp: stats.hp,
    max_hp: stats.hp,
    movement: stats.movement,
    max_movement: stats.movement
  }

  case Repo.all(
         from u in Unit,
           where:
             u.world_id == ^multiplayer_world.id and u.player_id == ^player.id and
               u.type == :warrior
       ) do
    [] ->
      {:ok, unit} = %Unit{} |> Unit.changeset(attrs) |> Repo.insert()
      IO.puts("Spawned warrior ##{unit.id} for #{user.email} at tile #{tile_id}")
      unit

    [existing | extra] ->
      # This script only ever creates one warrior per player — clear
      # any hand-seeded extras rather than leave them stray.
      if extra != [], do: Repo.delete_all(from(u in Unit, where: u.id in ^Enum.map(extra, & &1.id)))
      {:ok, unit} = existing |> Unit.changeset(attrs) |> Repo.update()
      IO.puts("Repaired warrior ##{unit.id} for #{user.email}: full HP at tile #{tile_id}")
      unit
  end
end

warrior_a = force_warrior_at.(user_a, player_a, target_tile_a)
warrior_b = force_warrior_at.(user_b, player_b, target_tile_b)

# --- Lower the shared target camp so the cooperative assault and the
# proportional-bounty-split assertion finish within ~2 turns, before
# the camp's own 3-turn spawn cadence can field barbarians that would
# kill the staged warriors. The split logic is HP-independent (it
# divides the fixed bounty by damage dealt), so a lower starting HP is
# a faithful fixture for the split math. ---
Repo.update_all(from(c in Camp, where: c.id == ^target_camp.id), set: [hp: 40])
target_camp = Repo.get!(Camp, target_camp.id)
IO.puts("Shared target camp ##{target_camp.id} lowered to #{target_camp.hp} HP for a fast cooperative kill")

# --- Mutual discovery (story 899's `game_known_players`, both
# directions) so chat/alliance are unlocked from the first page load —
# normally written by `Discovery.new_contacts/2` at a real tick, seeded
# directly here since this script never ticks (see top doc). ---

ensure_known = fn viewer, discovered ->
  case Repo.get_by(KnownPlayer,
         world_id: multiplayer_world.id,
         viewer_player_id: viewer.id,
         discovered_player_id: discovered.id
       ) do
    nil ->
      %KnownPlayer{}
      |> KnownPlayer.changeset(%{
        world_id: multiplayer_world.id,
        viewer_player_id: viewer.id,
        discovered_player_id: discovered.id
      })
      |> Repo.insert!()

      :ok

    _existing ->
      :ok
  end
end

ensure_known.(player_a, player_b)
ensure_known.(player_b, player_a)

# --- Camp visibility for both players (`WorldServer`'s fog rule: home
# region OR explored) — seeded directly into `game_explorations`
# rather than via a tick, so it carries none of the catch-up risk this
# file's top doc describes. Additive: never drops tiles a player
# already explored for real. ---

ensure_camp_explored = fn player ->
  case Repo.get_by(Exploration, world_id: multiplayer_world.id, player_id: player.id) do
    nil ->
      %Exploration{}
      |> Exploration.changeset(%{
        world_id: multiplayer_world.id,
        player_id: player.id,
        explored: [target_camp.tile_id]
      })
      |> Repo.insert!()

    %{explored: explored} = exploration ->
      unless target_camp.tile_id in explored do
        exploration
        |> Exploration.changeset(%{explored: [target_camp.tile_id | explored]})
        |> Repo.update!()
      end
  end
end

ensure_camp_explored.(player_a)
ensure_camp_explored.(player_b)

# --- Last write, always: refresh the wall-clock anchor so the next
# time ANYTHING boots this world's `WorldServer` (the dev server's own
# next start, most likely), catch-up has the smallest possible gap to
# replay — maximizing the odds the state printed below is still exactly
# what QA finds. ---

{:ok, multiplayer_world} =
  Worlds.update_world(multiplayer_world, %{turn_started_at: DateTime.utc_now() |> DateTime.truncate(:second)})

IO.puts("""

=== QA credentials (multiplayer) ===
player A: #{user_a.email} / #{qa_password} (user id #{user_a.id}, player id #{player_a.id})
player B: #{user_b.email} / #{qa_password} (user id #{user_b.id}, player id #{player_b.id})

=== World ===
name:         #{multiplayer_world.name}
id:           #{multiplayer_world.id}
seed:         #{multiplayer_world.seed}
frequency:    #{multiplayer_world.frequency}
turn:         #{multiplayer_world.turn}
turn_seconds: #{multiplayer_world.turn_seconds}

=== Shared camp ===
camp id:   #{target_camp.id}
camp tile: #{target_camp.tile_id}
warrior A: unit ##{warrior_a.id} @ tile #{warrior_a.tile_id} (player A)
warrior B: unit ##{warrior_b.id} @ tile #{warrior_b.tile_id} (player B)

=== QA URLs (dev server, port 4050) ===
login:  http://localhost:4050/users/log-in
join:   http://localhost:4050/play
play:   http://localhost:4050/play/#{multiplayer_world.id}
globe:  http://localhost:4050/worlds/#{multiplayer_world.id}
mailbox: http://localhost:4050/dev/mailbox

NOTE: turn_seconds is 5 on this world -- if a meaningful gap (more than
a few seconds) passes between this run finishing and the dev server
actually starting, re-run this script immediately beforehand. It is
fully self-healing: it will clear any wall-clock-catch-up barbarian
spawns/damage and restore both warriors to full HP on their target
tiles no matter how much time passed.
""")
