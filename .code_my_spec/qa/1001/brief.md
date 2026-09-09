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

Unlike stories 995-1000, this story's OWN mechanic appears fully wired to real UI: `feudal_top_bar.ex` renders, per `war_relationships`, an "Offer Peace" form (`phx-submit="offer_peace"`) and an "Accept" button (`phx-click="accept_peace"`, `data-test="accept-peace"`) for the recipient of a pending offer — both correctly scoped to ordinary (non-rebellion) wars per the code's own "Story 1001" comment. The ONLY blocker is the shared precondition: reaching an active war at all requires `declare_war`, which has no UI trigger anywhere (issue 8fb548d0, filed against story 996 this session).

- **Criterion 3123 (a player offers peace to a wartime rival):** Requires an active war first. Expect: blocked at the declare-war step, not at the offer-peace step (that part is wired).
- **Criterion 3124 (both players agree to peace):** Same precondition block.
- **Criterion 3125 (accepted peace ends the war):** Same precondition block.
- **Criterion 3126 (peace preserves wartime conquests):** Same precondition block, plus depends on the occupation mechanic (story 997) which is itself blocked the same way.

If issue 8fb548d0 is fixed before this QA session runs, this story likely passes outright since its own UI is already complete — prioritize re-testing this one first.

## Result Path

No result.md — findings go through `create_issue`, and the run closes with `mcp__plugin_codemyspec_local__submit_qa_result`.

## Setup Notes

Do not refile the missing-declare-war-button issue — reuse 8fb548d0-1c2c-418a-9807-daa7b7c3904c. Do not file a separate issue for offer/accept-peace UI — it is not missing, only unreachable.
