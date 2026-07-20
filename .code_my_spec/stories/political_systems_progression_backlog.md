# Political Systems Progression — BACKLOG (DEFERRED)

> ⏸️ **DEFERRED — do NOT import to CodeMySpec / do NOT build yet.**
> Parked as a backlog epic alongside the **God layer** stories (also deferred —
> see the feudal design bible's "God-layer interaction with political systems:
> deferred" note). Captured here in full so nothing is lost; slot in only after
> the decision to build it is made.

## Why this is deferred (decision 2026-07-20)

The plan is to **ship the current rebellion/vassalage feature, demo it, get real
users, and refine from feedback** before building this ladder. Reasoning:

- **The core thesis is already testable with what exists.** This epic's two
  invariants — *player autonomy always preserved* and *always give-and-take* —
  are exactly what the shipped vassalage + rebellion loop embodies. §4 of the
  epic says outright that Feudalism/Vassalage "is essentially the existing MVP
  mechanic, age-gated." So the demo already validates the most important
  question (is a persistent conquer → vassalize → strain → rebel → independence
  loop fun?). If users love it, the whole 7-tier ladder is de-risked cheaply; if
  not, we've avoided building six more tiers on a shaky base.
- **It's large and not fully locked.** Seven tiers, each with real sub-systems
  (governor/viceroy administrator, colonial tech-uplift, federation
  mega-projects, hegemony soft-power). Several ride on machinery that's thin or
  absent today (discrete ages *driving* mechanics, age-gap routing, peace
  settlements, defection/poaching). Open questions remain tentative (age labels,
  the one-age conversion threshold, admin-vs-feudalism line).
- **Nothing shipping now contradicts the ladder.** Current vassalage maps cleanly
  onto tier 4 (Feudalism), behind `:feudal_enabled`. When age-gating is added
  later, the existing mechanic slots in as the Feudalism rung with no rip-out.

**Framing note for whoever picks this up:** treat the current, shipped vassalage
+ rebellion system as **the Feudalism tier of this ladder**. This epic is the
work of adding the *other* tiers (Raiding, Conquest, Administration, Colonialism,
Federalism, Hegemony) and the age-gating that routes between them.

The one arguably-cheap early slice worth reconsidering first is **Stone-age
Raiding + basic alliances (§1)** — the game starts in the Stone Age and currently
has no political verb until vassalage is reachable, so early-game is a bit inert.
Still net-new work; better validated by watching real users hit that dead air.

---

## Political Systems Progression — User Stories

Stories for the age-gated political relationship systems. Written non-technical
for LLM handoff. Companion to the **Political Systems Progression — Outline**
(below).

**Note on scope:** Feudalism/Vassalage largely already exists from the MVP. Those
stories focus only on what changes when it becomes an *age-gated* tier (age
requirement, defection/poaching, conquest→vassalage bridge). Everything else is
net-new.

### 0. Foundation: Ages & Relationship Determination

#### 0.1 Players Have a Discrete Age
**As** the game world **I want** each player to sit in one specific age at any
time **So that** age gaps between players are simple to compute and drive
political mechanics.
- Every player has a current age (Stone, Bronze, Iron, … through later tiers)
- Age advances through tech progression, not elapsed time
- A player's age is a single discrete value, always known
- Two players can be in different ages simultaneously
- The gap between any two players = difference in their age values

#### 0.2 Relationship Type Determined by Conqueror's Age and the Gap
**As** the game world **I want to** automatically select the correct political
tool when one player defeats another **So that** the mechanic always fits the two
players' relative advancement.
- On a control-establishing win, check the conqueror's age and the age gap
- **Gap of 2+ ages** (conqueror ahead) → **Colonialism**
- Otherwise conqueror's age decides: Stone → Raiding, Bronze → Conquest, Iron →
  Administration, Feudalism-age → Vassalage, etc.
- Only the applicable UI/options are presented; inapplicable tools hidden
- Both players notified which relationship was established

#### 0.3 Relationships Convert as Ages Advance
**As** a player whose situation changes over time **I want** existing
relationships to convert to the appropriate tier as ages advance **So that** the
political structure stays consistent with current advancement.
- Colonized player catches up to **one age behind** the metropole → colonialism
  **converts to vassalage** *(tentative rule — confirm)*
- Other natural conversions follow the same principle
- Conversions notify both players and adjust tribute/terms to the new defaults

### 1. Stone Age — Raiding

#### 1.1 Raid an Enemy City for Spoils
Attack and defeat a city's defenses; on success extract spoils (gold,
production, and/or population). The enemy **keeps the city** — no occupation, no
control transfer, no ongoing relationship. Possibly a short-lived skim effect;
spoils to be tuned.

#### 1.2 Alliances & Basic Diplomacy
Declare war, make peace, coordinate via the existing chat/diplomacy layer. No
tribute, no vassalage — purely peer relationships; alliances informal/social
(backed by chat), consistent with the MVP approach.

### 2. Bronze Age — Conquest

#### 2.1 Conquer and Hold a City
Defeat a city into a **held** state. The enemy still owns/runs the city but you
hold it and extract **heavy tribute** (large share of output each turn). Holding
is per-city. No contract — a pure military hold.

#### 2.2 Garrison-or-Lose
A held city requires the conqueror to move a military unit into/through it every
**X turns (≈20)**. Fail to maintain presence → the hold lapses and the city
reverts to full owner control. Makes wide conquest expensive to maintain; gives
the conquered a natural reclaim window.

#### 2.3 No Defection, No Negotiated End
Bronze conquest has no defection or settlement mechanics (there is no contract).
No negotiated peace — holding resolves purely by military presence. A hold ends
only when the conqueror lapses on garrisoning or the conquered reclaims
militarily. **Exception bridge:** a *stronger, feudalism-capable* third party may
offer vassalage to the conquered (see 4.3) — that's the later system reaching in,
not conquest offering defection.

### 3. Iron Age — Administration (Governors)

#### 3.1 Appoint a Governor Over a Held City
When holding a city, appoint a **governor** (appointed administrator) granting
**bonuses that benefit the conquered** (production, happiness) in exchange for
**reduced tribute**. More stable than raw conquest; no constant garrison
babysitting. This governor is the **same administrator system** later reused as
the colonial viceroy.

#### 3.2 Peace Settlements
Either side can propose a settlement to end a war (tribute arrangements, gold,
other conditions). Both must agree or the war continues. The diplomatic off-ramp
Bronze conquest lacks.

#### 3.3 Conquered Player Retains Their Cities
The conquered keeps owning/operating their cities; the governor overlays bonuses
and reduced tribute without stripping owner control. Consistent with the autonomy
invariant.

### 4. Feudalism — Vassalage (age-gated changes to the existing MVP mechanic)

#### 4.1 Vassalage Requires the Feudalism Age
The full MVP vassalage mechanic becomes available at the feudalism age; below it,
players use raiding/conquest/administration. When applicable, vassalage presents
its normal terms (moderate tribute, commands, rebellion, etc.).

#### 4.2 Defection / Poaching
A stronger/rival lord can extend a vassalage offer to a player who is already
someone else's vassal. If accepted, they **switch lords** (new lord's terms
replace the old); the former lord is notified and loses that vassal's
tribute/obligations. This is what makes good treatment matter; defection lives
only in the relationship tiers, never in conquest.

#### 4.3 Defect Out of Conquest Into Vassalage
A feudalism-capable third party can offer vassalage to a player currently held
under Bronze conquest. If accepted, the player becomes that third party's vassal,
and the new lord + freshly-vassalized player are positioned to **fight off the
original conqueror** together — the classic "enemy of my enemy" flip.

### 5. Colonialism

#### 5.1 Colonialism Triggers on a 2+ Age Gap
Defeating a player **2+ ages behind** establishes **colonialism** automatically
(instead of conquest/vassalage) — a simple discrete-age comparison. Both notified.

#### 5.2 Appoint a Viceroy
Appoint a **viceroy** — the **same administrator system** as the Iron Age
governor, reused at range. Grants **bonuses** to the colonized territory
(production, happiness, research speed); the colonial power collects **moderate
tribute**.

#### 5.3 Colonized Player Retains Full Autonomy
The colonized player retains full autonomy — city management, internal
development, military, all normal actions. Colonialism adds tribute + viceroy
bonuses + tech access on top; it does not subtract agency.

#### 5.4 Tech Access / Uplift
The colonized player can request and receive technology from the metropole,
accelerating their advancement (uplift). Core give-and-take: the metropole
extracts tribute, but the colony grows toward parity.

#### 5.5 Catch-Up Converts Colonialism to Vassalage
When the colonized player reaches **one age behind** the metropole, colonialism
**converts to vassalage** *(tentative — confirm)*; terms shift to vassalage
defaults, both notified. Reflects the colony maturing into a peer-like tributary.

### 6. Federalism

#### 6.1 Form a Federation
Near-peer players opt into a voluntary union willingly. **No tribute between
members** — cooperative, not extractive. Members can leave.

#### 6.2 Pooled Military & Unified War
Members coordinate/pool military forces; the federation can act as a single bloc
in war, stronger than any individual member.

#### 6.3 Mega-Projects
Federations unlock **mega-projects** (space programs, grand wonders) requiring
coordinated multi-player investment — the payoff that makes deep cooperation
worthwhile.

### 7. Hegemony

#### 7.1 Become a Hegemon
A top-tier power recognized as dominant; others defer by consent. **No direct
control and no tribute** — influence rests on goodwill. Multiple competing
hegemons can coexist (rival blocs).

#### 7.2 Rally Civilization-Scale Action
A hegemon can rally united action (civilization-level mega-projects, coordinated
wars, crusades) — the top of the cooperation ladder, participation by consent.

### Open Questions (carried from the outline)
1. **Back-half age ladder** — finalize names/count of ages from feudalism onward
   (mechanics + order locked; labels not).
2. **Catch-up conversion threshold** — confirm colonialism → vassalage at exactly
   one age behind (tentative).
3. **Administration vs. feudalism distinction** — keep Iron Age administration
   meaningfully distinct from feudal vassalage (held relationship + appointed
   administrator vs. contractual relationship with the original ruler +
   commands/defection).

---

## Political Systems Progression — Outline

### Core Idea
As players advance through ages, their **political toolkit evolves**. Each age
unlocks a new way of relating to conquered or allied players. Older systems don't
just get replaced — they become **strategically inferior**, so players naturally
migrate toward newer systems the way real societies did. The through-line is a
march from brutal extraction toward voluntary cooperation, with each tier
unlocking bigger collective capabilities.

**Two invariants hold across every tier:**
1. **Player autonomy is always preserved** — a conquered/administered/colonized
   player never loses the ability to keep playing and run their own cities. Even
   under colonialism, they retain full autonomy over everything they normally do.
2. **There's always give-and-take** — being on the losing end is never purely
   negative; some benefit always flows back down (bonuses, tech access,
   protection).

The system also solves the **asymmetry problem**: when a strong player meets a
much weaker one, raw vassalage would just crush the weaker player and make them
quit. The age-gated tiers (especially colonialism) exist so mismatched encounters
still produce a playable, engaging relationship for both sides.

### Ages
Players each sit in a **specific, discrete age** (driven by tech progression, not
wall-clock time). Because each player's age is a concrete value, the **gap
between any two players is trivial to compute** — this drives which political
tool applies when they clash.

**Locked age → mechanic assignments:**
- **Stone Age → Raiding**
- **Bronze Age → Conquest**
- **Iron Age → Administration** (governors)

**Later ages (mechanics locked, exact age names/ordering still to finalize):**
- **Feudalism / Vassalage**, **Colonialism**, **Federalism**, **Hegemony**

*(The back half of the age ladder — names and count from feudalism onward — isn't
nailed down. The mechanics and their order are; labels can be settled later.)*

### The Progression

**Stone Age — Raiding.** Alliances and basic diplomacy via chat (declare war,
make peace, coordinate); fight barbarians and each other; **raid** enemy cities
for spoils (gold, production, population); enemy **always keeps their city**; no
formal relationship/contract/hold. The tribal phase: peers raiding peers.

**Bronze Age — Conquest.** Occupy and hold **individual cities** (enemy still
owns/runs them, you hold and extract); **heavy tribute** — the most extractive
tier; **garrison-or-lose** every ≈20 turns; purely military — **no contract, no
defection, no negotiated end**; scales badly on purpose (many garrisons to
babysit).

**Iron Age — Administration (Governors).** The bureaucratic answer to "direct
rule doesn't scale." **Peace settlements** unlock (negotiated war ends); appoint
a **governor** that **benefits the conquered** (local bonuses) in exchange for
**reduced tribute**; more stable, less extractive, no garrison babysitting. The
governor system is the **same administrator reused later as the colonial
viceroy**.

**Feudalism — Vassalage.** The **relationship tier** — a formal, contractual bond
rather than a military hold. Vassal retains **full autonomy**; **moderate
tribute**; lord can **command** (vassal can refuse at a favor/tension cost);
**rebellion** (mistreated vassals accumulate discontent and can rebel — ties to
existing MVP tension + rebellion mechanics); **defection** (a stronger rival can
**poach** your vassal). Scales far better than conquest *if* you treat vassals
well. **Defect-under-conquest bridge** as in 4.3. *(Essentially the existing MVP
vassalage mechanic, now an age-gated tier.)*

**Colonialism.** Triggers on a large age gap (**2+ ages** → colonialism instead
of conquest/vassalage). Appoint a **viceroy** (same administrator as the Iron Age
governor, at range). Colonized player **retains full autonomy**. Give-and-take
built in: **tech access/uplift** + **viceroy bonuses**. **Catch-up conversion** to
vassalage at ~one age behind *(tentative)*. Purpose: make lopsided-age encounters
**fun for both sides** instead of an instant crush-and-quit.

**Federalism.** Voluntary **union of near-peer powers** (join willingly, can
leave). **No tribute between members.** Pool military; wage **unified war**;
unlock **mega-projects** (space programs, grand wonders). The game shifts from
"who dominates whom" to "what can we build together."

**Hegemony.** **Soft-power dominance** without formal control — one power
recognized as hegemon, others defer by consent. Hegemon can rally
civilization-level action (mega-projects, coordinated wars, crusades). Multiple
competing hegemons possible. The **top of the cooperation ladder**.

### The Central Design Pattern
Each tier trades **extraction** for **stability + scale**, and each cooperative
tier unlocks **bigger collective capabilities**:

| Tier | Tribute | Stability | Conquered keeps | Unlocks |
|------|---------|-----------|-----------------|---------|
| Raiding | One-time spoils | N/A | Everything | — |
| Conquest | Heavy | Low (needs garrison) | Their cities | — |
| Administration | Reduced | Medium | Cities + governor bonuses | Peace settlements |
| Feudalism | Moderate | High (if treated well) | Full autonomy | Many vassals, commands, defection |
| Colonialism | Moderate | High | **Full autonomy** + tech access + bonuses | Cross-age play, tech uplift |
| Federalism | None | Voluntary | Full sovereignty | Mega-projects |
| Hegemony | None | Consent-based | Full sovereignty | Civilization-scale projects |

The game **teaches itself**: conquest doesn't scale, feudalism scales better,
cooperation scales best — and cooperation is the only path to the most ambitious
end-game achievements.

### Historical Grounding
Raiding → tribal raids/alliances; Conquest → early empires collapsing under
overextension; Administration → provincial governors; Feudalism → autonomy for
local lords in exchange for tribute + service; Colonialism → viceroys over
distant less-advanced territories with uplift flowing back; Federalism → voluntary
pooling of sovereignty; Hegemony → soft-power blocs.

### Cross-Age Interactions (the interesting part)
- Different players sit in different ages simultaneously (tech, not wall-clock)
- The tool used is determined by the conquering player's age and the age gap
- **Defection chains:** a player held under conquest can be offered vassalage by a
  stronger third party and switch, flipping the local balance of power
- **Upgrade/downgrade paths:** conquest → administration → vassalage →
  independence/federation; colonialism → vassalage as the gap closes to one age

### Resolved Decisions Log
- **Custom age track** (not Civ 6): Stone → Bronze → Iron → … (later ages TBD).
  Stone = Raiding, Bronze = Conquest, Iron = Administration.
- **Governor and Viceroy are the same system** — one appointed-administrator
  mechanic, reused for Iron Age administration and colonial rule.
- **Colonialism preserves full autonomy**; colonized gains tech access + viceroy
  bonuses on top.
- **Colonialism trigger = a gap of 2 or more ages** (trivial discrete comparison).
- **Colonialism → Vassalage conversion** at ~one age behind *(tentative)*.
- **Raiding** (Stone): spoils only, city always retained by owner.
- **Conquest** (Bronze): hold individual cities, garrison-or-lose ≈20 turns,
  heavy tribute, **no defection, no negotiated end** — pure military hold.
- **Administration** (Iron): peace settlements unlock; governor benefits the
  conquered for reduced tribute.
- **Feudalism/Vassalage**: relationship tier; moderate tribute, commands +
  refusal, rebellion, and **defection** (poaching lives here). Essentially the
  existing MVP mechanic, age-gated.
- **Federalism**: voluntary peer unions, no tribute, unlocks mega-projects.
- **Hegemony**: soft-power dominance enabling civilization-scale projects.
- **God-layer interaction with political systems: deferred** — not being
  considered right now (parked alongside this epic).
