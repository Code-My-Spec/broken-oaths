# Qa Story Brief

## Tool

web

## Auth

Run `mix run priv/repo/qa_seeds_multiplayer.exs` (see Seeds below) — prints two confirmed QA player credentials and a world URL. Log in via `/users/log-in` using the `#login_form_password` form (magic link also available via `/dev/mailbox`).

Use the `vibium` CLI per `.code_my_spec/qa/plan.md`'s Tools Registry (prefer it over MCP `browser_*` tools, which are documented as unreliable). Two accounts are needed since this is a two-player agreement:

    vibium go "https://preview-c8eda3e8-ed17-49ec-86b0-1862b21f58b0.codemyspec.com/users/log-in"
    vibium find "#login_form_password"

## Seeds

    mix run priv/repo/qa_seeds_multiplayer.exs

This creates two confirmed QA players already joined and founded in the same fast-turn world, with mutual discovery pre-seeded (chat/alliance panels unlocked from first load) — exactly the precondition (`two_players_discovered_each_other`) all four BDD criteria for this story require. No story-994-specific seed exists or is needed; the multiplayer seed's discovery precondition is sufficient to attempt every scenario below.

## What To Test

- **Criterion 3110 (propose/accept):** As Player A, find any UI affordance (button/panel) to propose Open Borders to Player B (a known/discovered neighbor). Expect something analogous to `GameLive.AlliancePanel`'s "Propose" flow. As Player B, look for an "Accept" affordance. Expect both players' boards to then show an active Open Borders indicator.
- **Criterion 3111 (peaceful movement):** With Open Borders active, move a Player A unit onto Player B's territory. Expect no war to start and the unit to enter peacefully.
- **Criterion 3112 (revoke):** With Open Borders active, find a "Revoke" affordance for either partner. Expect the agreement to become inactive on both sides.
- **Criterion 3113 (blocked after revocation):** After revocation, try moving a unit across the former border again. Expect entry to be refused and no re-activation of the agreement.
- **Baseline check first:** Before attempting the above, inspect the `/play/:id` board's known-players panel, alliance panel, and any right-click/context menu on a neighbor for an "Open Borders" option. `lib/broken_oaths/diplomacy.ex` and `lib/broken_oaths/diplomacy/open_borders.ex` implement the domain logic (`propose_open_borders/3`, `accept_open_borders/3`, `revoke_open_borders/3`) and are delegated from `BrokenOaths.Game`, but a source search of `lib/broken_oaths_web/` turns up **no** `handle_event` clause for `propose_open_borders`, `accept_open_borders`, `revoke_open_borders`, or `move_through_open_border`, and no `data-test` element matching `open-borders-*` anywhere in the app — unlike the structurally identical Alliance feature (story 901), which has a full `GameLive.AlliancePanel` LiveComponent. Confirm this empirically in the browser before concluding the story is untestable via UI.

## Result Path

No result.md — findings go through `create_issue`, and the run closes with `mcp__plugin_codemyspec_local__submit_qa_result`.

## Setup Notes

The four BDD spex files (`test/spex/54_open_borders_agreements/`) all drive the feature via `render_hook(context.play_live, "propose_open_borders", ...)` etc. directly against the LiveView process, bypassing any real DOM/UI. Since `GameLive.Play` defines no `handle_event` clause for these event names, those `render_hook` calls have no matching clause to dispatch to — the spex tests do not exercise anything a real player could trigger by clicking. This needs to be verified against the running app rather than assumed from source reading alone, since QA's job is to test the actual player experience, not just whether backend/business logic exists.
