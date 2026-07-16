# Qa Story Brief

## Tool

web (vibium / MCP browser tools) — LiveView flows only. Code-verification
(reading `lib/broken_oaths/game/turn.ex`, `production.ex`) supplements live
testing for the healing criterion, where no live damage mechanic exists yet.

## Auth

Navigate to `http://localhost:4050/users/log-in`, use the `#login_form_password`
form:
- `input[name="user[email]"]` = `qa@broken-oaths.test`
- `input[name="user[password]"]` = `qa-password-123!`

## Seeds

No new seeds needed. Reusing existing state from this QA batch:
- World 6 ("QA World"), player_id 1 (QA user) owns city 1 "Oakhaven"
  (tile 21635, territory `{21607,21608,21634,21635,21636,21661,21662,
  21578,21606,21577}`).
- Unit 23: warrior, garrisoned on Oakhaven's city tile 21635 (100/100 hp,
  movement 1/1).
- Unit 24: warrior, tile 21661 (in Oakhaven's territory, not the city tile),
  100/100 hp, movement 1/1.
- World 1, player_id 10 (also QA user) owns city 4 with units 25/26/27
  (all warriors, movement 1/1) — backup surface if world 6 has issues.
- No live settler exists among QA-controlled players (all consumed founding
  cities earlier this batch). Settler `movement=2` is verified via the
  `BrokenOaths.Game.Production.unit_stats/1` catalog (code) plus historical
  DB reads earlier this session (units 8/16/18/20 all read movement=2 before
  being consumed).
- Real-time turn boundary is 60s (`@tick_seconds 60` in `world_server.ex`,
  `config :broken_oaths, :game_auto_tick` not disabled in dev) — waits are
  real wall-clock, not scriptable via `Fixtures.advance_turn/1` (spex-only).

## What To Test

- **7478 (city turns 40 production into a warrior):** Log in, go to
  `/play/6`, open Oakhaven's city panel, queue a Warrior (cost 40). Poll
  `game_production_items` / `game_units` via `psql broken_oaths_dev` every
  ~60-90s until the item resolves. Confirm: new `game_units` row appears
  with `type=warrior`, `hp=100`, `max_hp=100`, `movement=1`, `max_movement=1`,
  and `tile_id` at or adjacent to Oakhaven's tile 21635. Screenshot the city
  panel before/after and the map showing the new unit.
- **7479 (warrior 1 hex/turn, settler 2 hex/turn):** Queue a move order for
  unit 24 toward a tile 2+ hexes away from 21661 (via the UI's queue-move
  interaction on the selected unit). Record `tile_id` before, wait one real
  60s turn boundary, re-check via psql: confirm it advanced to exactly one
  adjacent hex of its start (not further), and that `movement` reset to
  `max_movement` (1) at the top of the new turn. Settler side is
  code-verified only (see Seeds) — no live settler exists to move.
- **7480 (healing: home/garrison/road):** **Code-verified only** — there is
  no legitimate live damage mechanic in this build (combat is explicit
  future work; `BrokenOathsSpex.Fixtures.set_unit_hp/3` is a spex-test-only
  stand-in, not reachable from the live app, and a raw `psql UPDATE` on
  `game_units.hp` would be silently overwritten by `WorldServer`'s
  in-memory state on the next tick or desync the DB). Verify by reading
  `lib/broken_oaths/game/turn.ex` `heal_rate/2`: a unit with `movement ==
  max_movement` (i.e., didn't spend movement this tick) heals `15` if
  standing on its own city's tile, `10` if standing anywhere else in its
  owner's territory, `0` otherwise. This matches the acceptance criterion
  exactly (garrison heals faster than home, road/abroad heals nothing).

## Result Path

No result.md — findings filed via `create_issue`, final record via
`submit_qa_result` (task id `1c02a195-9e9d-49af-9b39-53f8a6deb63a`).

## Setup Notes

Existing warriors (23, 24, 25, 26, 27) and cities (1, 4) are shared across
stories 881/882/883 in this batch — avoid destructive actions on them.
Screenshots saved to `.code_my_spec/qa/881/screenshots/`.
