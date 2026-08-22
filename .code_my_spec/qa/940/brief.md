# Qa Story Brief

Story 940 — Winning, Losing, or Ending a Rebellion. Component:
`BrokenOaths.Feudal.Rebellion.War` (+ `BrokenOaths.Feudal.Rebellion`/
`Rebellion.Resolution`, same file). Five criteria: tracked entity with
one end-state transition (2691), win via holding (2692), crushed via
lord retaking cities (2693), negotiated peace (2694), disband/settle
exactly once on any ending (2695).

## Tool

- `web` (MCP `mcp__plugin_codemyspec_vibium__browser_*` tools) for every
  LiveView interaction — declare independence, hold, offer/accept/reject
  peace, oath/vassal panels.
- `curl` for the dev-only `/dev/qa/worlds/:id` control surface (pause/
  step/reload) — see plan.md's Tools Registry.
- `psql broken_oaths_dev` for one targeted, sanctioned write: simulating
  "the lord retakes the risen city" by setting `occupied_by_player_id`
  directly on the `game_cities` row, since there is no DevQA endpoint to
  patch city HP/occupation (only `/camps/:camp_id` supports an HP
  patch) and the NPC tyrant has no login to drive real siege combat
  through the browser. Always follow with `POST .../reload` so the live
  `WorldServer` re-hydrates from the DB before the next `/step` — this
  is the documented reload contract in plan.md ("pairs with a raw-Repo
  reseed so the running server picks up the fresh state").

## Auth

Two real, password-login accounts come out of the seed below (printed
credentials each run): the DEMO PLAYER and the RIVAL, both password
`qa-password-123!`. Log in via `#login_form_password`
(`input[name="user[email]"]`, `input[name="user[password]"]`) at
`http://localhost:4050/users/log-in`. The NPC TYRANT lord
(`qa-913-tyrant@...`) has NO login — it's a direct-insert non-player
actor; never try to authenticate as it.

The demo player's board opens on a `data-test="oath-screen"` Terms-of-
Oath modal on first load (their one city starts occupied by the
tyrant) — dismiss it by picking any Hidden Agenda before doing anything
else on the board.

## Seeds

    mix run priv/repo/qa_seeds_rebellion.exs

Idempotent and self-healing — run it ONCE at the start of this session
to get a clean beat-1-ready world. Read the printed summary block for:
world id, demo/rival user+player ids, tyrant player id, rival's city
id, demo warrior id/tile. Confirm via `curl http://localhost:4050/dev/qa/worlds/<id>`
that the world isn't mid-use by another concurrent QA session before
touching it (check `paused`/`turn` against what the seed just printed).

Do NOT re-seed between the sub-scenarios below — the plan chains them
on purpose (crushed → revassalized → win; rival conquest → peace →
restored vassal → crushed) so only one reseed is needed for the whole
session.

## What To Test

- **Scenario A — tracked entity + crushed (2691, 2693, 2695):** as the
  demo player, dismiss the oath screen, open the independence preview
  against the tyrant lord (feudal top bar), confirm
  `rise-preview-city-<id>` reads `will_rise?: true` and
  `rebellion-army-preview` shows a strain-sized army. Confirm
  (`confirm_declare_independence`). Assert `rebellion-panel` appears
  with `rebellion-status: active`, `at-war-with` badge shows, and the
  temporary army (`rebellion-army-size` units) exists. Then simulate
  the lord retaking the risen city: `psql` `UPDATE game_cities SET
  occupied_by_player_id = <tyrant_player_id> WHERE id = <risen_city_id>`,
  `POST /dev/qa/worlds/<id>/reload`, `POST /dev/qa/worlds/<id>/step`.
  Assert `rebellion-status` flips to `crushed` exactly once, the
  temporary army is gone (units query or `rebellion-panel` army count),
  and the demo player's oath panel shows the tyrant as lord again
  (re-vassalized). Step 2-3 more times and confirm nothing re-fires
  (no error page, status stays `crushed`, no duplicate unit deletion).

- **Scenario B — win independence (2692, 2691, 2695):** re-vassalized
  from Scenario A, declare independence against the tyrant a second
  time (fresh `Rebellion` row). This time hold: `POST
  /dev/qa/worlds/<id>/step` ten times with no interference. Assert
  `rebellion-status` flips to `independence_won` at turn 10, the
  temporary army disbands, and the demo player's oath panel no longer
  shows any lord (permanently free — confirm a THIRD declare against
  the tyrant is not offered/possible).

- **Scenario C — negotiated peace, both directions, two real accounts
  (2694, 2695):** as the demo player, select the staged warrior and
  attack+occupy the rival's one city (one hit breaks it per the seed's
  staging, then a `/step` + adjacent move occupies it) — the rival
  swears fealty (real `Vassalage`, demo player = lord). Log in as the
  RIVAL and declare independence against the demo player
  (`confirm_declare_independence`). As the demo player, submit
  `offer-peace-form` with `outcome=restored_vassal` and a nonzero
  `reparations_gold`. Switch to the rival's session, confirm
  `pending-peace-offer` is visible, click `reject-peace` — assert the
  rebellion stays `active` and the offer clears. As the demo player,
  offer peace again (`outcome=restored_vassal`, reparations again).
  Switch to rival, click `accept-peace`. Assert: rebellion status ->
  `peace`, reparations gold actually moved between the two players'
  balances (check via the UI resource display or `psql`), the rival's
  vassalage to the demo player is restored, and the temporary army (if
  any spawned) is gone.

- **Cross-check (2691):** across all three endings, confirm each
  `Rebellion` row's `status` only ever transitions once (query
  `select id, status, started_turn from game_rebellions where world_id
  = <id> order by id` at the end and sanity-check exactly 3 rows, each
  ended in a distinct status: crushed / independence_won / peace).

## Result Path

`.code_my_spec/qa/940/screenshots/` for evidence. No result.md —
findings go through `create_issue`, outcome through `submit_qa_result`
per the workflow.

## Setup Notes

- Component source: `lib/broken_oaths/feudal/rebellion/war.ex`,
  `lib/broken_oaths/feudal/rebellion.ex` (predicates/transitions live
  in `Rebellion.Resolution`, a submodule inside `rebellion.ex`).
- UI selectors confirmed by reading
  `lib/broken_oaths_web/live/game_live/play.ex` and
  `feudal_top_bar.ex`: `open_independence_preview`,
  `confirm_declare_independence`, `rebellion-panel` (`rebellion-status`,
  `rebellion-army-size`, `rebellion-risen-cities`), `offer-peace-form`,
  `accept-peace`, `reject-peace`.
- Known contention risk: world 7 ("QA World (Rebellion Demo)") is
  shared infrastructure — five other QA sessions (stories 935-939) are
  running concurrently against the same dev server/DB per the task
  brief. Re-check `GET /dev/qa/worlds/7` before each pause/reload/step
  if there's any gap in the session, and prefer aborting a step rather
  than fighting contention.
