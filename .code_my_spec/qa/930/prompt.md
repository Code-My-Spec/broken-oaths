# QA Story 930: Tribute Payments

Run a full QA session for this story. Two phases: write a testing brief,
then execute it. The playbook below has the detailed procedure.

**App URL:** Run `mix run -e 'IO.puts(BrokenOathsWeb.Endpoint.url())'`.

## Story description

As a lord, I want to set the tribute my vassals owe — gold and military levies — and collect it each turn, so that I can tune extraction against loyalty and profit from my conquests while keeping vassals in the game.

## Acceptance criteria

- Lord raises a vassal's tribute rate from the Vassals panel
- Vassal earning 12 gold/turn at 25% pays 3 gold tribute
- A raised rate is applied on the next turn's tribute
- Vassal with an empty treasury goes into debt paying tribute
- Vassal answers a call to arms and keeps command of the units sent
- Vassal refuses the call to arms and takes strain and Honor hits
- Many vassal tributes resolve in one turn tick

## BDD spec files

- `test/spex/908_tribute_payments/criterion_7673_lord_raises_a_vassals_tribute_rate_from_the_vassals_panel_spex.exs`
- `test/spex/908_tribute_payments/criterion_7674_vassal_earning_12_goldturn_at_25_pays_3_gold_tribute_spex.exs`
- `test/spex/908_tribute_payments/criterion_7675_a_raised_rate_is_applied_on_the_next_turns_tribute_spex.exs`
- `test/spex/908_tribute_payments/criterion_7676_vassal_with_an_empty_treasury_goes_into_debt_paying_tribute_spex.exs`
- `test/spex/908_tribute_payments/criterion_7677_vassal_answers_a_call_to_arms_and_keeps_command_of_the_units_sent_spex.exs`
- `test/spex/908_tribute_payments/criterion_7678_vassal_refuses_the_call_to_arms_and_takes_strain_and_honor_hits_spex.exs`
- `test/spex/908_tribute_payments/criterion_7679_many_vassal_tributes_resolve_in_one_turn_tick_spex.exs`

## Linked component: Tribute

This story is implemented by `BrokenOaths.Feudal.Tribute` (module).
Reading the source code and spec will help you understand what to
test and how the feature works.

- Tests: `test/broken_oaths/feudal/tribute_test.exs`
- Spec: `.code_my_spec/spec/broken_oaths/feudal/tribute.spec.md`
- Source: `lib/broken_oaths/feudal/tribute.ex`

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

Write the brief to `.code_my_spec/qa/930/brief.md` matching this spec exactly.
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