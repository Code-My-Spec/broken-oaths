# QA Story 906: Fog of War and Exploration

Run a full QA session for this story. Two phases: write a testing brief,
then execute it. The playbook below has the detailed procedure.

**App URL:** Run `mix run -e 'IO.puts(BrokenOathsWeb.Endpoint.url())'`.

## Story description

As a player, I want to see only the areas of the globe I have explored, so that the game has discovery and scouting mechanics.

Source: .code_my_spec/stories/stone_age.md §7.1. Three per-player visibility states on the hex globe: unexplored (hidden), explored-but-out-of-vision (terrain remembered, greyed, no live units shown), and currently visible (vision radius around own units — Lord sees farther). The exploration mask is server-owned per player and never leaks hidden tiles to the client; each player sees a different world. Cities extend vision when they arrive in a later batch.

## Acceptance criteria

- A fresh spawn sees a cloud-wrapped planet with one clear bubble
- The Lord out-scouts the Settler
- Terrain stays on the map after the scout moves on
- A stranger in remembered territory is invisible
- Two players see two different worlds
- Hidden tiles never travel over the wire
- Fog cloud and weather cloud read as different things

## BDD spec files

- `test/spex/876_fog_of_war_and_exploration/criterion_7431_a_fresh_spawn_sees_a_cloud-wrapped_planet_with_one_clear_bubble_spex.exs`
- `test/spex/876_fog_of_war_and_exploration/criterion_7432_the_lord_out-scouts_the_settler_spex.exs`
- `test/spex/876_fog_of_war_and_exploration/criterion_7433_terrain_stays_on_the_map_after_the_scout_moves_on_spex.exs`
- `test/spex/876_fog_of_war_and_exploration/criterion_7434_a_stranger_in_remembered_territory_is_invisible_spex.exs`
- `test/spex/876_fog_of_war_and_exploration/criterion_7435_two_players_see_two_different_worlds_spex.exs`
- `test/spex/876_fog_of_war_and_exploration/criterion_7436_hidden_tiles_never_travel_over_the_wire_spex.exs`
- `test/spex/876_fog_of_war_and_exploration/criterion_7438_fog_cloud_and_weather_cloud_read_as_different_things_spex.exs`

## Linked component: Play

This story is implemented by `BrokenOathsWeb.GameLive.Play` (liveview).
Reading the source code and spec will help you understand what to
test and how the feature works.

- Tests: `test/broken_oaths_web/live/game_live/play_test.exs`
- Spec: `.code_my_spec/spec/broken_oaths_web/game_live/play.spec.md`
- Source: `lib/broken_oaths_web/live/game_live/play.ex`

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

Write the brief to `.code_my_spec/qa/906/brief.md` matching this spec exactly.
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