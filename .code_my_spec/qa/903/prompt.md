# QA Story 903: New Player Spawns in World

Run a full QA session for this story. Two phases: write a testing brief,
then execute it. The playbook below has the detailed procedure.

**App URL:** Run `mix run -e 'IO.puts(BrokenOathsWeb.Endpoint.url())'`.

## Story description

As a new player, I want to spawn with a settler and lord unit in an unexplored region of the hex globe, so that I can begin building my civilization from a safe starting position.

Source: .code_my_spec/stories/stone_age.md §1.1, trimmed to the pre-city substrate: joining an active world (or creating one), spawn placement far from existing players on valid terrain, the two starting units (Lord with crown icon, Settler), 50 starting gold, and the map centering on the spawn point. City founding, barbarians, and the welcome flow build on this in a later batch.

## Acceptance criteria

- Registered player picks a world and spawns
- Picking a world that just filled up fails gracefully
- Re-entering a joined world never re-spawns
- Returning player resumes where their civilization is
- Playing in two worlds at once
- Spawn delivers a Lord and a Settler on workable land
- Fresh spawn shows 50 gold
- A fourth world join is refused at the cap
- Abandoning wipes the civilization and reopens the region
- An abandoned region is a fresh start for its next claimant

## BDD spec files

- `test/spex/873_new_player_spawns_in_world/criterion_7412_registered_player_picks_a_world_and_spawns_spex.exs`
- `test/spex/873_new_player_spawns_in_world/criterion_7413_picking_a_world_that_just_filled_up_fails_gracefully_spex.exs`
- `test/spex/873_new_player_spawns_in_world/criterion_7414_re-entering_a_joined_world_never_re-spawns_spex.exs`
- `test/spex/873_new_player_spawns_in_world/criterion_7415_returning_player_resumes_where_their_civilization_is_spex.exs`
- `test/spex/873_new_player_spawns_in_world/criterion_7416_playing_in_two_worlds_at_once_spex.exs`
- `test/spex/873_new_player_spawns_in_world/criterion_7417_spawn_delivers_a_lord_and_a_settler_on_workable_land_spex.exs`
- `test/spex/873_new_player_spawns_in_world/criterion_7418_fresh_spawn_shows_50_gold_spex.exs`
- `test/spex/873_new_player_spawns_in_world/criterion_7437_a_fourth_world_join_is_refused_at_the_cap_spex.exs`
- `test/spex/873_new_player_spawns_in_world/criterion_7439_abandoning_wipes_the_civilization_and_reopens_the_region_spex.exs`
- `test/spex/873_new_player_spawns_in_world/criterion_7440_an_abandoned_region_is_a_fresh_start_for_its_next_claimant_spex.exs`

## Linked component: Join

This story is implemented by `BrokenOathsWeb.GameLive.Join` (liveview).
Reading the source code and spec will help you understand what to
test and how the feature works.

- Tests: `test/broken_oaths_web/live/game_live/join_test.exs`
- Spec: `.code_my_spec/spec/broken_oaths_web/game_live/join.spec.md`
- Source: `lib/broken_oaths_web/live/game_live/join.ex`

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

Write the brief to `.code_my_spec/qa/903/brief.md` matching this spec exactly.
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