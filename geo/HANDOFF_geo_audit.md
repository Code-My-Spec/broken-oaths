# HANDOFF — Implement the GEO Audit Tool

*For: an implementing agent. From: the discovery session that validated this.*
*Branch: `claude/upwork-actor-bakeoff-RQyyb`. Context files: `geo/*.md`, esp.
`geo/precall_boundaries_io.md` (a worked example of this audit, done by hand).*

---

## What to build (one sentence)

A CLI that takes a URL and emits a **GEO (Generative Engine Optimization) readiness
scorecard** — the automated version of the manual recon in
`geo/precall_boundaries_io.md` — as both human-readable output and JSON.

## Why (so you make good calls)

This is the repeatable core of a service: get small/mid SaaS sites *cited* by
ChatGPT/Perplexity/Claude/Google AI. The audit is used three ways:
1. **Sales asset** — run it on a prospect's site, screen-share the scorecard on the call.
2. **Delivery checklist** — the failing checks ARE the work to be done.
3. **Product seed** — this engine is what a later hosted product wraps.

It was validated by hand against a real prospect (boundaries.io). You are automating
that exact process. Read `geo/precall_boundaries_io.md` first — it is the spec by example.

## Input / Output

```
geo-audit https://example.com [--json out.json] [--quiet]
```
- **Human output:** a scorecard table — each signal: PASS/WARN/FAIL + one-line finding +
  the concrete fix. End with a prioritized "biggest wins" list.
- **JSON output:** `{ url, fetched_at, signals: { <name>: {status, detail, fix} }, score }`
  so it can feed a report generator / product later.

## Signals to check (implement all; these are proven, from the manual audit)

| Signal | How to check | PASS / FAIL logic |
|---|---|---|
| **AI crawler access** | GET `/robots.txt`; parse per user-agent | FAIL if GPTBot, ClaudeBot, anthropic-ai, CCBot, PerplexityBot, Google-Extended, OAI-SearchBot have `Disallow: /`. Note: a UA listed with NO directive = allowed. |
| **Sitemap** | GET `/sitemap.xml` | PASS if 200 + valid XML |
| **Schema.org / JSON-LD** | Parse HTML for `<script type="application/ld+json">` | FAIL if none. Report which @types found (Product, FAQPage, Article, SoftwareApplication, Organization). This is usually the biggest win. |
| **FAQ structured content** | Look for FAQPage schema or Q&A heading patterns | WARN if absent |
| **Title + meta description** | Parse `<title>`, `<meta name=description>` | WARN if missing/empty |
| **Content rendering** | Compare raw HTML body text length vs. presence of SPA root divs | WARN if content appears JS-rendered (AI crawlers may miss it) |
| **Heading structure** | Extract h1-h3; flag question-phrased headings | INFO: are headings answer/question-shaped? |
| **llms.txt** | GET `/llms.txt` | INFO only — report presence, do NOT weight it (contested lever; see the "snake oil" note in the brief) |
| **Platform detection** | `Server` header + asset hosts (squarespace-cdn, etc.) | INFO: report platform (shapes what's fixable — e.g. Squarespace limits schema control) |

Compute a simple weighted score (schema + crawler access weighted highest).

## Tech constraints

- **Language: Python 3.9+, stdlib-only where possible** (urllib, html.parser, json, re).
  The existing discovery tooling (`discovery/sweep.py`, `discovery/discover_score.py`) is
  stdlib-only — match that. An HTML-parsing dep (e.g. `selectolax`/`beautifulsoup4`) is
  acceptable IF you add a requirements file; prefer stdlib `html.parser` if feasible.
- Be polite: one set of requests, ~15s timeouts, real User-Agent, handle 4xx/5xx/timeouts
  gracefully (a dead URL should produce a clean error, not a stack trace).
- No API keys required for v1. (Optional later: GA referral data — out of scope now.)

## Acceptance criteria

1. `geo-audit https://boundaries.io` reproduces the findings in
   `geo/precall_boundaries_io.md`: Squarespace, server-rendered, crawlers allowed,
   sitemap present, **schema=FAIL (none)**, FAQ=WARN, llms.txt=absent.
2. Handles a JS-rendered SPA, a site that blocks AI bots, and a dead URL — each a clean result.
3. `--json` emits valid parseable JSON with all signals.
4. Has a `README` with usage + a sample run.
5. Has at least a few unit tests on the parsers (robots.txt directive parsing, JSON-LD
   extraction) using fixture HTML/robots strings — don't hit the network in tests.

## Out of scope (do NOT build these yet)

- No content *generation* / rewriting (that's the human/tooling step downstream).
- No hosted UI / web app — CLI only.
- No GA / analytics integration.
- No auto-fixing the site. Audit only: it REPORTS, a human acts.

## Repo placement — DECISION NEEDED (flag to the human, don't guess)

This currently lives on a feature branch of `broken-oaths`, an **Elixir/Phoenix app this
work is unrelated to**. Recommend: a **new standalone repo** (`geo-audit` or similar) OR a
clearly-isolated `tools/geo/` dir — not woven into the Phoenix app. Confirm with the human
(johns10) before committing code into the Phoenix project proper.

## Pointers
- `geo/precall_boundaries_io.md` — worked example (the spec by demonstration)
- `geo/opportunity_brief.md` — why this exists, market, the wedge
- `discovery/sweep.py` — reference for stdlib HTTP + CLI style to match
