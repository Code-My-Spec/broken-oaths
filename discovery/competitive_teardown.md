# Competitive Teardown — GoHighLevel migration services

*Source: web research on live GHL migration providers + GHL platform docs, June 2026.
Pairs with `opportunity_brief.md`.*

## Who's in the market (it's SERVICES, not products)

Established done-for-you GHL migration shops, e.g. hireghldeveloper.com,
netpartners.marketing, clonepartner.com, penninetechnolabs.com. No dominant
*software* product — the field is agencies/freelancers doing it by hand.

## What they actually do (the 6-step playbook, confirmed identical everywhere)

1. **Audit** existing CRM — map data, integrations, automations
2. **Prepare GHL snapshot** — preload funnels/campaigns/automations
3. **Import contacts & data** — CSV: contacts, pipelines, custom fields, tags
4. **Rebuild automations as GHL workflows** — the hard, manual step
5. **Test & validate** — QA every workflow with a live contact before cutover
6. **Client onboarding & training**

## Pricing (the ceiling, confirmed across sources)

| Tier | Price | Scope |
|------|-------|-------|
| Basic | $300–$800 | contacts, single pipeline, starter automations |
| Standard | $800–$3,000 | full setup, workflows, funnels, campaigns |
| Enterprise | $3,000–$10,000+ | multiple pipelines, custom integrations, white-label |

Consensus "done-for-you" band: **$1,500–$5,000 one-time.** Timeline **3–7 days simple,
2–4 weeks full.** Platform itself: $97/$297/$497/mo.

## THE key insight — where the value (and defensibility) actually is

Every source independently says the same thing, and it's the crux:

> **Contact data moves via CSV (easy, partly commoditized by GHL itself).
> Automations CANNOT transfer — they must be REBUILT BY HAND, because each platform
> uses a different logic structure. Old CRMs are "static"; GHL is "dynamic
> multi-channel." "Lift & shift rarely works — upgrade during rebuild."**

So:
- **The data-move is NOT the moat.** GHL ships CSV import; freelancers do it cheap.
  An "AI that moves contacts" competes with free.
- **The workflow rebuild IS the pain, the time, and the money** — and it's *judgment*
  work (re-architecting static automations into GHL's dynamic model), which is exactly
  the frontier where an LLM could be differentiated vs. a CSV importer.
- Secondary moat: **field mapping** (GHL is contact-centric; sources flag relational
  CRMs like Salesforce as the breakage point) and **QA/validation** (testing every
  workflow with a live contact — tedious, automatable).

## What this means for the wedge

A naive "AI migration tool" loses (commodity data-move, $0 native import, cheap
freelancers). A tool that **rebuilds workflows** — ingest the source CRM's automations,
re-architect them into GHL's dynamic workflow model, and auto-QA them — attacks the
expensive, manual, judgment-heavy step nobody has productized. That's the defensible slice.

For agencies (the repeat buyer), the pitch isn't "cheaper migration" — it's
**"onboard each new client in hours, not 2–4 weeks, without your senior person
hand-rebuilding workflows every time."**

## Risks this surfaced

- **GHL platform risk:** they already commoditized import; they could move up into
  workflow-mapping. Defensibility = depth of cross-CRM workflow translation + agency
  workflow-library network effects.
- **Trust/liability:** botched workflow migration breaks a client's live marketing.
  Agencies may not hand that to AI without heavy QA/human-in-loop. (Validate in interviews.)
- **Price ceiling:** $1.5–5k one-time caps per-deal revenue → business must be
  volume/repeat (agencies) or climb to retainer, not one-off SMB migrations.
