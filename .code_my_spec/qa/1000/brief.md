# Qa Story Brief

## Tool

web

## Auth

Run `mix run priv/repo/qa_seeds_multiplayer.exs` (see Seeds below). Log in via `/users/log-in` using the `#login_form_password` form.

Use the `vibium` CLI per `.code_my_spec/qa/plan.md`'s Tools Registry. **Do not attempt raw MCP browser_* tools or fresh account registration/confirmation** — 17 prior QA attempts on this exact story (`list_qa_attempts story_id=1000`) all failed on preview infra (Cloudflare 524, LiveView reconnect loops, broken-pipe browser errors, confirmation never completing) before ever reaching the actual capture mechanic. Use the pre-seeded, already-confirmed `qa_seeds_multiplayer.exs` accounts rather than registering new ones.

## Seeds

    mix run priv/repo/qa_seeds_multiplayer.exs

Two confirmed QA players, joined and founded, mutual discovery pre-seeded.

## What To Test

All three criteria build on the `a_freshly_subjugated_vassal` fixture (same as stories 998/999), which calls `render_hook(play_live, "declare_war", ...)` before capturing a city. Story 996 QA (this session, issue 8fb548d0) established there is no UI trigger anywhere for `declare_war` — this blocks the underlying capture-to-vassalization flow at its first step, on top of the infra instability documented across 17 prior attempts:

- **Criterion 3117 (capturing an enemy capital vassalizes its realm):** Requires declaring war, then capturing the rival's only/capital city. Expect: blocked at the declare-war step alone, before even reaching the preview-instability problems prior attempts hit.
- **Criterion 3118 (cities in a vassal realm pay tribute):** Same precondition chain.
- **Criterion 3119 (tribute starts when the capital falls):** Same precondition chain.

If issue 8fb548d0 is fixed AND the preview is confirmed stable (spot-check `/health` and a simple login before attempting the full flow), re-test: declare war, capture the rival's only city, and confirm a `Vassalage` record appears (feudal top bar `sworn to` indicator) with tribute flowing on the next turn boundary.

## Result Path

No result.md — findings go through `create_issue`, and the run closes with `mcp__plugin_codemyspec_local__submit_qa_result`.

## Setup Notes

Do not refile the missing-declare-war-button issue — reuse 8fb548d0-1c2c-418a-9807-daa7b7c3904c. Do not refile preview-infra issues already on record for this story (ab7fa7de, d2d6b6f4, 979c3a32, cb871571, b06e4a8b, 340faa84, 25f40e42, 30ac774c, c1320541) unless a NEW distinct failure mode is observed.
