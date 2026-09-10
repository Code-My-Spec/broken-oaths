# Qa Story Brief

## Tool

web

## Auth

Run `mix run priv/repo/qa_seeds_multiplayer.exs` (see Seeds below) — prints two confirmed QA player credentials and a world URL. Log in via `/users/log-in` using the `#login_form_password` form.

Use the `vibium` CLI per `.code_my_spec/qa/plan.md`'s Tools Registry (prefer it over MCP `browser_*` tools — see known issue 5be3616e filed this session, browser automation was non-functional in this session).

## Seeds

    mix run priv/repo/qa_seeds_multiplayer.exs

Creates two confirmed QA players already joined and founded in the same fast-turn world, mutual discovery pre-seeded — satisfies `two_players_discovered_each_other`, the shared precondition for all three criteria.

## What To Test

- **Baseline check first:** `GameLive.Play` DOES implement `handle_event("declare_war", %{"neighbor_user_id" => ...}, socket)` (`lib/broken_oaths_web/live/game_live/play.ex:874`), and `board_overlays.ex` renders both a `data-test="war-hostile-#{user_id}"` marker once war is active and a `data-test="declare-war-required"` banner ("Declare war before entering this territory") when a move is blocked by lack of war. `feudal_top_bar.ex` renders a read-only `data-test="at-war-with"` badge. However, a full source search of `lib/broken_oaths_web/` turns up **no** `phx-click="declare_war"` anywhere — no button, link, or context-menu entry that fires the event. Confirm this empirically: log in as Player A, open the Known Players panel and Alliance panel, and look for ANY affordance to declare war on Player B (a known neighbor). Also try moving a unit onto Player B's territory (this should surface the `declare-war-required` banner per `border_entry_status/3`) and check whether that banner offers a follow-up action to actually declare war.
- **Criterion 3120 (declaring war establishes a wartime relationship):** If a UI affordance is found, use it and confirm both players see the rival marked hostile / an "At war with X" badge. If no affordance exists, this criterion cannot be exercised by a real player.
- **Criterion 3121 (wartime units cross a rival's territory):** With war established (if reachable), queue a unit move onto the rival's territory and confirm it's accepted (no `declare-war-required` banner, unit enters).
- **Criterion 3122 (a wartime player fights for a rival city):** With war established (if reachable), move a Warrior adjacent to the rival's city and use the existing "attack" affordance (`target_city_id`) — this one IS wired to real UI per prior QA sessions (story 906 issues). Confirm a combat report appears.

## Result Path

No result.md — findings go through `create_issue`, and the run closes with `mcp__plugin_codemyspec_local__submit_qa_result`.

## Setup Notes

The BDD spex files (`test/spex/56_conduct_a_war/*.exs`) drive `declare_war` via `render_hook` directly against the LiveView process, bypassing the DOM. Since `handle_event` for `declare_war` DOES exist (unlike story 994's Open Borders), those render_hook calls succeed at the LiveView level — but that doesn't establish a real player can reach the same event by clicking anything, since the search above found no matching `phx-click`. This needs empirical browser confirmation, not just source reading.
