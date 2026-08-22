# QA Story 924: Stone Age Technology Tree

Run a full QA session for this story. Two phases: write a testing brief,
then execute it. The playbook below has the detailed procedure.

**App URL:** Run `mix run -e 'IO.puts(BrokenOathsWeb.Endpoint.url())'`.

## Story description

As a player, I want to research technologies, so that I can unlock new units and buildings and advance toward the Bronze Age.

## Acceptance criteria

- Bigger cities research faster
- Science banks toward the chosen tech until it completes
- The tree lists the Ancient-era techs with their costs
- Mining speeds up worker mines
- Pottery unlocks the granary
- Bronze Working asks before committing
- Research progress is visible
- Switching research and returning loses nothing
- Animal Husbandry unlocks pastures on animal resources
- Bronze Working stays locked until Mining is done
- Finishing a prerequisite unlocks its followers
- The tree makes prerequisites and state obvious

## BDD spec files

- `test/spex/902_stone_age_technology_tree/criterion_7625_bigger_cities_research_faster_spex.exs`
- `test/spex/902_stone_age_technology_tree/criterion_7626_science_banks_toward_the_chosen_tech_until_it_completes_spex.exs`
- `test/spex/902_stone_age_technology_tree/criterion_7627_the_tree_lists_the_ancient_era_techs_with_their_costs_spex.exs`
- `test/spex/902_stone_age_technology_tree/criterion_7628_mining_speeds_up_worker_mines_spex.exs`
- `test/spex/902_stone_age_technology_tree/criterion_7629_pottery_unlocks_the_granary_spex.exs`
- `test/spex/902_stone_age_technology_tree/criterion_7630_bronze_working_asks_before_committing_spex.exs`
- `test/spex/902_stone_age_technology_tree/criterion_7631_research_progress_is_visible_spex.exs`
- `test/spex/902_stone_age_technology_tree/criterion_7642_switching_research_and_returning_loses_nothing_spex.exs`
- `test/spex/902_stone_age_technology_tree/criterion_7643_animal_husbandry_unlocks_pastures_on_animal_resources_spex.exs`
- `test/spex/902_stone_age_technology_tree/criterion_7710_bronze_working_stays_locked_until_mining_is_done_spex.exs`
- `test/spex/902_stone_age_technology_tree/criterion_7711_finishing_a_prerequisite_unlocks_its_followers_spex.exs`
- `test/spex/902_stone_age_technology_tree/criterion_7712_the_tree_makes_prerequisites_and_state_obvious_spex.exs`

## Linked component: TechPanel

This story is implemented by `BrokenOathsWeb.GameLive.TechPanel` (liveview_component).
Reading the source code and spec will help you understand what to
test and how the feature works.

- Tests: `test/broken_oaths_web/live/game_live/tech_panel_test.exs`
- Spec: `.code_my_spec/spec/broken_oaths_web/game_live/tech_panel.spec.md`
- Source: `lib/broken_oaths_web/live/game_live/tech_panel.ex`

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

Write the brief to `.code_my_spec/qa/924/brief.md` matching this spec exactly.
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