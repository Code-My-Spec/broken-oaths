# Qa Story Brief

Story 874 — Automatic Turn Processing.

## Tool

web

## Auth

- Login URL: `http://localhost:4050/users/log-in`
- Use the password form `#login_form_password` (below the magic-link
  form on the same page):
  - `input[name="user[email]"]`
  - `input[name="user[password]"]`
- Primary QA account: `qa@broken-oaths.test` / `qa-password-123!`
  (already a member of QA World, id 6, from prior QA sessions).
- Second account for the "two connected players" scenario:
  `qa877-throwaway2@example.test`, registered this session, magic-link
  confirmed, already joined world 6 (region_id 3) via story 877 QA —
  reachable via `/users/register` + `/dev/mailbox` if a fresh session
  needs to re-derive its token, but the account itself persists.
- Driven with the `vibium` CLI (bash), sandbox disabled for the vibium
  daemon socket. `vibium go <url>`, `vibium find <selector>`, `vibium
  fill/click`, `vibium screenshot` (path arg broken, always writes
  `~/Pictures/Vibium/screenshot.png` — copy aside per scenario).

## Seeds

    mix run priv/repo/qa_seeds.exs

Idempotent, already run this session. Uses **QA World** (id 6, seed
424242, frequency 54) — the only world needed for this story; turn
timing is a per-world property independent of region/spawn mechanics.

## What To Test

Browser-observable behaviors:

- **The countdown runs down and the turn advances by itself**
  (criterion 7419) — log in as `qa@broken-oaths.test`, go to
  `/play/6`. Read `[data-test='turn-number']` and
  `[data-test='turn-countdown']`, note wall-clock time. Re-check every
  ~10-15s across a full ~65s window without touching anything.
  Expect: countdown decreases roughly 1/sec; when it would hit 0, the
  turn number increments by exactly 1 and the countdown resets to
  ~59-60. No page reload needed — this is a live-updating
  `live_component` (`GameLive.TurnBar`) via `send_update_after`.

- **Two views show consistent turn state** — while the turn is
  in-flight, navigate away (`/play`) and back to `/play/6`. Confirm
  the turn number matches (accounting for a boundary that may have
  fired mid-navigation — turn number should be equal or exactly +1,
  never regress or jump by more) and the countdown resumes counting
  down from a sane value (not reset to a stale number, not negative).

- **The world lives while everyone sleeps** (criterion 7420) — note
  the current turn number, then log out
  (`a[href='/users/log-out']`). Wait for roughly two turn boundaries
  (~125s covers the countdown's remaining time plus one full 60s
  cycle with margin). Log back in, go to `/play/6`, confirm the turn
  number increased by ~2 versus the pre-logout reading (±1 is
  acceptable slop from timing). This demonstrates the `WorldServer`
  GenServer ticks on its own schedule (`Process.send_after`),
  independent of any connected LiveView socket.

- **Two connected players tick over together** (criterion 7423,
  approximate — vibium is a single browser, so this is sequential, not
  truly simultaneous) — while logged in as `qa@broken-oaths.test` on
  `/play/6`, read the turn number and timestamp it. Log out, log in as
  `qa877-throwaway2@example.test` (also a world-6 member from story
  877), go to `/play/6`, read the turn number again within a few
  seconds of the first read. Expect identical turn numbers (both
  players share one world clock) — a mismatch would only be
  explainable by a boundary firing in the few seconds between checks,
  which should be a one-count difference at most, not a diverging
  per-player state.

Code/spec-level criteria (not independently browser-testable — no safe
way to restart the dev server mid-QA-session per team lead's
standing instruction, and true concurrent-order resolution needs
multiple simultaneous units/sockets beyond what sequential single-browser
QA can drive):

- A server restart never loses or double-runs a turn (criterion 7421)
  — `test/spex/874_.../criterion_7421_..._spex.exs` explicitly kills
  the LiveView process and drives 10 ticks with nobody connected, then
  reconnects and asserts the turn count is exactly 10 higher; source
  read confirms `turn`/`turn_started_at` are persisted every tick
  (`persist_world_turn/1`) and `catch_up/1` replays any missed ticks
  on `WorldServer` init from the persisted `turn_started_at`. This QA
  pass relies on that spec plus the source read rather than triggering
  an actual `mix phx.server` restart, since the team lead's standing
  instruction is not to restart the dev server without checking in
  first — doing so mid-session to manufacture this scenario isn't worth
  the risk of re-triggering the documented "500 on every route after
  recompile" failure mode for a criterion the spec already covers well.
- Nothing moves until the boundary, then everything moves at once
  (criterion 7422) — full verification (units mid-path not visibly
  advancing until the exact turn tick) is primarily story 875's
  territory (queued movement orders) and is spec-covered by
  `criterion_7422_..._spex.exs`, which asserts lockstep resolution
  order deterministically. This QA pass corroborates only the timer
  half: the turn number does not change until the countdown reaches
  0/resets (observed directly above) — i.e., nothing *turn-related*
  happens until the boundary. Full order-resolution-at-once is not
  re-derived here to avoid duplicating story 875's scope.

## Result Path

Findings are filed via `create_issue` as discovered; the run concludes
with one `submit_qa_result` call against task id
`386c3c48-ad8b-49d7-afbd-6f7786904a68`. Screenshots go in
`.code_my_spec/qa/874/screenshots/`.

## Setup Notes

- `WorldServer` (`lib/broken_oaths/game/world_server.ex`) is a
  per-world GenServer, `@tick_seconds 60`, self-scheduling via
  `Process.send_after(self(), :tick, 60_000)` in `handle_info(:tick,
  ...)` — confirmed independent of any LiveView PubSub subscriber
  count by source read. `Game.turn_ends_at/1` computes
  `turn_started_at + 60s` server-side; `TurnBar` recomputes
  `seconds_remaining` client-visibly once per second via its own
  `send_update_after/3` loop — the countdown ticking is a pure
  client-side render of a fixed deadline, not itself proof the server
  is ticking (only the turn-number incrementing proves that).
- This story reuses QA World (id 6) already seeded and already joined
  by both test accounts from story 877's QA pass — no new seed data
  needed.
- Real time passes during this QA session (multiple ~60-130s waits) —
  this is expected and consistent with the QA plan's guidance that
  sleeping through dev-mode's real 60s turns is an acceptable way to
  human-simulate time-dependent checks.
