# Qa Story Brief

Story 952 — Scout, early recon unit. All 10 BDD spec criteria already pass
via `mix spex` per the requirement's own automated gate; this session
verifies the same behaviors live against the running app (browser UI +
the dev QA control surface), not by re-running the spex suite.

## Tool

- web (Vibium CLI, driving the canvas board at `/play/:id`) plus the
  `/dev/qa/worlds/:id/*` control surface via curl for deterministic setup.
- `.code_my_spec/qa/scripts/board_state.sh` / `board_click.sh` for
  reading/driving the canvas board once Vibium has navigated to `/play/1`.

## Auth

Login page: `http://localhost:4050/users/log-in`
Password form: `#login_form_password`

```
vibium go "http://localhost:4050/users/log-in"
vibium eval "document.querySelector('#login_form_password_email').value='qa@broken-oaths.test'"
vibium eval "document.querySelector('#user_password').value='qa-password-123!'"
vibium eval "document.querySelector(\"#login_form_password button[name='user[remember_me]']\").click()"
```

QA credentials (from `qa_seeds.exs`): `qa@broken-oaths.test` /
`qa-password-123!`.

For the "buildable turn 1, zero techs" criterion specifically, register a
brand-new second account through the UI (`/users/register`) so the check
is against a player with no research at all, rather than the seeded QA
player (player_id 1), who already has Bronze Working/other techs from
prior QA sessions.

## Seeds

```
mix run priv/repo/qa_seeds.exs
```

Already run this session (server was freshly started). World 1 ("QA
World") has an established player (id 1, `qa@broken-oaths.test`) who
already owns multiple cities, including city id 1 "Oakhaven II" at tile
14725 (size 6) with an existing Lord, warriors, workers, bronze
spearmen. Use this city/player for movement, vision, and combat
scenarios via the dev QA control surface (deterministic, no growth
needed). Use a freshly registered second account for the "zero techs"
buildability check only.

Pause the world first so nothing ticks mid-scenario:

```
curl -X POST http://localhost:4050/dev/qa/worlds/1/pause
curl http://localhost:4050/dev/qa/worlds/1   # confirm paused: true
```

Resume at the end:

```
curl -X POST http://localhost:4050/dev/qa/worlds/1/resume
```

## What To Test

- **Buildable turn 1, zero techs (AC1)** — fresh second account, join +
  found a city in World 1, open the city panel immediately (no turns
  advanced, no research queued). Confirm "Scout" appears in the
  production options list and is clickable/queueable.
- **Cost 30, cheapest military (AC2)** — in the city panel, confirm the
  Scout's displayed cost is 30 and it's the lowest-cost buildable next to
  Warrior (40), Bronze Spearman (60), Archer (40), Galley (50).
- **Completes faster than a Warrior in the same city (AC3)** — queue a
  Scout and a Warrior back-to-back in the same city, `POST
  .../worlds/1/step` turn by turn, and confirm the Scout (30 cost) lands
  before the Warrior (40 cost) given identical per-turn production
  income.
- **Crosses three open tiles in one turn (AC4)** — `POST
  .../worlds/1/units` to spawn a player-owned Scout on an open land tile,
  `board_state.sh` to find an open (non-hills, non-feature) tile 3 hops
  out, `board_click.sh <tile> right` to queue the move, then
  `board_state.sh` again to confirm the Scout arrived immediately with
  movement 0.
- **Reveals a 2-hop vision ball (AC5)** — after the Scout spawns/moves
  into unexplored ground, `board_state.sh` and inspect the fog-known tile
  list / a sidebar tile inspection to confirm every tile within 2 hops of
  the Scout is revealed.
- **Lord out-sees the Scout by one hop (AC6)** — compare the known-tile
  footprint around the existing Lord (vision 3) vs. the Scout (vision 2)
  from `board_state.sh`'s output — the Lord's third ring should be known
  where the Scout's own third ring is not.
- **Attacks a barbarian camp at strength 5 (AC7)** — `POST
  .../worlds/1/barbarians` with a `camp_id` (or locate a visible camp),
  position the Scout adjacent via `PATCH .../units/:id` (`tile_id=`),
  `board_click.sh <camp_tile> right` to attack, and read the combat
  result (toast / `game:combat` push, or camp HP via `PATCH
  .../camps/:id` read-back) confirming 5 flat damage.
- **Loses a 1v1 against a Warrior (AC8)** — `POST .../worlds/1/barbarians`
  to spawn a barbarian Warrior adjacent to a Scout positioned off the
  city tile and away from the Lord's aura, attack via `board_click.sh
  <tile> right`, and confirm the Scout's own HP loss lands in the heavier
  band (\~34-56) while the barbarian's is in the lighter band (\~15-25)
  — i.e. the Scout visibly comes off worse.
- **Ignores difficult terrain (AC9)** and **pays a different cost than a
  Warrior for the same woods tile (AC10)** — find a woods/rainforest/marsh
  tile via `board_state.sh`, move the Scout onto it and confirm only 1
  movement is spent, then move a Warrior onto the SAME tile and confirm
  its movement drops to 0 (it pays the standard difficult-terrain cost
  of 2 against its own single movement point).

## Result Path

Findings are filed live via `create_issue`, not written to a result
file. Screenshots go to `.code_my_spec/qa/952/screenshots/`. The
canonical outcome is the `submit_qa_result` call at the end of this
session.

## Setup Notes

The dev server was not running at session start; started via `mix
phx.server` and confirmed healthy (`/health` → 200) BEFORE running the
seed script, to avoid the documented out-of-band-compile risk when a
second `mix` invocation shares `_build/dev` with a live server. No
further `mix`/`iex` calls are made after the initial seed run — state
reads during the session go through the browser, `board_state.sh`, or
the dev QA control surface only, per `plan.md`'s System Issues section.
`mix spex`/`mix test`/`mix credo` are intentionally NOT run this
session (per team-lead instruction — the harness's own continuous
analysis pipeline already covers these and a competing manual
invocation lock-contends with it).
