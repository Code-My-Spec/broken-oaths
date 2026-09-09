# Qa Story Brief

## Tool

web

## Auth

Run `mix run priv/repo/qa_seeds_multiplayer.exs` (see Seeds below) — prints two confirmed QA player credentials and a world URL. Log in via `/users/log-in` using the `#login_form_password` form.

Use the `vibium` CLI per `.code_my_spec/qa/plan.md`'s Tools Registry (prefer it over MCP `browser_*` tools — non-functional this session, see issue 5be3616e).

## Seeds

    mix run priv/repo/qa_seeds_multiplayer.exs

Two confirmed QA players, joined and founded, mutual discovery pre-seeded — satisfies `two_players_discovered_each_other`.

## What To Test

This story shares its underlying mechanic entirely with story 996 (Conduct a War): both exercise `GameLive.Play`'s `declare_war` event and the same `war-hostile-*`/`declare-war-required`/`hostile-border-entry` data-test markers. Story 996 QA (this session, issue 8fb548d0) already found there is NO `phx-click="declare_war"` or other UI trigger anywhere in `lib/broken_oaths_web/` — confirm this holds for this story's specific angle too:

- **Criterion 3114 (declares war through diplomacy):** Look for a "Declare War" affordance in the Known Players panel, Alliance panel, or anywhere diplomacy actions live. Expect: none found (per issue 8fb548d0).
- **Criterion 3115 (closed-border movement prompts a declaration of war):** Move a unit into a rival's territory without being at war. Expect the `declare-war-required` banner to appear (this part DOES work — `border_entry_status/3` in play.ex correctly detects and blocks the crossing). Then look for a way to act on that prompt — expect none.
- **Criterion 3116 (a declared war permits border crossing):** Requires war to already be active, which is unreachable through the UI per the above — cannot be tested end-to-end.

## Result Path

No result.md — findings go through `create_issue`, and the run closes with `mcp__plugin_codemyspec_local__submit_qa_result`.

## Setup Notes

Do not refile the missing-declare-war-button issue — reuse 8fb548d0-1c2c-418a-9807-daa7b7c3904c (filed against story 996 this session) since it's the identical root cause blocking this story's criteria too.
