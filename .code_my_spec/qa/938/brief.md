# Qa Story Brief

Story 938 — Coordinated Rebellion (Pact of Broken Oaths). Component:
`BrokenOaths.Feudal.RebellionPact.Conspiracy`, UI in
`lib/broken_oaths_web/live/game_live/play.ex` +
`lib/broken_oaths_web/live/game_live/feudal_top_bar.ex`.

## Tool

web (Vibium MCP browser tools) — every scenario below is a LiveView
flow on `/play/:id`, behind `:require_authenticated_user`. Never use
curl for these; see plan.md's golden rule.

## Auth

No existing seed sets up "1 lord + 3 vassals" (checked `game_vassalages`
in `broken_oaths_dev` — no lord currently has 2+ active vassals), so
this story needs its own 4-account scenario built live:

1. Register 4 fresh accounts via the real `/users/register` form (NOT
   the magic-link box on `/users/log-in` — that only emails EXISTING
   users, it never creates one):
   - `qa-938-mira@broken-oaths.test` (the lord)
   - `qa-938-wes@broken-oaths.test` (opens the pact)
   - `qa-938-ada@broken-oaths.test` (invited, commits)
   - `qa-938-bo@broken-oaths.test` (invited, declines then informs)
2. Confirm each via the magic-link token — either read it from
   `http://localhost:4050/dev/mailbox` after registering, or set a
   password afterward from `/users/settings` once logged in via the
   magic link, so subsequent logins can use
   `#login_form_password` (email + `qa-password-123!`) instead of the
   mailbox round-trip every time.
3. User switching: log out (`a[href='/users/log-out']`), then log back
   in as the next account — see plan.md's "User switching" pattern.

## Seeds

World: id 4, "QA Density Sparse 905" (frequency 54 — 100+ spawnable
regions, plenty of room for 4 players). Chosen because it had **zero**
existing `game_players` rows at the start of this session — the
least-contended large world available (world 1 "QA World" is the
default world other concurrent QA sessions actively use; worlds
2/3/6/7 are small or already staged for other stories).

No `.exs` seed script is used for this story — do NOT run
`mix run` / `iex -S mix` mid-session (plan.md's own System Issues
section: an out-of-band `mix run` invocation took the shared dev
server down entirely on 2026-07-16, and multiple other QA agents share
this server right now). Build the scenario entirely through:

- The real browser flow (register/join/found city) for the 4 accounts
  above.
- `POST /dev/qa/worlds/4/pause` first (already done this session — a
  paused, player-less world is uncontended to manipulate).
- `POST /dev/qa/worlds/4/units` to spawn Mira a warrior adjacent to
  each of wes/ada/bo's freshly-founded city, one at a time.
- A single-row `psql broken_oaths_dev -c "UPDATE game_cities SET hp=10
  WHERE id=<target>"` per target city (mirrors the one-hit-break
  pattern `priv/repo/qa_seeds_rebellion.exs` already documents), then
  `POST /dev/qa/worlds/4/reload` so the live `WorldServer` picks up the
  fresh HP before Mira's warrior attacks.
- Attack + move-to-occupy through the browser (real UI clicks) for
  each of the 3 targets, converting each into an active `Vassalage`
  under Mira — confirm with
  `psql broken_oaths_dev -c "select * from game_vassalages where
  lord_player_id=<mira's player id> and status='active';"` (expect 3
  rows) before starting the pact scenarios below.

## What To Test

All five acceptance criteria map onto ONE continuous pact so state
carries forward naturally (informing doesn't require having committed,
so Bo can decline AND later inform on the same pact):

- **Wes opens a pact chat and invites two fellow vassals (criterion
  2679 / spex 7737):** as Wes, `toggle_pact_panel`, confirm the
  composer lists `fellow-vassal-<ada's user id>` and
  `fellow-vassal-<bo's user id>` (and nobody else — Mira and any
  non-vassal must never appear). Submit `open_pact_chat` with a small
  `strike_turn` offset (e.g. `"6"`, since world 4 ticks in raw turns we
  fully control via `/step`) and both invitee ids. As Ada and as Bo,
  confirm each sees `pact-invite-notice` plus `pact-commit`/
  `pact-decline` controls.
- **The roster stays secret until the strike (criterion 2680 / spex
  7738):** Ada `pact_commit`, Bo `pact_decline`. As Wes, confirm both
  `pact-member-status-<ada>` and `pact-member-status-<bo>` read
  "Outstanding", never "Committed"/"Declined". As Mira (the lord),
  confirm no `pact-chat` element renders at all, and no
  `pact-member-status-*` for either vassal.
- **An invitee informs the lord and betrays the plot (criterion 2682 /
  spex 7741):** as Bo, `pact_inform`. As Mira, confirm
  `pact-informed-banner` appears, names strike turn, and
  `brace-defenses`/`reposition-lord`/`buy-off-conspirators` controls
  appear. As Bo, confirm `informer-reward`. As Wes and as Ada, confirm
  neither ever sees a `pact-informer` element (Bo still appears as an
  ordinary roster row to them, just not labeled as the informer).
- **Lord reads rising heat and buys off the plot (criterion 2683 / spex
  7742):** as Mira, read `conspiracy-heat` (baseline). Raise strain by
  cycling `issue_levy`/`refuse_levy` a few times against Wes and Ada
  (mirrors spex's 7x refusals each). Re-read `conspiracy-heat` — should
  rise. Apply `set_tribute_rate` (lower) and `honor_protection_call`
  for both Wes and Ada; confirm `conspiracy-heat` and each vassal's
  `vassal-oath-strain` drop afterward. Confirm Wes still has a
  `pact-decline` control available post-concession (the negotiation
  stays reversible).
- **Strike turn reveals and fires all revolts at once (criterion 2681 /
  spex 7739):** `POST /dev/qa/worlds/4/step` until the strike turn
  offset from above is reached. As Wes and as Ada, confirm
  `rebellion-status` now renders and `vassal-status` no longer reads
  "Sworn to Mira". As Bo (declined, never committed), confirm he still
  reads "Sworn to Mira" with no `rebellion-status` at all.

Explore afterward: try inviting an outsider (not a fellow vassal) into
the composer and confirm they're never a candidate; try opening a
second pact while one is already forming (at-most-one-active-pact
scoping per the Conspiracy module's own doc).

## Result Path

Findings go through `create_issue` as they're found, then one
`mcp__plugin_codemyspec_local__submit_qa_result` call at the end (or
the `cms_cloud`-prefixed equivalents if `_local` isn't attached this
session) — see the task prompt's "Findings and done signal" section.
No result.md file.

## Setup Notes

**Vibium contention (2026-08-21):** the vibium browser used this
session behaved like a single shared Chrome instance across multiple
concurrently-running QA agents (935-940) rather than one per agent —
navigating and immediately reading back showed different pages/users
than what was just driven, `browser_list_pages` showed tabs never
opened by this session, and a `browser_stop`+`browser_start` cycle
reconnected to an already-authenticated session (`qa-913-demo`) within
one tool call. Flagged to the team lead. If this recurs, prefer tight
navigate→act→verify sequences and confirm real state via `psql` (not
racy) rather than trusting a single browser read.
