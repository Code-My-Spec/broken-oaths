# Broken Oaths: hero stats

*Collected 2026-07-30 for the case study. Sources named per row so every number is
re-derivable. Nothing here is rounded up.*

## The headline: what John typed vs what the machine wrote

Computed with `code_my_spec_marketing/.code_my_spec/playbooks/conversation-share.py`
over the build session `ad271113-c1ad-440a-a29a-27c61fde9cd0` and its 227 subagent
transcripts.

| Scope | John typed | Machine wrote | John's share |
|---|---|---|---|
| Main build conversation | 58,535 chars | 4,933,904 chars | **1.17%** |
| Including all 227 subagents | 58,535 chars | 23,284,503 chars | **0.25%** |

- 206 genuine human messages in the main conversation, 58,535 characters total.
- The all-in agent figure adds the 608,537 characters of subagent prompts, which the
  orchestrator wrote, not John. Per the playbook's correction, those count as machine
  output, so the human numerator does not move.
- Agent output breaks down as 907,558 chars of assistant text and 4,026,346 chars of
  tool-call input (the code) in the main session; 3,108,570 and 19,567,396 all-in.
- Thinking chars register as 0: this session predates thinking capture in the
  transcript format. The real machine total is therefore understated.

**Compare Cleaner CRM: 3,923 human chars vs 1,027,791 agent = 0.4% (0.07% all-in).**
Broken Oaths' human share is *higher*, and the reason is not harness regression. This is
a passion project John had been planning for years and intended to play himself, so he
gave far more notes than on a client CRM. Read the percentage as a measure of how much he
cared. Do not frame it as the harness needing more help.

**A third input channel: real playtesters.** From July 20 John recruited players and
routed their reports in through the in-game feedback widget. Roughly 20 commits reference
playtest or user-reported issues (`f578c18`, `bb7a0c4`, `62509c2`, `883ea9f`, `a3a3bb8`,
`b3cafa6` and more). Individual reports carry ids: "playtest issue 2a9df843" became the
display-name feature (`ca82749`). Some of the human characters in the count above are
other people's bug reports relayed by John, not his own opinions.

## Build shape

| Metric | Value | Source |
|---|---|---|
| Total commits | 275 (271 through the sprint, 4 on Jul 30) | `git log --oneline \| wc -l` |
| First commit | 2026-03-19 | `git log --reverse` |
| Last commit | 2026-07-30 (project is active, not stopped) | `git log` |
| Commits in the July 12-25 sprint | 253 (92%) | `git log --since=2026-07-01` |
| Distinct commit days, all time | 16 | `git log --format=%ai \| cut -c1-10 \| sort -u` |
| Distinct commit days, July sprint | 12 | same, since 2026-07-01 |
| Peak day | 44 commits (Jul 13) | per-day count |

Monthly distribution: Mar 4 · May 2 · Jun 12 · Jul 253. The build is a **12-day
sprint** with a four-month exploratory prologue, not a four-month project.

July daily: 12th 8 · 13th 44 · 14th 35 · 16th 27 · 17th 22 · 18th 33 · 19th 25 ·
20th 34 · 21st 21 · 23rd 1 · 24th 1 · 25th 2. No commits on the 15th or 22nd.

## Codebase

| Metric | Value |
|---|---|
| Tracked files | 1,630 |
| Elixir LOC (`.ex` + `.exs`) | 108,734 |
| JavaScript LOC | 1,642 |
| `.ex` files | 184 |
| `.exs` files | 443 |
| Spex (BDD spec) files | 279 |
| Files under `test/` | 390 |
| Game art PNGs | 709 |
| Aseprite sources | 13 |

## Harness records

From the local CMS CLI DB `~/.codemyspec/cli.db`, project
`1a71fe74-f809-4d51-8d4a-45979e4e943a`.

| Record | Count |
|---|---|
| Stories | 52 |
| Acceptance criteria | 387 |
| BDD rules | 285 |
| Three Amigos questions | 145 |
| Personas | 3 |
| Components | 171 |
| Sessions | 7 |
| QA attempts | 55 |
| Subagents dispatched | 227 |

**QA attempts by outcome: 32 pass · 19 partial · 4 fail.** Only 58% of QA attempts
passed first look. That number belongs in "The Bad" and it is the most honest stat
on this page.

Personas: Gem-Weary Wes, Ledger-Minded Mara, Rushdown Rhea.

### QA coverage, stated precisely

| Fact | Value |
|---|---|
| Stories whose final QA attempt passed | 32 of 52 (62%) |
| Stories with **zero** QA attempts on record | **20 of 52 (38%)** |
| Acceptance criteria marked `verified` in the DB | **0 of 387** |

Those last two rows are the honest headline of this build, and they contradict what
the case-study tooling would print. See the next section.

## The fixture script fabricated three fields (now patched)

`code_my_spec_marketing/.code_my_spec/playbooks/extract-stories-fixture.py` did not
derive these from the database. It hard-coded them:

| Line | Emits | Reality for Broken Oaths |
|---|---|---|
| 45 | `status: :completed` | all 52 stories are `in_progress` |
| 52 | `verified: true` on every criterion | 0 of 387 criteria are `verified` |
| 58 | `qa: %{final: :pass, ...}` | 20 of 52 stories have no QA attempt at all |

Run unmodified against Broken Oaths, it would publish an all-green page: 52 completed
stories, 387 verified criteria, every story passing QA. Three of those claims are
false and the third is false for 20 stories.

**This is not a Broken Oaths problem.** The same script produced the shipped
MetricFlow, Market My Spec and Cleaner CRM fixtures, so those pages carry the same
three unverified claims. Worth an audit pass separately from this case study.

**Fixed.** The script now derives `status` from `stories.status`, `verified` from
`criteria.verified`, and `qa.final` from the last `qa_attempts.status`, with an explicit
`:untested` state when a story has no attempts. It also takes the project id and output
path as arguments instead of hard-coded constants, and prints the untested and unverified
counts on every run so the gaps cannot be missed.

## Step 2 output

`code_my_spec/lib/code_my_spec_web/live/content_live/pages/broken_oaths_stories.exs`,
generated and validated against the DB:

```
stories: 52   criteria: 387   rules: 285   questions: 145
qa final: %{pass: 32, untested: 20}
status:   %{in_progress: 52}
```

## Notes for whoever writes the copy

- `git log --format=%an` reports 255 John / 16 Claude, but that is git config on an
  agent-driven repo. **Do not use author attribution as a human-effort signal**; the
  character share above is the real measure.
- The stories modal in `cleaner_crm.ex` renders `story.qa.history` as badges. For the 20
  untested stories that history is empty, so the modal will show a blank QA row rather
  than saying "never tested." Add an explicit untested badge when building
  `broken_oaths.ex`, or the page under-reports the gap it is supposed to be honest about.
- Playbook Step 4 says to copy `market_my_spec.ex` as the page template. That is stale:
  `market_my_spec.ex` renders no QA at all. `cleaner_crm.ex` is the newer pattern with
  complete records and QA badges, so start from that one.
