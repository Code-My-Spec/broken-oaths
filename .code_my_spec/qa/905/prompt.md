# QA Story 905: Queue Movement Orders

Run a full QA session for this story. Two phases: write a testing brief,
then execute it. The playbook below has the detailed procedure.

**App URL:** Run `mix run -e 'IO.puts(BrokenOathsWeb.Endpoint.url())'`.

## Story description

As a player, I want to select a unit and queue a movement order to an adjacent hex between turns, so that my units move when the turn processes.

## Acceptance criteria

- Clicking your lord shows the unit panel
- A settler walks a three-hex path: two hexes now, the third after the recharge
- A path blocked mid-journey halts the unit without losing it
- Only the latest remaining path executes
- Ocean and mountains refuse a land unit
- Two units racing for the same hex resolve to one occupant
- You cannot path onto your own unit
- An order into the fog of war is legal: right-clicking an unexplored spot on the globe queues a move there (the client sends the clicked sphere point; the server resolves the tile, since the fog-filtered client can't name tiles it has never seen), and the unit travels through unexplored terrain to reach it.
- A queued order's remaining path renders from the unit to its destination and shrinks as the unit walks

## BDD spec files

- `test/spex/875_queue_movement_orders/criterion_7424_clicking_your_lord_shows_the_unit_panel_spex.exs`
- `test/spex/875_queue_movement_orders/criterion_7425_a_settler_walks_a_three-hex_path_over_two_turns_spex.exs`
- `test/spex/875_queue_movement_orders/criterion_7426_a_path_blocked_mid-journey_halts_the_unit_without_losing_it_spex.exs`
- `test/spex/875_queue_movement_orders/criterion_7427_only_the_last_order_before_the_boundary_counts_spex.exs`
- `test/spex/875_queue_movement_orders/criterion_7428_ocean_and_mountains_refuse_a_land_unit_spex.exs`
- `test/spex/875_queue_movement_orders/criterion_7429_two_units_racing_for_the_same_hex_resolve_to_one_occupant_spex.exs`
- `test/spex/875_queue_movement_orders/criterion_7430_you_cannot_path_onto_your_own_unit_spex.exs`
- `test/spex/875_queue_movement_orders/criterion_7441_an_order_into_the_fog_of_war_walks_the_unit_through_unexplored_terrain_spex.exs`
- `test/spex/875_queue_movement_orders/criterion_7442_a_queued_orders_remaining_path_renders_and_shrinks_as_the_unit_walks_spex.exs`

## Linked component: UnitPanel

This story is implemented by `BrokenOathsWeb.GameLive.UnitPanel` (liveview_component).
Reading the source code and spec will help you understand what to
test and how the feature works.

- Tests: `test/broken_oaths_web/live/game_live/unit_panel_test.exs`
- Spec: `.code_my_spec/spec/broken_oaths_web/game_live/unit_panel.spec.md`
- Source: `lib/broken_oaths_web/live/game_live/unit_panel.ex`

## Available scripts

Reference these by path in the brief instead of inlining commands:

- `/Users/johndavenport/Documents/github/broken_oaths/.code_my_spec/qa/scripts/board_click.sh`
- `/Users/johndavenport/Documents/github/broken_oaths/.code_my_spec/qa/scripts/board_state.sh`

## Required reading: QA plan

Read `.code_my_spec/qa/plan.md` first. It contains the App Overview, Tools
Registry, auth strategy, and Seed Strategy you need before writing the
brief. The plan is produced and maintained by the `qa_setup` task; if
it's missing or incomplete, the evaluator will tell you to run that
task first.

## Read the playbook

Read these via the `read_knowledge` MCP tool:

- `qa_story/workflow.md` — two-phase procedure (brief, test), tool
  rules (`:browser` vs `:api` pipelines), testing approach, and what
  the evaluator does when you stop.
- `qa-tooling.md` — testing tool patterns and selection.
- Tool-specific cheat sheets under `qa-tooling/` (browse with
  `list_knowledge`, then read individual entries).

## Brief format spec

Write the brief to `.code_my_spec/qa/905/brief.md` matching this spec exactly.
The evaluator validates the brief structure on stop.

# Qa Story Brief

Per-story QA testing brief. Written by the QA planner after reading the story's prompt file and the QA plan. Gives the tester exact instructions — tool, auth, seeds, what to test.

## Required Sections

### Tool

Format:
- Use H2 heading
- Single line: tool name (web, curl, or script path)

Content:
- Which tool to use for this story's testing
- `web` for LiveView pages, `curl` or script path for controller/API routes


### Auth

Format:
- Use H2 heading
- Exact commands or instructions the tester copies verbatim

Content:
- Login URL, credentials, headers — whatever the tool needs
- Reference auth scripts from the QA plan if applicable
- Tester should not need to figure out auth on their own


### Seeds

Format:
- Use H2 heading
- Exact commands to run

Content:
- Seed script references (`mix run priv/repo/qa_seeds.exs`)
- Any story-specific seed commands beyond the base seeds
- Entity IDs or values the tester will need


### What To Test

Format:
- Use H2 heading
- Bullet list of specific test scenarios

Content:
- Specific URLs to visit
- Interactions to perform (click, fill form, submit)
- Expected outcomes (what the tester should see)
- Map to acceptance criteria from the story


### Result Path

Format:
- Use H2 heading
- Single line: file path

Content:
- Where the tester writes the result document


## Optional Sections

### Setup Notes

Format:
- Use H2 heading
- Free-form paragraphs

Content:
- Additional context, prerequisites, known issues



## Findings and done signal

Every finding you uncover during execution gets filed via
`mcp__plugin_codemyspec_local__create_issue` **as you find it** — not
written into a markdown file. Capture the title, severity, scope, and a
short description; the call returns an issue id. Hold those ids.

When you finish the session, call
`mcp__plugin_codemyspec_local__submit_qa_result` with the structured
scenarios payload **and** every issue id you filed:

    mcp__plugin_codemyspec_local__submit_qa_result(
      task_id: <task_id>,
      status: "pass" | "partial" | "fail",
      scenarios: [%{name: "...", status: "pass|partial|fail", observation: "..."}, ...],
      issue_ids: [<every id returned from create_issue>]
    )

Discipline:

- **`status: "pass"`** with `issue_ids: []` is fine.
- **`status: "partial"` or `"fail"`** with `issue_ids: []` is **rejected
  by the tool**. A failure with no filed issue is a finding that just
  disappeared when your session ended — there's nowhere else for it to
  live. File the issues first, then submit.
- The bare `submit_qa_result` (without the `mcp__plugin_codemyspec_local__`
  prefix) does NOT resolve — use the fully-qualified name.
- Attribution follows automatically: on submit, every `scope: app` issue
  you listed is attached to this story, and `story_issues_resolved` holds
  the story's release until they're fixed. `framework`, `qa` and `docs`
  findings are about the tooling rather than the story, so they queue at
  the project level instead. If an issue belongs to a *different* story,
  pass that `story_id` on the `create_issue` call — an explicit
  attribution is never overwritten.
- Don't write findings into a result.md file. The harness doesn't read it.
  Screenshots and other evidence still belong on disk, but the canonical
  record is the DB attempt + linked issues.