# QA Story 908: Settler Founds City

Run a full QA session for this story. Two phases: write a testing brief,
then execute it. The playbook below has the detailed procedure.

**App URL:** Run `mix run -e 'IO.puts(BrokenOathsWeb.Endpoint.url())'`.

## Story description

As a player, I want to use my settler to found a city, so that I can begin producing resources and units.

Source: .code_my_spec/stories/stone_age.md §2.1 plus more_stories.md §4.2: select the settler and found a city on valid terrain (not ocean/mountains, not too close to another city); the settler is consumed and a size-1 city appears with a default, renameable name; the city claims surrounding territory and can immediately begin production. The stone_age source also triggers barbarian camp spawning on the FIRST city — that consequence belongs to the future barbarian stories, not this one.

## Acceptance criteria

- A settler founds a city on the grassland it stands on
- Founding too close to an existing city is refused with a reason
- Founding trades the settler for a working size-1 city on the spot
- A fresh city in open land claims exactly seven tiles
- A neighbor founded at minimum spacing never steals claimed tiles
- A new city is named by default and renameable

## BDD spec files

- `test/spex/878_settler_founds_city/criterion_7461_a_settler_founds_a_city_on_the_grassland_it_stands_on_spex.exs`
- `test/spex/878_settler_founds_city/criterion_7462_founding_too_close_to_an_existing_city_is_refused_with_a_reason_spex.exs`
- `test/spex/878_settler_founds_city/criterion_7463_founding_trades_the_settler_for_a_working_size-1_city_on_the_spot_spex.exs`
- `test/spex/878_settler_founds_city/criterion_7464_a_fresh_city_in_open_land_claims_exactly_seven_tiles_spex.exs`
- `test/spex/878_settler_founds_city/criterion_7465_a_neighbor_founded_at_minimum_spacing_never_steals_claimed_tiles_spex.exs`
- `test/spex/878_settler_founds_city/criterion_7466_a_new_city_is_named_by_default_and_renameable_spex.exs`

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

Write the brief to `.code_my_spec/qa/908/brief.md` matching this spec exactly.
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