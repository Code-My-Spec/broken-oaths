# Delivery SOP — running a GHL migration (and harvesting the build spec)

Two jobs at once: **(1) deliver a clean migration → 5-star review. (2) Log where the
work is API-automatable vs. forced manual — THAT log is the product spec.** Fill the
"automation log" column every time; after ~5 jobs it tells you exactly what to build.

## API reality (confirmed — set expectations)

- **Contacts/fields/pipelines:** API-automatable on most platforms + GHL. (The easy,
  commodity half — GHL's CSV import already does much of it.)
- **Workflow/automation DEFINITIONS:** uneven. HubSpot exposes them (`/automation/v4/flows`);
  Keap/Dubsado/Honeybook largely don't. **GHL cannot fully author multi-step workflows via
  API** — expect UI work in the GHL workflow builder. This is the hard, valuable, partly-manual step.
- GHL: V1 API end-of-life (Dec 2025), rate limit 100 req/10s.

→ **v1 = you + scripts as copilot, NOT a product.** Automate the data-move; do workflow
rebuild by hand; log everything.

---

## Phase 0 — Before you accept (scoping call)

Confirm and write down:
- [ ] Source CRM + exact plan/tier (decides what's API-exportable)
- [ ] **# of active workflows/automations** (the real effort driver — not # of contacts)
- [ ] # contacts, # custom fields, # pipelines
- [ ] Integrations to preserve (Zapier/Make, payments, LMS, Twilio, calendars)
- [ ] Do they have admin/API access to the source? (Get it early.)
- [ ] Go-live date + who tests/signs off
- [ ] **Scope boundary in writing** — what's NOT included (prevents scope creep killing margin)

## Phase 1 — Audit & backup
- [ ] Full export/backup of source data BEFORE touching anything (CSV + API dump)
- [ ] Screenshot/document every source workflow (you'll rebuild from these)
- [ ] Map source fields → GHL contact-centric model (note relational→flat losses, e.g. HubSpot associations)
- [ ] List automations by priority — which MUST work at go-live vs. nice-to-have

## Phase 2 — Data migration (the automatable half)
- [ ] Clean/dedup contacts (note: AI-assistable)
- [ ] Import contacts, custom fields, tags into GHL
- [ ] Import pipelines → opportunities, preserving relationships
- [ ] Spot-check a sample against source for accuracy
- [ ] **Automation log:** which steps did you script vs. hand-do? Time each.

## Phase 3 — Workflow rebuild (the valuable, partly-manual half)
- [ ] Rebuild each priority automation as a GHL workflow (email/SMS/wait/conditional)
- [ ] Re-establish integrations (Zapier/Make, Twilio, payments, LMS)
- [ ] "Upgrade during rebuild" — don't lift-and-shift; improve where obvious (clients love this)
- [ ] **Automation log (the gold):** per workflow — could the source DEFINITION be read via
      API? Did LLM-translation of the logic help or hallucinate? Was GHL authoring API or UI?
      How long did it take by hand? ← this is your product spec.

## Phase 4 — QA & cutover (where trust is won/lost)
- [ ] Test EVERY workflow with a live test contact — confirm each email/SMS/wait/branch fires
- [ ] Parallel-run if possible (don't hard-cutover blind)
- [ ] Validate no leads/contacts dropped; counts reconcile source↔GHL
- [ ] Client walkthrough + sign-off before old system is killed

## Phase 5 — Handoff & review
- [ ] Short Loom walkthrough of what was built (clients value this; justifies price)
- [ ] Document the GHL setup
- [ ] If agency/repeat buyer: offer to **snapshot** the build for faster next-client onboarding
      (this is the upsell into recurring work)
- [ ] **Ask for the review** explicitly. Early reviews > rate.

---

## After each job — update the meta-spec
- Which platform PAIR was this? Add to a tally (demand signal for which connector to build).
- % of hours that were automatable vs. manual?
- Biggest time-sink? (Likely workflow rebuild — confirm or refute the thesis with data.)
- Would a tool have saved real time here, or was it judgment? (The product/services line.)

**Exit condition (set now):** after ~5 migrations, pick the ONE platform pair with both
demand AND API surface, and build that connector first. Until then, don't build — learn.
