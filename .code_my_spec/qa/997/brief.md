# Qa Story Brief

## Tool

web

## Auth

Run `mix run priv/repo/qa_seeds_multiplayer.exs` (see Seeds below). Log in via `/users/log-in` using the `#login_form_password` form.

Use the `vibium` CLI per `.code_my_spec/qa/plan.md`'s Tools Registry (MCP `browser_*` tools were non-functional this session, see issue 5be3616e).

## Seeds

    mix run priv/repo/qa_seeds_multiplayer.exs

Two confirmed QA players, joined and founded, mutual discovery pre-seeded.

## What To Test

All three of this story's criteria require war to be ACTIVE as a precondition before occupying/reclaiming a city can even be attempted (each BDD spex declares war via `render_hook(play_live, "declare_war", ...)` before doing anything else). Story 996 QA (this session, issue 8fb548d0) already established there is no UI trigger anywhere for `declare_war` — confirm this blocks story 997 too:

- **Criterion 3127 (a wartime player occupies an enemy city):** Requires declaring war first. Expect: blocked, no way to reach a wartime state through the UI.
- **Criterion 3128 (occupation preserves city ownership):** Same precondition, same block.
- **Criterion 3129 (the owner reclaims an occupied city):** Same precondition (needs occupation to already exist), same block.

If a coding fix lands for issue 8fb548d0 before this QA session runs, re-test the actual occupy/reclaim mechanic itself: march a Lord onto an at-war rival's city tile (should mark it `occupied` per `city-status` data-test, city stays on the original owner's panel), then march the owner's own Lord back onto that tile (should clear the occupied status). The underlying `attack`/`queue_move` events these use ARE wired to real UI per prior QA on story 906.

## Result Path

No result.md — findings go through `create_issue`, and the run closes with `mcp__plugin_codemyspec_local__submit_qa_result`.

## Setup Notes

Do not refile the missing-declare-war-button issue — reuse 8fb548d0-1c2c-418a-9807-daa7b7c3904c.
