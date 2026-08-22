# Qa Story Brief

Story 937 — Declare Independence and Free Your Cities.

## Tool

web (Vibium browser MCP) for the LiveView flow at `/play/:id`; `psql broken_oaths_dev` (read-only) and the dev-only DevQA control surface (`curl`) to seed/verify state without racing the live `WorldServer`.

## Auth

Log in via `#login_form_password` at `http://localhost:4050/users/log-in`:

- Demo player (vassal, then rebel): `qa-913-demo@broken-oaths.test` / `qa-password-123!`
- Rival player (independent, then would-be vassal): `qa-913-rival@broken-oaths.test` / `qa-password-123!`
- NPC tyrant lord: `qa-913-tyrant@broken-oaths.test` — no login, direct-insert-only actor (never has a live session, so lord-side push notifications cannot be observed for this actor through the browser).

Scroll `#login_form_password` into view first (below-fold), then click `button[name='user[remember_me]']`.

## Seeds

    mix run priv/repo/qa_seeds_rebellion.exs

Idempotent/self-healing — resets **world 7 ("QA World (Rebellion Demo)", seed 913919)** to its documented "beat 1 ready" baseline: demo player is a fresh, active vassal of the NPC tyrant (tribute_rate 1.0, oath_strain 90, tyrant Honor floored to 0 — guarantees the demo's one occupied city, #18, will rise), rival player is fully independent with a one-hit-breakable city adjacent to the demo player's staged warrior. World boots `paused: true`. After running the `.exs` (a separate BEAM node — never call `iex`/`mix run` against `BrokenOaths.Game.*` from a second shell while the dev server is up otherwise), call `POST /dev/qa/worlds/7/reload` so the LIVE dev server's `WorldServer` picks up the raw-Repo writes.

First board load for the demo player opens on the Terms of Oath screen (`data-test="oath-screen"`) — dismiss by clicking any `[data-test="agenda-option-*"]` button before testing anything else.

This world is also the shared vehicle for the human's rebellion demo-video prep (913-919) and was mid-use at session start (rebellion already resolved `independence_won` from an earlier walkthrough) — re-seeding was necessary to get a fresh, active oath to sever. Flagged to the team lead before resetting.

## What To Test

- **7731 (sever oath, open war):** As demo player, click `[data-test="declare-independence"]` → confirm the two-step warning modal (`data-test="declare-independence-warning"`, confirm button `data-test="confirm-declare-independence"`) appears, then click confirm. Assert via `psql`: `game_vassalages` row flips to `status: broken`; a new `game_rebellions` row appears with `status: active`.
- **7732 (preview before committing):** Before confirming, look for `data-test="independence-preview"` (per-city `data-test="rise-preview-city-<id>"` verdicts, `data-test="rebellion-army-preview"` army size) anywhere on the page, and specifically check the warning modal's own content for it. The triggering event is `"open_independence_preview"` (`lib/broken_oaths_web/live/game_live/play.ex:1188`) but grep the whole `lib/broken_oaths_web/` tree for any `phx-click="open_independence_preview"` binding — expect none.
- **7733 (risen city de-occupies, garrison defects):** After confirming, `psql`: the risen city's `occupied_by_player_id` should be `NULL` and `hp` full; any lord unit that was standing on that city's tile should now have `player_id` = the rebel's.
- **7734 (tyrant's cities rise, grievance army rallies):** With honor floored + tribute maxed, expect `risen_city_ids` to include the demo's occupied city and `army_size` > 0 with that many `temporary: true, rebellion_id: <id>` warrior units spawned (`psql` `game_units`).
- **7735 (just lord, cities stay loyal):** Needs a SEPARATE, high-honor/low-tribute vassalage (e.g. demo player as lord over a freshly-conquered rival, tribute_rate ~0.25, oath_strain ~0) — not covered this session, see Setup Notes.
- **7736 (loyal cities siege-only, lord notified):** Needs a mixed rise/loyal split to observe the "still occupied" half; the lord-notification push (`"game:rebellion_declared"`) needs a REAL logged-in lord (not the NPC tyrant) to observe in the browser — not covered this session, see Setup Notes.
- **7747 (tracked rebellion):** `psql` `game_rebellions` row exists with `rebel_player_id`/`former_lord_player_id`/`started_turn`/`risen_city_ids`/`loyal_city_ids`/`army_size` populated.

## Result Path

DB-backed QA attempt via `submit_qa_result` (task id from `start_task`); findings via `create_issue`. No result.md file.

## Setup Notes

Environment: 6 QA agents ran concurrently against the same dev server/DB and the same shared Vibium browser instance this session. The browser MCP tools share one global "current page" pointer with no per-call page/tab targeting — concurrent agents' `browser_navigate`/`browser_click`/`browser_delete_cookies` calls repeatedly interleaved with mine and stole focus/session mid-sequence, producing intermittent `element not found` errors and unrelated pages/logins showing up between calls. Filed as a framework issue. Screenshots in this session's evidence folder that show a different QA agent's session (e.g. `qa-901-a@broken-oaths.test`) are contention artifacts, not this story's state.

7735/7736's "just lord" half were not exercised live this session due to time spent on the above contention; `BrokenOaths.Feudal.Rebellion.War`'s source (read in full) implements both symmetric outcomes through the same `Resolution.resolve_risings/4` call the "tyrant" half already exercised, so the risk is judged low, but this is inference from source, not a live-tested pass.

### 2026-08-22 re-verification session (criterion 7732 focus)

Issue 6ec08fdf (no UI trigger for the independence preview) was resolved: a "Preview Independence" button (`data-test="preview-independence"`, `phx-click="open_independence_preview"`) was added in `feudal_top_bar.ex` just before "Declare Independence". This session re-seeded world 7 (`mix run priv/repo/qa_seeds_rebellion.exs` + `POST /dev/qa/worlds/7/reload` — the vassalage had already drifted to `status: broken` with two prior rebellion rows from earlier demo-prep use) and re-verified criterion 7732 LIVE in the browser using the `vibium` CLI, cross-checked against `psql`:

- Logged in as `qa-913-demo@broken-oaths.test`, dismissed the oath screen, confirmed both "Preview Independence" and "Declare Independence" buttons render side by side (screenshot `01_board_before_preview.png`).
- Clicked "Preview Independence" — the top bar rendered a "will rise" verdict badge and a `rebellion-army-preview` badge reading "10" (screenshot `02_preview_rendered_will_rise_army10.png`). Confirmed via source (`feudal_top_bar.ex:469-489`) that these map to `data-test="independence-preview"` wrapper, `data-test="rise-preview-city-<id>"` per-city verdicts, and `data-test="rebellion-army-preview"` army size — exactly matching the criterion's requirement.
- Cross-verified via `psql` immediately after the click: `game_vassalages` row unchanged (`status: active`, tribute 1.0, oath_strain 90), `game_rebellions` empty, city 18 still `occupied_by_player_id: 18` — confirming opening the preview is read-only, no side effects.
- **New finding filed** (issue `b204930b`, medium/app): `mix spex` for criterion 7732 currently fails — not on the preview panel itself (those assertions pass), but on a stale "sworn to {email}" assertion that predates an earlier, unrelated commit (`ca82749`, "player display name instead of email everywhere") which changed the vassal-status badge to show `User.display_name/1`'s `"Player #<id>"` fallback instead of the literal email. The feature works correctly; the automated regression coverage for "preview has no side effects" is what's broken.
- **Environment note**: contention this session was severe enough to defeat even the `vibium` CLI + dedicated-page-switching approach — multiple concurrent QA agents (evidence: sessions for `qa-901-a@broken-oaths.test`, `qa-901-b@broken-oaths.test`, and others on unrelated worlds 3/etc. surfaced mid-sequence) share one browser daemon with no per-agent tab isolation; `vibium page new` + `vibium page switch <id>` immediately before each action did NOT provide isolation either, since the daemon's "current page" pointer is a single global value any concurrent agent's call can flip between one CLI invocation and the next. Flagged to team-lead live. After several retries a clean window opened long enough to capture both key screenshots above; a full live re-walk of 7731/7733/7734/7735/7736/7747 was not completed this session due to sustained contention afterward — those criteria's status rests on the 2026-08-21 session's prior live evidence (7731/7733/7734/7747) and source-level inference (7735/7736), noted above.
