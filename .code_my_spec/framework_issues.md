# Framework issues — pending create_issue (tool 401s: "Invalid deploy key")

Collected during the 2026-07-13 project bring-up session. Each entry is
ready to file with `create_issue` (`scope: framework`) once the deploy
key problem is fixed.

## 1. create_issue returns 401 "Invalid deploy key" (severity: high)
`create_issue` with `scope: framework` fails with `Remote API returned
401: Invalid deploy key`, while sibling MCP tools (create_persona,
evaluate_task, start_task) work in the same session and
`/api/bootstrap/auth/status` shows authenticated. The engineer supplied
a deploy key described as "for the CodeMySpec integration"; there is no
documented place to register it locally and no docs on which key
create_issue uses. The failure blocks the exact workflow the tool
description mandates ("your FIRST call is create_issue").

## 2. devops_setup assumes greenfield provisioning (severity: medium)
The prompt mandates a Hetzner API token and provisioning server/DNS/
Postgres/proxy from scratch. This user already runs a documented
two-box fleet (~/Documents/github/devops/) and the correct action was
joining it; the engineer had to interrupt and redirect. Suggest a
discovery step: ask whether existing infrastructure or a devops runbook
repo exists, and if so switch to reuse mode where the fleet's scripts
and conventions are authoritative. The "exactly three credentials, once,
up front" contract was wrong on two of three counts here (no Hetzner
token needed; AWS root was local so IAM users were created, not
collected).

## 3. devops_setup /health contract vs kamal /up convention (severity: low)
Done signal requires verifying `/health`, but kamal-proxy probes `/up`
over plain HTTP. Resolved by serving both from one endpoint plug —
prompt should standardize or explain both. Related trap worth a warning
in the prompt: phx.gen.auth-era `config/prod.exs` ships `force_ssl`
(x_forwarded_proto rewrite) which 301s the proxy's plain-HTTP probe and
fails the deploy with "target failed to become healthy" — cost one full
build/deploy cycle to diagnose.

## 4. "Proceed without further input" conflicts with permission-gated
     environments (severity: medium)
devops_setup instructs: collect credentials once, then "proceed through
server, DNS, secrets, and deploy without further input or questions."
Claude Code's permission classifier independently gates DNS writes,
prod DB provisioning, secret-store writes, and production deploys, each
requiring the user to name the action. The workflow should anticipate
staged approvals: enumerate the privileged actions up front so the user
can approve them as a named batch, instead of promising a no-input run
that stalls repeatedly.

## 5. Approvals via AskUserQuestion are invisible to the permission
     classifier (severity: medium)
A user answered "Yes, seed all 12" to an AskUserQuestion (from their
phone), but the subsequent bash call was still denied with "the agent's
AskUserQuestion proposing this was not answered." Only a typed user
message satisfies the classifier. Workflow docs (and the devops_setup
prompt) should tell agents to request typed approval for
classifier-gated actions rather than using question prompts.

## 6. project_setup evaluate_task reports all steps unchecked despite
     completed work (severity: low)
After completing all 12 setup steps, `evaluate_task` returned "Needs
work (11 steps remaining)" with every step unchecked except one; the
stop-hook validation then passed unchanged moments later. Either
evaluate_task should run the same checks as the stop hook or its
response should say validation is deferred — the false "needs work"
invites pointless rework.

## 7. Setup checklist references a :spex compiler the hex release lacks
     (severity: medium)
project_setup's compiler config includes `:spex`, but sexy_spex 0.1.0
(the only hex release) has no `Mix.Tasks.Compile.Spex`; the fleet's
projects all pin `{:sexy_spex, github: "JediLuke/spex", branch: "main",
only: :test}`. The checklist should specify the github pin (or the hex
package should ship the compiler) — as written, `mix compile` fails in
test env with "task compile.spex could not be found".

## 8. cms_gen.integrations is not re-run-safe and its early steps
     scroll off (severity: low)
Re-invoking `mix cms_gen.integrations` (e.g. to re-read its printed
instructions) hits an interactive overwrite prompt and aborts under
non-TTY execution. Steps 1–2 of its output (deps + base config) were
lost to scrollback with no way to re-print them; recovered by
inspecting a sibling project. Generators should support a
`--print-instructions` (no-op) mode and be idempotent by default.

## 10. architecture_design initial mode did not auto-execute the proposal
      (severity: medium)
The initial-mode prompt says "Stop. The evaluator runs validate + execute
atomically" — but after writing proposal.md and stopping (twice, across
turns), no specs appeared and no feedback came back. Manual
`execute_proposal` + `evaluate_task` was required. Either the stop-hook
executor didn't fire for this requirement, or the promised auto-execution
doesn't exist; the engineer had to notice missing specs themselves.

## 11. Proposal type enum rejects 'genserver' but nothing documents the
      allowed list up front (severity: low)
The architecture_proposal document spec embedded in the prompt shows
Types like context/schema/liveview in examples but never lists the full
enum; a `genserver` child type (a natural designation for a WorldServer)
failed validation only at execute time. The valid list (context, schema,
module, liveview, liveview_component, live_context, controller,
component, channel, plug, infrastructure) should appear in the prompt's
format section.

## 9. Plugin hook mangles piped `mix test` invocations (severity: medium)
With the codemyspec plugin active, `mix test 2>&1 | tail -5` fails with
"Paths given to mix test did not match any directory/file: 2>&1, |,
tail, -5" — shell operators are passed to the task as literal args
(hook rewrites the command). Plain `mix test` works. Cost several
confusing failures; agents routinely pipe test output.
