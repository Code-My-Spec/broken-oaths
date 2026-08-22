# QA Story 948: Workers chop woods and rainforest

Run a full QA session for this story. Two phases: write a testing brief,
then execute it. The playbook below has the detailed procedure.

**App URL:** Run `mix run -e 'IO.puts(BrokenOathsWeb.Endpoint.url())'`.

## Story description

As a user, I want my workers to chop down woods and rainforest to gain a one-time production boost to the nearest city and clear the tile, so I can accelerate a nearby city's builds and open terrain for farms/other improvements.

## Acceptance criteria

- Worker chops a woods tile and a nearby city gains a production lump
- Chop lump advances the city's active build immediately, once
- Chop is offered once the feature-removal tech is researched
- Chop is blocked before the required tech is researched
- Chop only appears on woods/rainforest tiles
- No chop on a featureless tile
- Chopping woods drops the tile's movement cost and removes the woods yield modifier
- Cleared tile becomes eligible for a Farm
- Feature on unowned land cannot be chopped
- Chop allowed on a feature inside the player's borders
- A chop spends one worker charge
- A worker with no charges left cannot chop
- A later-game chop yields a larger lump than an early one
- Chopping a tile the city is working reassigns its citizens next turn
- Cannot chop a tile an enemy unit holds

## BDD spec files

- `test/spex/46_workers_chop_woods_and_rainforest/criterion_2716_worker_chops_a_woods_tile_and_a_nearby_city_gains_a_production_lump_spex.exs`
- `test/spex/46_workers_chop_woods_and_rainforest/criterion_2717_chop_lump_advances_the_citys_active_build_immediately_once_spex.exs`
- `test/spex/46_workers_chop_woods_and_rainforest/criterion_2718_chop_is_offered_once_the_feature-removal_tech_is_researched_spex.exs`
- `test/spex/46_workers_chop_woods_and_rainforest/criterion_2719_chop_is_blocked_before_the_required_tech_is_researched_spex.exs`
- `test/spex/46_workers_chop_woods_and_rainforest/criterion_2720_chop_only_appears_on_woodsrainforest_tiles_spex.exs`
- `test/spex/46_workers_chop_woods_and_rainforest/criterion_2721_no_chop_on_a_featureless_tile_spex.exs`
- `test/spex/46_workers_chop_woods_and_rainforest/criterion_2722_chopping_woods_drops_the_tiles_movement_cost_and_removes_the_woods_yield_modifier_spex.exs`
- `test/spex/46_workers_chop_woods_and_rainforest/criterion_2723_cleared_tile_becomes_eligible_for_a_farm_spex.exs`
- `test/spex/46_workers_chop_woods_and_rainforest/criterion_2724_feature_on_unowned_land_cannot_be_chopped_spex.exs`
- `test/spex/46_workers_chop_woods_and_rainforest/criterion_2725_chop_allowed_on_a_feature_inside_the_players_borders_spex.exs`
- `test/spex/46_workers_chop_woods_and_rainforest/criterion_2726_a_chop_spends_one_worker_charge_spex.exs`
- `test/spex/46_workers_chop_woods_and_rainforest/criterion_2727_a_worker_with_no_charges_left_cannot_chop_spex.exs`
- `test/spex/46_workers_chop_woods_and_rainforest/criterion_2728_a_later-game_chop_yields_a_larger_lump_than_an_early_one_spex.exs`
- `test/spex/46_workers_chop_woods_and_rainforest/criterion_2729_chopping_a_tile_the_city_is_working_reassigns_its_citizens_next_turn_spex.exs`
- `test/spex/46_workers_chop_woods_and_rainforest/criterion_2730_cannot_chop_a_tile_an_enemy_unit_holds_spex.exs`

## Linked component: ClearedFeature

This story is implemented by `BrokenOaths.Worlds.ClearedFeature` (schema).
Reading the source code and spec will help you understand what to
test and how the feature works.

- Tests: `test/broken_oaths/worlds/cleared_feature_test.exs`
- Spec: `.code_my_spec/spec/broken_oaths/worlds/cleared_feature.spec.md`
- Source: `lib/broken_oaths/worlds/cleared_feature.ex`

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

Write the brief to `.code_my_spec/qa/948/brief.md` matching this spec exactly.
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