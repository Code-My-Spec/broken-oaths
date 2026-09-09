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

All three of this story's criteria build on the `a_freshly_subjugated_vassal` fixture, which calls `render_hook(play_live, "declare_war", ...)` first, then captures the rival city. Story 996 QA (this session, issue 8fb548d0) established there is no UI trigger anywhere for `declare_war` — confirm this blocks story 999 too:

- **Criterion 3136 (occupation preserves city ownership):** Requires an active war + captured city. Expect: blocked.
- **Criterion 3137 (an occupied city cannot raise military units):** Same precondition chain, same block.
- **Criterion 3138 (reclaiming a city restores military production):** Same precondition chain, same block.

If issue 8fb548d0 is fixed before this QA session runs, re-test the actual production-limiting mechanic: occupy a rival city, open its city panel as the ORIGINAL owner, and confirm military unit types (warrior, bronze spearman, etc.) are absent/disabled from the production catalog while non-military items remain available; then reclaim the city and confirm military production returns.

## Result Path

No result.md — findings go through `create_issue`, and the run closes with `mcp__plugin_codemyspec_local__submit_qa_result`.

## Setup Notes

Do not refile the missing-declare-war-button issue — reuse 8fb548d0-1c2c-418a-9807-daa7b7c3904c.
