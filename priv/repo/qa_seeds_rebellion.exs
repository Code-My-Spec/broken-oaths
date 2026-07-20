# Rebellion demo QA seed — idempotent AND self-healing. Run with:
#
#     mix run priv/repo/qa_seeds_rebellion.exs
#
# Boots ONE world into the staged state the 4-beat rebellion demo
# (`.code_my_spec/qa/rebellion_demo_plan.md`) needs, doubling as the
# per-story QA journeys for 913-919. Builds on `priv/repo/
# qa_seeds_multiplayer.exs`'s patterns (confirmed magic-link QA users,
# `Game.join_world`/`Game.found_city`, raw `Repo` repair writes that
# bypass a possibly-stale WorldServer, a printed credentials/URLs/state
# summary) — read that file first if this one is unfamiliar. Diverges
# from it in three load-bearing ways, each explained below: the world
# boots PAUSED (no wall-clock catch-up gremlin to fight at all), a
# third NPC actor is built by direct insert rather than the normal
# join/spawn flow, and one city is hand-marked "occupied" to satisfy a
# precondition the rebellion mechanic itself enforces.
#
# ## Three actors, one world
#
#   1. DEMO PLAYER — a confirmed QA user, spawned + founded in region 1.
#      The demo's own protagonist: LORD of a fresh vassal in beat 1,
#      VASSAL of a strained NPC tyrant in beats 2-4.
#   2. RIVAL PLAYER — a confirmed QA user, spawned + founded in region
#      2, left fully independent, reduced to their one founded city
#      (nothing in this script ever gives them a second). Their city's
#      HP is forced low (see "One-hit break" below) and the demo
#      player's own warrior stands on a free land tile adjacent to it —
#      one capture away, ready for beat 1's siege live on camera.
#   3. NPC TYRANT LORD — NOT a real spawnable-region player (frequency 8
#      worlds have exactly two — the habitability floor,
#      `Regions.spawnable/1` — so both are spent on the two real
#      actors above). Built entirely by direct `Repo` insert: a `User`
#      that never logs in, a `Player` anchored to the world's one
#      LEFTOVER (non-spawnable, "wilderness") region, a small city
#      there so heir/realm logic has somewhere to point, and a Lord
#      unit garrisoned on it so `Feudal.lord_fallen?/2` reads `false`
#      (a tyrant who was never alive would make the story-917 "seize
#      the moment" prompt fire immediately and for the wrong reason).
#
# ## Why "self-healing" needs no wall-clock fight this time
#
# `qa_seeds_multiplayer.exs`'s own long "self-healing" doc exists
# because THAT world ticks on a real clock (`turn_seconds: 5`) and
# nothing but the dev server staying up keeps its `WorldServer` alive
# between visits — any gap longer than a few seconds lets boot-time
# catch-up (`WorldServer.catch_up/1`) replay real turns, spawning real
# barbarians onto the staged fixtures before a tester ever logs in.
#
# This world sidesteps that fight entirely by booting `paused: true`.
# `catch_up/1`'s FIRST check is `state.world.paused` — a paused world
# never replays missed turns on boot, full stop, independent of how
# long it sat dormant (`WorldServer`'s own doc: "a paused world's
# turn clock never advances on its own... Persisted so a paused QA
# world stays frozen across a server restart"). Camps never advance
# their spawn cadence, cities never regen, nothing drifts — the ONLY
# things that ever change this world's state are this script's own
# writes and whatever the demo operator deliberately does (attacks,
# moves, and the dev-only `POST /dev/qa/worlds/:id/step` control, which
# is a SEPARATE handler unaffected by the pause flag — "step" always
# works, paused or not). "Self-healing" here instead means: safe to
# re-run after a rehearsal has moved units, captured the rival's city,
# declared independence, or otherwise wandered off the staged script —
# every write below is an unconditional reset back to the canonical
# beat-1-ready state, not a guard against real-time drift.
#
# ## Gotcha #1 (resolved, not staged around): city siege has no
# "Stone Age PvP" gate at all
#
# The team brief flagged a risk that beat 1's siege might be blocked by
# the general "no Stone Age PvP" rule (`Combat.Resolver.hostile?/2`,
# story 899 criterion 7603 — two real players' UNITS are never hostile
# to each other absent a rebellion-war/protection-pact exception).
# Reading `Combat.Siege.attack_city/4` resolves this empirically: it
# says so directly in its own moduledoc — "Unlike `Resolver.hostile?/2`'s
# 'no Stone Age PvP' rule for unit-vs-unit combat, ANY player's unit
# may assault ANY OTHER player's city" — `validate_siege/3` only adds a
# MILITARY-attacker check on top of `CityDefense.validate_attack/3`'s
# movement/adjacency/not-your-own-city rules. The single gate
# `attack_city/4` actually applies is `Game.feudal_enabled?/0`, already
# `true` in both `config/dev.exs` and `config/prod.exs`. So: no special
# staging needed for beat 1 beyond what's already true of every dev
# server — a military unit standing adjacent to a rival's city can
# besiege it immediately, no war declaration, no exception, nothing.
#
# ## Gotcha #2 (staged around, not just documented): a rebellion needs
# an OCCUPIED city to work on
#
# A `Vassalage` row alone is not enough for beats 3-4 to have anything
# to DO. `Feudal.Rebellion.War`'s `declare_independence/3` and
# `independence_preview/3` both filter candidate cities through
# `rebel_occupied_cities/3`: `city.player_id == vassal_player_id AND
# city.occupied_by_player_id == lord_player_id` — i.e. only cities the
# LORD has actually captured from the vassal are eligible to "rise."
# `Rebellion.Resolution.independence_won?/3` and `crushed?/2` are both
# ALWAYS `false` for an empty `risen_city_ids` (see that module's own
# moduledoc) — a vassal with no occupied city can declare independence
# (the Vassalage still severs) but there is nothing to preview, nothing
# to rise, and beat 4's "hold N turns, win" has no city to hold. So
# this script hand-marks the demo player's OWN (one, founded) city
# `occupied_by_player_id: <npc lord>` — the fictional stand-in for "the
# tyrant already took this from you once" — never touching `player_id`
# (per the schema's own "Round-5" doc, an occupied owner still runs
# their city fully; only the tribute/levy relationship and the
# last-free-city check key off this field, so the demo player keeps
# playing it normally throughout beats 1-3). With Honor floored and
# tribute maxed (below), `Rebellion.Resolution.tyranny_score/2` comes
# out to exactly 100 — `city_rises?/4`'s own `>=` compare against a
# `0..100` resistance value means this city is GUARANTEED to rise,
# every run, regardless of its own tile's hashed resistance.
#
# ## One-hit break: the rival's city HP
#
# A size-1 city with no garrison defends at `20 + 5*1 = 25`
# (`CityDefense.defensive_strength/2`); a fresh Warrior attacks at
# effective strength 10. `Resolver.damage/3`'s Civ VI curve
# (`30 * exp(0.04 * (10 - 25)) * roll`, roll in `[0.75, 1.25]`) floors
# out at `round(30 * exp(-0.6) * 0.75) = 12` even on the worst possible
# roll. The rival's city HP is forced to 10 — strictly below that
# floor — so the demo player's staged warrior breaks it in exactly one
# `attack_city` click no matter how the roll lands, with zero counter-
# damage back (an unbroken, ungarrisoned city has no defender to
# counter with at all). The rival's own Lord unit is never garrisoned
# on the city's own tile in the first place — `City.found_city/3` founds
# on the SETTLER's tile, which `Spawner.spawn_player/2` always picks
# distinct from the Lord's own spawn tile — so this defense figure
# never has a lord's-aura wrinkle to account for.
#
# ## World choice
#
# Frequency 8 is the crash-safe, exactly-two-spawnable-regions size
# `qa_seeds_multiplayer.exs` already established (see that file's own
# "World choice" doc for the habitability-floor math). `worlds.seed`
# carries a unique index, so this world needs its own seed, offline-
# probed the same pure-function way (`Regions.spawnable/1` +
# `Simulation.Spawner.spawn_player/2`, no persisted world required)
# against every seed already claimed in this repo's other QA seeds
# (424242, 111222, 901901, 402054609, 850471216, 644595483): seed
# 913919 (a nod to the story range this demo threads together) yields
# exactly two spawnable regions (ids 0 and 1) that both place a player
# without raising, PLUS a third, non-spawnable (139-land-tile) region
# (id 2) — real wilderness, not synthesized — for the NPC tyrant's
# anchor. Do NOT change this seed without re-probing the same way.

import Ecto.Query

alias BrokenOaths.{Game, Repo, Users, Worlds}
alias BrokenOaths.Cities.{City, Production}
alias BrokenOaths.Combat.{Camp, CityDefense}
alias BrokenOaths.Diplomacy.KnownPlayer
alias BrokenOaths.Feudal.{Rebellion, Vassalage}
alias BrokenOaths.Players.Player
alias BrokenOaths.Units.Unit
alias BrokenOaths.Users.UserToken
alias BrokenOaths.Worlds.Regions

qa_password = "qa-password-123!"

ensure_qa_user = fn email ->
  case Users.get_user_by_email(email) do
    nil ->
      {:ok, user} = Users.register_user(%{email: email})

      # Confirm via the magic-link flow (same path production uses) —
      # mirrors `qa_seeds_multiplayer.exs`'s own `ensure_qa_user`.
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

# -------------------------------------------------------------------
# World — created (or found) PAUSED; see this file's top doc for why
# a paused world needs no wall-clock self-healing at all.
# -------------------------------------------------------------------

world =
  case Enum.find(Worlds.list_worlds(), &(&1.name == "QA World (Rebellion Demo)")) do
    nil ->
      {:ok, world} =
        Worlds.create_world(%{
          name: "QA World (Rebellion Demo)",
          seed: 913_919,
          frequency: 8,
          turn_seconds: 60,
          paused: true
        })

      IO.puts("Created QA World (Rebellion Demo) (seed 913919, frequency 8, paused)")
      world

    world ->
      IO.puts("QA World (Rebellion Demo) already exists (id #{world.id})")
      world
  end

# -------------------------------------------------------------------
# NPC tyrant lord — direct inserts ONLY, and deliberately BEFORE any
# `Game.*` call touches this world. `Game.join_world`/`Game.found_city`
# below are what lazily boot this world's `WorldServer`, and
# `WorldServer.init/1` loads EVERY `Player`/`City`/`Unit` row for this
# `world_id` from the DB at that moment (`load_players/1` et al.) — so
# as long as the NPC's rows exist first, the live server (and this
# script's own later `Game.set_player_honor_for_test/3` call, which
# round-trips through it) sees the NPC exactly like a real player.
# -------------------------------------------------------------------

npc_email = "qa-913-tyrant@broken-oaths.test"

npc_user =
  case Users.get_user_by_email(npc_email) do
    nil ->
      {:ok, user} = Users.register_user(%{email: npc_email})
      IO.puts("Created NPC tyrant user #{npc_email} (no login — direct insert only)")
      user

    user ->
      IO.puts("NPC tyrant user already exists: #{npc_email}")
      user
  end

# The one non-spawnable region at this seed/frequency — real wilderness
# (139 land tiles), never claimed by `Spawner.spawn_player/2` since it
# falls under the 175-tile habitability floor. Its most-central land
# tile anchors the tyrant's capital, exactly the same centrality
# `Spawner` itself uses to pick a REAL player's own spawn tile.
npc_region_id =
  (Regions.partition(world).regions |> Map.keys()) -- Regions.spawnable(world)

npc_region_id =
  case npc_region_id do
    [only] ->
      only

    other ->
      raise "expected exactly one non-spawnable wilderness region at seed #{world.seed}, got #{inspect(other)} — re-probe the seed"
  end

[npc_city_tile | _] = Regions.central_land_tiles(world, npc_region_id)

npc_player =
  case Repo.get_by(Player, world_id: world.id, user_id: npc_user.id) do
    nil ->
      {:ok, player} =
        %Player{}
        |> Player.changeset(%{
          world_id: world.id,
          user_id: npc_user.id,
          region_id: npc_region_id,
          gold: 50,
          joined_turn: 0
        })
        |> Repo.insert()

      IO.puts("Created NPC tyrant player ##{player.id} in wilderness region #{npc_region_id}")
      player

    player ->
      player
  end

npc_city =
  case Repo.get_by(City, world_id: world.id, player_id: npc_player.id) do
    nil ->
      {:ok, city} =
        %City{}
        |> City.changeset(%{
          world_id: world.id,
          player_id: npc_player.id,
          tile_id: npc_city_tile,
          name: "Tyrant's Hold",
          size: 1,
          food: 0,
          territory: [npc_city_tile],
          worked_tiles: [],
          hp: CityDefense.max_hp()
        })
        |> Repo.insert()

      IO.puts("Founded NPC capital \"Tyrant's Hold\" (city ##{city.id}) at tile #{npc_city_tile}")
      city

    city ->
      city
  end

npc_lord_stats = Production.unit_stats(:lord)

npc_lord =
  case Repo.all(from u in Unit, where: u.world_id == ^world.id and u.player_id == ^npc_player.id and u.type == :lord) do
    [] ->
      {:ok, unit} =
        %Unit{}
        |> Unit.changeset(%{
          world_id: world.id,
          player_id: npc_player.id,
          type: :lord,
          tile_id: npc_city_tile,
          hp: npc_lord_stats.hp,
          max_hp: npc_lord_stats.hp,
          movement: npc_lord_stats.movement,
          max_movement: npc_lord_stats.movement
        })
        |> Repo.insert()

      IO.puts("Spawned NPC tyrant's Lord unit ##{unit.id} garrisoned at Tyrant's Hold")
      unit

    [existing | extra] ->
      if extra != [], do: Repo.delete_all(from(u in Unit, where: u.id in ^Enum.map(extra, & &1.id)))

      {:ok, unit} =
        existing
        |> Unit.changeset(%{tile_id: npc_city_tile, hp: npc_lord_stats.hp, movement: npc_lord_stats.movement})
        |> Repo.update()

      unit
  end

# -------------------------------------------------------------------
# Demo player + rival — real confirmed QA users, joined/founded
# through the real `Game` API (this is what boots the WorldServer,
# now that the NPC's own rows already exist for it to load).
# -------------------------------------------------------------------

demo_user = ensure_qa_user.("qa-913-demo@broken-oaths.test")
rival_user = ensure_qa_user.("qa-913-rival@broken-oaths.test")

ensure_joined = fn user ->
  {:ok, player} = Game.join_world(world, user)
  player
end

demo_player = ensure_joined.(demo_user)
rival_player = ensure_joined.(rival_user)

ensure_founded = fn user, player ->
  case Game.player_cities(world, user) do
    [city | _] ->
      city

    [] ->
      [settler] =
        for u <- Game.player_units(world, user), u.type == :settler, do: u

      :ok = Game.found_city(world, user, settler.id)
      [city] = Game.player_cities(world, user)
      IO.puts("#{user.email} founded city ##{city.id} (player ##{player.id})")
      city
  end
end

demo_city = ensure_founded.(demo_user, demo_player)
rival_city = ensure_founded.(rival_user, rival_player)

# -------------------------------------------------------------------
# Repair pass: unconditionally reset every piece of staged state back
# to canonical, no matter what a prior run or a live rehearsal left
# behind — raw `Repo` writes throughout, deliberately bypassing the
# (now possibly stale) in-memory `WorldServer` the join/found calls
# above just booted, exactly like `qa_seeds_multiplayer.exs`'s own
# repair pass. Nothing below reads back through the WorldServer except
# the one `Game.set_player_honor_for_test/3` call, which round-trips
# fresh off `state.players` populated at the SAME boot the NPC's own
# pre-existing rows already fed.
# -------------------------------------------------------------------

# Re-assert paused (a rehearsal that hit `/dev/qa/worlds/:id/resume`
# should not leave the world ticking) and rewind the turn counter — a
# prior rehearsal's own `/step` clicks are combat/rebellion-timing
# noise, not part of the staged invariants below, but resetting them
# too keeps every re-run's printed summary (and the on-screen turn
# counter) looking like a truly fresh boot rather than a leftover
# rehearsal number.
{:ok, world} = Worlds.update_world(world, %{paused: true, turn: 0})

# Wilderness back to pristine (mirrors qa_seeds_multiplayer.exs).
Repo.update_all(from(c in Camp, where: c.world_id == ^world.id),
  set: [hp: Camp.max_hp(), spawn_counter: 0, destroyed_at: nil]
)

Repo.delete_all(from(u in Unit, where: u.world_id == ^world.id and u.type == :barbarian_warrior))

# Any temporary rebellion army from a prior live "declare independence"
# rehearsal, and the Rebellion row(s) it belonged to — a fresh take on
# beats 3-4 needs both gone.
Repo.delete_all(from(u in Unit, where: u.world_id == ^world.id and u.temporary == true))
Repo.delete_all(from(r in Rebellion, where: r.world_id == ^world.id))

# Every city back to full HP, unoccupied, production unhalted — then
# the two staged exceptions (demo player's own capital marked occupied
# by the tyrant; the rival's re-lowered to a one-hit break) are
# re-applied as the LAST writes for those two rows, so they always win
# over this general reset.
Repo.update_all(from(c in City, where: c.world_id == ^world.id),
  set: [hp: CityDefense.max_hp(), production_halted_until: nil, occupied_by_player_id: nil]
)

Repo.update_all(from(c in City, where: c.id == ^demo_city.id), set: [occupied_by_player_id: npc_player.id])
Repo.update_all(from(c in City, where: c.id == ^rival_city.id), set: [hp: 10])
rival_city = Repo.get!(City, rival_city.id)

IO.puts(
  "Repair: demo capital ##{demo_city.id} marked occupied by the tyrant, rival capital ##{rival_city.id} forced to #{rival_city.hp} HP"
)

# Any Vassalage the rival picked up from a rehearsal that actually
# captured their city — they must read fully INDEPENDENT.
Repo.delete_all(from(v in Vassalage, where: v.world_id == ^world.id and v.vassal_player_id == ^rival_player.id))

# The demo player's own oath to the tyrant: maxed tribute, high strain,
# always active, Oath screen freshly pending (so a rehearsal's own
# Hidden Agenda pick never leaks into the next take).
vassalage_attrs = %{
  world_id: world.id,
  lord_player_id: npc_player.id,
  vassal_player_id: demo_player.id,
  tribute_rate: 1.0,
  oath_strain: 90,
  hidden_agenda: nil,
  contract_terms: %{},
  status: :active
}

vassalage =
  case Repo.get_by(Vassalage, world_id: world.id, vassal_player_id: demo_player.id) do
    nil ->
      {:ok, v} = %Vassalage{} |> Vassalage.changeset(vassalage_attrs) |> Repo.insert()
      IO.puts("Created demo player's Vassalage to the tyrant (##{v.id})")
      v

    existing ->
      {:ok, v} = existing |> Vassalage.changeset(vassalage_attrs) |> Repo.update()
      v
  end

# The tyrant's own Honor, floored — read fresh: the NPC's `Player` row
# already existed before this world's `WorldServer` booted above, so
# `find_player/2` inside the `:set_player_honor_for_test` handler finds
# it. Honor 0 + tribute 1.0 -> `tyranny_score/2` == 100, guaranteeing
# the demo capital rises the instant independence is declared (see this
# file's top doc, "Gotcha #2").
:ok = Game.set_player_honor_for_test(world, npc_user, 0)

# -------------------------------------------------------------------
# Beat 1's staged warrior: a free land tile adjacent to the rival's
# ONE city, excluding every tile already spoken for (both cities, both
# Lords, and every wilderness camp near the rival's own region —
# founding always seeds 5-8 of them around a player's first city,
# story 892, and one could easily land on a candidate tile). Lowest
# free tile id wins, for a deterministic pick across re-runs.
# -------------------------------------------------------------------

lord_tiles =
  for u <- Game.player_units(world, demo_user) ++ Game.player_units(world, rival_user),
      u.type == :lord,
      do: u.tile_id

camp_tiles = Repo.all(from(c in Camp, where: c.world_id == ^world.id, select: c.tile_id))

occupied_base = MapSet.new([demo_city.tile_id, rival_city.tile_id | lord_tiles ++ camp_tiles])

warrior_tile =
  world
  |> Regions.adjacent_tiles(rival_city.tile_id)
  |> Enum.uniq()
  |> Enum.filter(&(Regions.tile_class(world, &1) == :land))
  |> Enum.reject(&MapSet.member?(occupied_base, &1))
  |> Enum.sort()
  |> List.first() ||
    raise "no free land tile adjacent to the rival's city ##{rival_city.id} — re-probe the seed"

warrior_stats = Production.unit_stats(:warrior)

warrior_attrs = %{
  world_id: world.id,
  player_id: demo_player.id,
  type: :warrior,
  tile_id: warrior_tile,
  hp: warrior_stats.hp,
  max_hp: warrior_stats.hp,
  movement: warrior_stats.movement,
  max_movement: warrior_stats.movement
}

demo_warrior =
  case Repo.all(from u in Unit, where: u.world_id == ^world.id and u.player_id == ^demo_player.id and u.type == :warrior) do
    [] ->
      {:ok, unit} = %Unit{} |> Unit.changeset(warrior_attrs) |> Repo.insert()
      IO.puts("Spawned demo player's warrior ##{unit.id} at tile #{warrior_tile}, adjacent to the rival's city")
      unit

    [existing | extra] ->
      if extra != [], do: Repo.delete_all(from(u in Unit, where: u.id in ^Enum.map(extra, & &1.id)))
      {:ok, unit} = existing |> Unit.changeset(warrior_attrs) |> Repo.update()
      IO.puts("Repaired demo player's warrior ##{unit.id}: full HP at tile #{warrior_tile}")
      unit
  end

# -------------------------------------------------------------------
# Mutual discovery (both directions, demo<->rival and demo<->tyrant) so
# chat/feudal panels are unlocked from the first page load — same
# pattern as qa_seeds_multiplayer.exs.
# -------------------------------------------------------------------

ensure_known = fn viewer, discovered ->
  case Repo.get_by(KnownPlayer, world_id: world.id, viewer_player_id: viewer.id, discovered_player_id: discovered.id) do
    nil ->
      %KnownPlayer{}
      |> KnownPlayer.changeset(%{world_id: world.id, viewer_player_id: viewer.id, discovered_player_id: discovered.id})
      |> Repo.insert!()

      :ok

    _existing ->
      :ok
  end
end

ensure_known.(demo_player, rival_player)
ensure_known.(rival_player, demo_player)
ensure_known.(demo_player, npc_player)
ensure_known.(npc_player, demo_player)

# -------------------------------------------------------------------
# Last write, always: refresh the wall-clock anchor — belt-and-
# suspenders even though a paused world never reads it for catch-up
# (see this file's top doc); keeps it accurate if the demo operator
# ever does hit `/resume` mid-session.
# -------------------------------------------------------------------

{:ok, world} =
  Worlds.update_world(world, %{turn_started_at: DateTime.utc_now() |> DateTime.truncate(:second)})

IO.puts("""

=== QA credentials (rebellion demo) ===
demo player:  #{demo_user.email} / #{qa_password} (user id #{demo_user.id}, player id #{demo_player.id})
rival player: #{rival_user.email} / #{qa_password} (user id #{rival_user.id}, player id #{rival_player.id})

=== NPC tyrant lord (no login) ===
identity:  #{npc_user.email} (user id #{npc_user.id}, player id #{npc_player.id})
capital:   Tyrant's Hold (city ##{npc_city.id}, tile #{npc_city_tile}, wilderness region #{npc_region_id})
lord unit: ##{npc_lord.id}
honor:     0 (floored) | vassal tribute_rate: #{vassalage.tribute_rate} | oath_strain: #{vassalage.oath_strain}

=== World ===
name:   #{world.name}
id:     #{world.id}
seed:   #{world.seed}
freq:   #{world.frequency}
turn:   #{world.turn}
paused: #{world.paused}

=== Beat 1 staging ===
rival's only city:  ##{rival_city.id} "#{rival_city.name}" @ tile #{rival_city.tile_id}, #{rival_city.hp} HP (one warrior hit breaks it)
demo warrior:        ##{demo_warrior.id} @ tile #{demo_warrior.tile_id} (adjacent, #{demo_warrior.hp}/#{demo_warrior.max_hp} HP)

=== QA URLs (dev server, port 4050) ===
login:       http://localhost:4050/users/log-in
play:        http://localhost:4050/play/#{world.id}
globe:       http://localhost:4050/worlds/#{world.id}
mailbox:     http://localhost:4050/dev/mailbox
advance turn: curl -X POST http://localhost:4050/dev/qa/worlds/#{world.id}/step   (works even while paused; also /pause, /resume)

=== Beat-by-beat: what to click ===
1. TAKE OVER + VASSALIZE (906/907) — log in as the demo player, open the
   globe, select warrior ##{demo_warrior.id} (tile #{demo_warrior.tile_id}), attack
   city ##{rival_city.id} ("#{rival_city.name}") — one hit breaks it (#{rival_city.hp} HP, no
   counter-damage). Move the warrior onto the city's tile (an
   adjacent-move + one `/step` resolves it) to occupy it — the rival
   swears fealty and appears in the demo player's own Vassals panel.
2. THE STRAINED VASSAL (908/913/914) — still as the demo player, open
   the Vassals panel to show the FRESH rival vassal-row (tribute
   control, `vassal-oath-strain` badge, low strain). Then show the
   OTHER vantage point: the demo player's OWN `my-oath-strain` gauge
   reads near-maxed (oath_strain #{vassalage.oath_strain}/100) under the tyrant
   (#{npc_user.email}), tribute_rate #{vassalage.tribute_rate} being paid every turn boundary.
3. DECLARE INDEPENDENCE (915) — from the demo player's own oath panel,
   open the independence preview against the tyrant: the demo capital
   (##{demo_city.id}) reads `will_rise?: true` (Honor floored + tribute
   maxed -> tyranny_score 100, always >= any city's resistance).
   Confirm: the city rises, the tyrant's garrison (if any still stood
   there) defects, a strain-sized temporary army spawns, war is
   declared (`at-war-with`, `rebellion-panel`).
4. WIN INDEPENDENCE (919) — hit the `/step` control ten times (no
   re-occupation in between) to cross the 10-turn hold threshold; the
   rebellion panel flips to `independence_won` and the oath is
   permanently severed.
""")
