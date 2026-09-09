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

All three of this story's criteria build on the `a_freshly_subjugated_vassal` fixture, which itself calls `render_hook(play_live, "declare_war", ...)` as its first step before marching a Lord to capture the rival city. Story 996 QA (this session, issue 8fb548d0) established there is no UI trigger anywhere for `declare_war` — confirm this blocks story 998 too:

- **Criterion 3133 (an occupied city pays its controller tribute):** Requires an active war + a captured/occupied city first. Expect: blocked, cannot reach a wartime state through the UI.
- **Criterion 3134 (tribute stops when occupation ends):** Same precondition chain, same block.
- **Criterion 3135 (occupation preserves city ownership):** Same precondition chain, same block.

If issue 8fb548d0 is fixed before this QA session runs, re-test the actual tribute mechanic: occupy a rival city (see story 997's brief), advance a turn (`Fixtures.advance_turn` equivalent — wait for the real turn clock, or use the `/dev/qa/worlds/:id/step` endpoint per plan.md), and check the vassal-row / city-tribute indicators for gold transfer; then reclaim the city and confirm tribute stops.

## Result Path

No result.md — findings go through `create_issue`, and the run closes with `mcp__plugin_codemyspec_local__submit_qa_result`.

## Setup Notes

Do not refile the missing-declare-war-button issue — reuse 8fb548d0-1c2c-418a-9807-daa7b7c3904c.
