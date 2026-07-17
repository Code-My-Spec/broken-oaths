# QA Brief — Story 895: City Defense and Garrison

## Tool

web

## Auth

- Operator-driven session using the existing confirmed account
  `qa-894-a@broken-oaths.test` (already joined World 1 with city 7 at
  tile 18906). Session established via the dev mailbox confirmation
  flow: open `http://localhost:4050/dev/mailbox`, open the newest mail
  for the account, run `document.forms[0].submit()` on the magic-link
  page via `vibium eval`.
- Fallback account with password login: `qa@broken-oaths.test` /
  `qa-password-123!` via the second form on
  `http://localhost:4050/users/log-in`.

## Seeds

- Base seeds already applied (`priv/repo/qa_seeds.exs` was run by the
  operator after the DB re-seed; do NOT run mix from a QA session).
- World 1 runs 10-second turns (`update worlds set turn_seconds = 10
  where id = 1` applied by the operator).
- Entities used: city 7 (tile 18906, size 4, owner player 8), heir
  lord 200 (garrisoned on 18906), warriors 203/204/205 produced via
  the city panel, camps 40/41 with live guards providing hostiles.

## What To Test

- The wall math: select city 7; `[data-test='city-hp']` shows HP and
  `[data-test='city-defense']` equals 20 + 5×size + garrison defense
  (size 4 + lord 12 → 52).
- Three fit in the keep: move two warriors onto the city tile with the
  lord already there — all three military units co-locate as garrison.
- The fourth sleeps outside: order a fourth military unit onto the
  city tile — refused with a human-readable reason, unit stays put.
- Room in the walls for the meek: queue a worker; move it onto the
  full-garrison city tile — it arrives, defense unchanged.
- Fighting from the walls / the walls bite back: when a barbarian
  closes on the city, attack it from the garrison (right-click) and
  observe counter-exchange; barbarian city assaults at boundaries drop
  city HP while the attacker takes garrison counter-damage (psql HP
  reads both sides).
- Quiet nights mend walls: track city HP via psql across boundaries
  with no attacker in reach — +5 per boundary to max.
- Sacked but still mine: pillage-not-capture consequences (size −1,
  production halted 3 boundaries, HP resets to 50) — historical live
  record from world 1 city 1 (`production_halted_until` set during
  batch-3 combat) plus the green end-to-end spec criterion_7568.
- The watchman's cry: `game:alert` flashes on 3-hex approach and on
  attack.

## Result Path

.code_my_spec/qa/895/ (screenshots; canonical record via
mcp__plugin_codemyspec_local__submit_qa_result)

## Setup Notes

The live worlds are saturated with camp guards from earlier QA
sessions; garrison-side scenarios are staged AT the city where the
garrison bonus keeps units alive. Ground truth via psql
`broken_oaths_dev` between every step. Never restart the dev server;
never run plain mix/iex.
