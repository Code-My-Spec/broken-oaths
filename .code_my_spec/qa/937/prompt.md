# QA Story 937: Declare Independence and Free Your Cities

Run a full QA session for this story. Two phases: write a testing brief,
then execute it. The playbook below has the detailed procedure.

**App URL:** Run `mix run -e 'IO.puts(BrokenOathsWeb.Endpoint.url())'`.

## Story description

As a vassal, I want declaring independence to launch a real, first-class war of liberation, so that subjugation is never permanent — my cities rise to me based on how my lord ruled, and a temporary uprising rallies to fight it.

## Acceptance criteria

- Declaring independence severs the oath and opens war
- Vassal previews which cities will rise before committing
- A risen city de-occupies and its garrison defects
- A tyrant's cities rise and a grievance army rallies
- A just lord's cities stay loyal and little rises
- Cities that stay loyal must be taken by siege, and the lord is notified
- Declaring independence opens a tracked rebellion

## BDD spec files

- `test/spex/915_declare_independence_and_free_your_cities/criterion_7731_declaring_independence_severs_the_oath_and_opens_war_spex.exs`
- `test/spex/915_declare_independence_and_free_your_cities/criterion_7732_vassal_previews_which_cities_will_rise_before_committing_spex.exs`
- `test/spex/915_declare_independence_and_free_your_cities/criterion_7733_a_risen_city_de-occupies_and_its_garrison_defects_spex.exs`
- `test/spex/915_declare_independence_and_free_your_cities/criterion_7734_a_tyrants_cities_rise_and_a_grievance_army_rallies_spex.exs`
- `test/spex/915_declare_independence_and_free_your_cities/criterion_7735_a_just_lords_cities_stay_loyal_and_little_rises_spex.exs`
- `test/spex/915_declare_independence_and_free_your_cities/criterion_7736_cities_that_stay_loyal_must_be_taken_by_siege_and_the_lord_is_notified_spex.exs`
- `test/spex/915_declare_independence_and_free_your_cities/criterion_7747_declaring_independence_opens_a_tracked_rebellion_spex.exs`

## Linked component: War

This story is implemented by `BrokenOaths.Feudal.Rebellion.War` (module).
Reading the source code and spec will help you understand what to
test and how the feature works.

- Tests: `test/broken_oaths/feudal/rebellion/war_test.exs`
- Spec: `.code_my_spec/spec/broken_oaths/feudal/rebellion/war.spec.md`
- Source: `lib/broken_oaths/feudal/rebellion/war.ex`

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

Write the brief to `.code_my_spec/qa/937/brief.md` matching this spec exactly.
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