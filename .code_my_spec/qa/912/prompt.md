# QA Story 912: Worker Improves Terrain

Run a full QA session for this story. Two phases: write a testing brief,
then execute it. The playbook below has the detailed procedure.

**App URL:** Run `mix run -e 'IO.puts(BrokenOathsWeb.Endpoint.url())'`.

## Story description

As a player, I want to build workers to improve hexes, so that my cities generate more resources.

## Acceptance criteria

- A worker is a builder, not a fighter
- Three turns of digging turns grassland into a farm
- A worker helps a friend by farming their land
- An abandoned dig waits patiently for the next shovel
- A finished mine pays its city and refuses a second improvement
- A fresh worker comes with three charges
- Three farms and the worker is spent
- An abandoned dig costs no charge
- The charge count is on the selected worker
- Roads are free of charge

## BDD spec files

- `test/spex/882_worker_improves_terrain/criterion_7481_a_worker_is_a_builder_not_a_fighter_spex.exs`
- `test/spex/882_worker_improves_terrain/criterion_7482_three_turns_of_digging_turns_grassland_into_a_farm_spex.exs`
- `test/spex/882_worker_improves_terrain/criterion_7483_a_worker_helps_a_friend_by_farming_their_land_spex.exs`
- `test/spex/882_worker_improves_terrain/criterion_7484_an_abandoned_dig_waits_patiently_for_the_next_shovel_spex.exs`
- `test/spex/882_worker_improves_terrain/criterion_7485_a_finished_mine_pays_its_city_and_refuses_a_second_improvement_spex.exs`
- `test/spex/882_worker_improves_terrain/criterion_7697_a_fresh_worker_comes_with_three_charges_spex.exs`
- `test/spex/882_worker_improves_terrain/criterion_7698_three_farms_and_the_worker_is_spent_spex.exs`
- `test/spex/882_worker_improves_terrain/criterion_7699_an_abandoned_dig_costs_no_charge_spex.exs`
- `test/spex/882_worker_improves_terrain/criterion_7700_the_charge_count_is_on_the_selected_worker_spex.exs`
- `test/spex/882_worker_improves_terrain/criterion_7709_roads_are_free_of_charge_spex.exs`

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

Write the brief to `.code_my_spec/qa/912/brief.md` matching this spec exactly.
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