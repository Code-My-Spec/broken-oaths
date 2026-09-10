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

This story has TWO separate missing-UI blockers, both confirmed this session:

1. Reaching an active war requires `declare_war`, which has no UI trigger anywhere (issue 8fb548d0, story 996).
2. Even once at war, `raid_city` (`GameLive.Play.handle_event("raid_city", ...)`, play.ex:976) has NO UI trigger either — a full grep of every game_live `.ex` file finds only the handler definition and an unrelated help-text mention of "raid" (issue 75822e86, filed this session).

- **Criterion 3130 (a wartime player raids an enemy city):** Blocked at declare_war first; even if war existed, there is no button/context-menu action to issue a raid order.
- **Criterion 3131 (a successful raid yields gold):** Same double block.
- **Criterion 3132 (a raid leaves the city under its owner):** Same double block.

Confirm empirically in the browser: log in, select a unit adjacent to a rival city, and check for ANY raid affordance (right-click context menu, city-panel button, etc.) distinct from the existing "attack" option — expect none.

## Result Path

No result.md — findings go through `create_issue`, and the run closes with `mcp__plugin_codemyspec_local__submit_qa_result`.

## Setup Notes

Do not refile either issue — reuse 8fb548d0-1c2c-418a-9807-daa7b7c3904c (declare_war) and 75822e86-1751-42e0-9340-544cb8632652 (raid_city).
