# Qa Story Brief

Story 883 — Settler Production and Expansion.

## Tool

web

## Auth

- Login URL: `http://localhost:4050/users/log-in`
- Password form `#login_form_password`: `input[name="user[email]"]`,
  `input[name="user[password]"]`, submit via
  `#login_form_password button[name='user[remember_me]']`.
- Primary account (world 6, "QA World"): `qa@broken-oaths.test` /
  `qa-password-123!`.
- Driven with the `vibium` CLI directly (bash tool, sandbox disabled).
  City/unit selection via the real LiveView socket:

      window.liveSocket.owner(document.getElementById('board-viewport'), view => {
        const hook = view.viewHooks[Object.keys(view.viewHooks)[0]];
        hook.pushEvent('select_city', {city_id: <id>});
      });

  Real DOM buttons (`[data-test='city-panel']` production buttons,
  `[data-test='unit-panel']` found-city button) confirmed fully
  working this session (commit cc0b599) — used directly throughout,
  no hook-eval workaround needed for the actual action buttons.

## Seeds

    mix run priv/repo/qa_seeds.exs

Idempotent, already current. Per the hardened QA rule for this batch,
no `mix`/`iex` invocations during execution — psql and the browser
only (a second `mix`/`iex` process recompiles the shared `_build/dev`
and has crashed the running dev server twice already this session).

State re-verified via psql immediately before writing this brief: all
5 QA-controlled cities across worlds 1/6/10 are size 4 — Oakhaven
(city 1, world 6, player 1/QA user, tile 21635) chosen as the primary
subject since it's the QA user's own civilization and has ample
production. Settler (100 cost) queued via a real button click.

## What To Test

- **7486 (a settler is paid for in people) + 7488 (the map remembers
  what the census forgets):** track Oakhaven's Settler production via
  psql (`game_production_items`) to completion. On completion, confirm
  via psql: city size drops by exactly 1 (4 -> 3), and `territory`
  stays exactly the same 10 tiles it was before (only `worked_tiles`
  may shrink by one entry, per
  `lib/broken_oaths/game/production.ex` `apply_pop_cost/3` +
  `unwork_weakest_tile/2` — territory is explicitly documented as
  permanent).
- **7489 (the second city is founded like the first, minus the
  drama):** take the new settler, move it at least 4 land-hexes from
  Oakhaven (tile 21635), found a second city via the real Found City
  button. Confirm success (a real size-1 city appears, settler
  consumed) and confirm no barbarian-camp side effect — there is no
  barbarians/camps table in the schema at all (`\dt` confirmed), so
  this is code/schema-verified as a non-issue: the mechanic simply
  doesn't exist yet in this build, consistent with the story's own
  "future stories" scoping note.
- **7487 (a hamlet may not empty itself onto the road):** on the
  freshly founded (size-1) second city, immediately try to queue
  Settler production. Confirm the option is disabled/refused with a
  reason in the real UI, corroborated by
  `Production.can_queue?(%{size: 1}, :settler) -> {:error, :size_one}`
  in code.

## Result Path

`.code_my_spec/qa/883/screenshots/` for evidence; canonical result via
`submit_qa_result` (task id from `start_task`), no result.md.

## Setup Notes

Two dev-server crashes and one MCP plugin outage occurred earlier in
this QA batch (stories 881/882), both resolved by the team lead before
this story started. Server and MCP plugin confirmed healthy
throughout this session. No new app defects found in the immediately
prior story (882) beyond one time-boxed live-verification gap (issue
33653400, qa scope, not an app bug).
